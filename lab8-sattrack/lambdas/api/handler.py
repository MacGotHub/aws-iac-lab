"""SatTrack compute API.

One Lambda behind an API Gateway HTTP API (payload format 2.0) serving:

    GET /satellites               list tracked satellites
    GET /satellites/{id}          details + current position for one satellite
    GET /positions                current positions of every tracked satellite
    GET /satellites/{id}/passes   upcoming passes over the home location
    GET /satellites/{id}/tle      raw TLE lines
"""

import json
import os
from datetime import timedelta

import boto3
from boto3.dynamodb.conditions import Attr
from skyfield.api import EarthSatellite, load, wgs84

# Built once per execution environment and reused across warm invocations.
# load.timescale() uses data files bundled with skyfield -- no network call.
ts = load.timescale()

DEFAULT_PASS_HOURS = 48
MAX_PASS_HOURS = 120
MIN_PASS_ALTITUDE_DEGREES = 10.0

SINGLE_SATELLITE_ROUTES = (
    "GET /satellites/{id}",
    "GET /satellites/{id}/passes",
    "GET /satellites/{id}/tle",
)

_table = None


class ApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def get_table():
    global _table
    if _table is None:
        _table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    return _table


def home_location():
    return wgs84.latlon(float(os.environ["HOME_LAT"]), float(os.environ["HOME_LON"]))


def to_satellite(item: dict) -> EarthSatellite:
    return EarthSatellite(item["line1"], item["line2"], item["name"], ts)


def scan_tle_items(table) -> list[dict]:
    items = []
    kwargs = {"FilterExpression": Attr("sk").eq("TLE")}
    while True:
        response = table.scan(**kwargs)
        items.extend(response["Items"])
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            return items
        kwargs["ExclusiveStartKey"] = last_key


def get_tle_item(table, norad_id: str) -> dict | None:
    return table.get_item(Key={"pk": norad_id, "sk": "TLE"}).get("Item")


def list_satellites(table) -> list[dict]:
    items = scan_tle_items(table)
    satellites = [
        {"norad_id": i["pk"], "name": i["name"], "fetched_at": i["fetched_at"]}
        for i in items
    ]
    return sorted(satellites, key=lambda s: s["name"])


def current_position(item: dict, t) -> dict:
    geocentric = to_satellite(item).at(t)
    lat, lon = wgs84.latlon_of(geocentric)
    return {
        "norad_id": item["pk"],
        "name": item["name"],
        "latitude": round(lat.degrees, 4),
        "longitude": round(lon.degrees, 4),
        "altitude_km": round(wgs84.height_of(geocentric).km, 1),
        "timestamp": t.utc_iso(),
    }


def predict_passes(item: dict, observer, t0, t1) -> list[dict]:
    satellite = to_satellite(item)
    times, events = satellite.find_events(
        observer, t0, t1, altitude_degrees=MIN_PASS_ALTITUDE_DEGREES
    )
    topocentric = satellite - observer

    # find_events yields interleaved codes: 0 = rise, 1 = culminate, 2 = set.
    # Group them into one dict per pass; a pass already in progress at the
    # window edge is kept with its missing fields absent.
    passes = []
    current = {}
    for t, event_code in zip(times, events):
        if event_code == 0:
            current = {"rise": t.utc_iso()}
        elif event_code == 1:
            altitude, _, _ = topocentric.at(t).altaz()
            current["culminate"] = t.utc_iso()
            current["peak_altitude_deg"] = round(altitude.degrees, 1)
        else:
            current["set"] = t.utc_iso()
            passes.append(current)
            current = {}
    if current:
        passes.append(current)
    return passes


def parse_hours(query: dict) -> int:
    raw = query.get("hours", str(DEFAULT_PASS_HOURS))
    try:
        hours = int(raw)
    except ValueError:
        raise ApiError(400, f"hours must be an integer, got '{raw}'")
    if not 1 <= hours <= MAX_PASS_HOURS:
        raise ApiError(400, f"hours must be between 1 and {MAX_PASS_HOURS}")
    return hours


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    route_key = event.get("routeKey", "")
    path_params = event.get("pathParameters") or {}
    query = event.get("queryStringParameters") or {}

    try:
        table = get_table()

        if route_key == "GET /satellites":
            return _response(200, {"satellites": list_satellites(table)})

        if route_key == "GET /positions":
            t = ts.now()
            items = scan_tle_items(table)
            positions = [current_position(item, t) for item in items]
            return _response(200, {"positions": positions})

        if route_key in SINGLE_SATELLITE_ROUTES:
            norad_id = path_params.get("id", "")
            item = get_tle_item(table, norad_id)
            if item is None:
                raise ApiError(404, f"no tracked satellite with NORAD ID '{norad_id}'")

            if route_key == "GET /satellites/{id}":
                body = current_position(item, ts.now())
                body["fetched_at"] = item["fetched_at"]
                return _response(200, body)

            if route_key == "GET /satellites/{id}/tle":
                return _response(
                    200,
                    {
                        "norad_id": item["pk"],
                        "name": item["name"],
                        "line1": item["line1"],
                        "line2": item["line2"],
                        "fetched_at": item["fetched_at"],
                    },
                )

            hours = parse_hours(query)
            t0 = ts.now()
            t1 = t0 + timedelta(hours=hours)
            return _response(
                200,
                {
                    "norad_id": item["pk"],
                    "name": item["name"],
                    "hours": hours,
                    "min_altitude_deg": MIN_PASS_ALTITUDE_DEGREES,
                    "passes": predict_passes(item, home_location(), t0, t1),
                },
            )

        raise ApiError(404, f"unknown route: {route_key}")
    except ApiError as e:
        return _response(e.status, {"error": e.message})
