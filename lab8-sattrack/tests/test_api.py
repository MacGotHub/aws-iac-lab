import json
from datetime import datetime, timedelta, timezone

import boto3
import pytest
from moto import mock_aws
from skyfield.api import wgs84

import lambdas.api.handler as api

# Same synthetic TLEs as test_tle_fetcher.py: epoch 26191.5 = 2026-07-10
# 12:00 UTC. Orbit propagation degrades far from the TLE epoch, so tests
# that use "now" rely on this epoch being close to the current date.
ISS_ITEM = {
    "pk": "25544",
    "sk": "TLE",
    "name": "ISS (ZARYA)",
    "line1": "1 25544U 98067A   26191.50000000  .00016717  00000-0  10270-3 0  9008",
    "line2": "2 25544  51.6423 339.8700 0007417  17.6667  85.6479 15.50423408123456",
    "fetched_at": "2026-07-10T12:00:00+00:00",
}
CSS_ITEM = {
    "pk": "48274",
    "sk": "TLE",
    "name": "CSS (TIANHE)",
    "line1": "1 48274U 21035A   26191.50000000  .00025000  00000-0  25000-3 0  9005",
    "line2": "2 48274  41.4750  10.0000 0001000 100.0000 260.0000 15.60000000123456",
    "fetched_at": "2026-07-10T12:00:00+00:00",
}

EPOCH = datetime(2026, 7, 10, 12, 0, tzinfo=timezone.utc)
HOME = wgs84.latlon(26.13, -80.23)


@pytest.fixture(autouse=True)
def api_env(monkeypatch):
    monkeypatch.setenv("TABLE_NAME", "test-table")
    monkeypatch.setenv("HOME_LAT", "26.13")
    monkeypatch.setenv("HOME_LON", "-80.23")
    # Reset the cached table so each test binds to its own moto table.
    monkeypatch.setattr(api, "_table", None)


def seeded_table():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    table = dynamodb.create_table(
        TableName="test-table",
        KeySchema=[
            {"AttributeName": "pk", "KeyType": "HASH"},
            {"AttributeName": "sk", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "pk", "AttributeType": "S"},
            {"AttributeName": "sk", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )
    table.put_item(Item=ISS_ITEM)
    table.put_item(Item=CSS_ITEM)
    return table


def api_event(route_key, norad_id=None, query=None):
    return {
        "routeKey": route_key,
        "pathParameters": {"id": norad_id} if norad_id else None,
        "queryStringParameters": query,
    }


# ---------------------------------------------------------------------------
# Orbit math (deterministic: fixed TLE, fixed time at the TLE epoch)
# ---------------------------------------------------------------------------


def test_current_position_is_physically_plausible():
    t = api.ts.from_datetime(EPOCH)

    position = api.current_position(ISS_ITEM, t)

    assert position["norad_id"] == "25544"
    # Ground track latitude can never exceed the orbital inclination.
    assert abs(position["latitude"]) <= 51.7
    assert -180.0 <= position["longitude"] <= 180.0
    assert 350 < position["altitude_km"] < 500
    assert position["timestamp"] == "2026-07-10T12:00:00Z"


def test_predict_passes_finds_iss_passes_over_home():
    t0 = api.ts.from_datetime(EPOCH)
    t1 = t0 + timedelta(hours=48)

    passes = api.predict_passes(ISS_ITEM, HOME, t0, t1)

    assert len(passes) >= 1
    complete = [p for p in passes if {"rise", "culminate", "set"} <= p.keys()]
    assert len(complete) >= 1
    for p in complete:
        assert p["rise"] < p["culminate"] < p["set"]
        assert p["peak_altitude_deg"] >= 10.0


def test_parse_hours_default_and_bounds():
    assert api.parse_hours({}) == api.DEFAULT_PASS_HOURS
    assert api.parse_hours({"hours": "12"}) == 12

    with pytest.raises(api.ApiError) as exc:
        api.parse_hours({"hours": "banana"})
    assert exc.value.status == 400

    with pytest.raises(api.ApiError) as exc:
        api.parse_hours({"hours": "9999"})
    assert exc.value.status == 400


# ---------------------------------------------------------------------------
# Routing (moto-backed, end to end through handler)
# ---------------------------------------------------------------------------


@mock_aws
def test_list_satellites_route_returns_sorted_names():
    seeded_table()

    response = api.handler(api_event("GET /satellites"), None)

    assert response["statusCode"] == 200
    satellites = json.loads(response["body"])["satellites"]
    assert [s["name"] for s in satellites] == ["CSS (TIANHE)", "ISS (ZARYA)"]
    assert satellites[1]["norad_id"] == "25544"


@mock_aws
def test_positions_route_returns_every_satellite():
    seeded_table()

    response = api.handler(api_event("GET /positions"), None)

    assert response["statusCode"] == 200
    positions = json.loads(response["body"])["positions"]
    assert len(positions) == 2
    for position in positions:
        assert -90 <= position["latitude"] <= 90
        assert -180 <= position["longitude"] <= 180
        assert position["altitude_km"] > 100


@mock_aws
def test_satellite_detail_route():
    seeded_table()

    response = api.handler(api_event("GET /satellites/{id}", "25544"), None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["name"] == "ISS (ZARYA)"
    assert body["fetched_at"] == "2026-07-10T12:00:00+00:00"
    assert "latitude" in body


@mock_aws
def test_tle_route_returns_raw_lines():
    seeded_table()

    response = api.handler(api_event("GET /satellites/{id}/tle", "25544"), None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["line1"] == ISS_ITEM["line1"]
    assert body["line2"] == ISS_ITEM["line2"]


@mock_aws
def test_passes_route():
    seeded_table()

    response = api.handler(
        api_event("GET /satellites/{id}/passes", "25544", {"hours": "24"}), None
    )

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["hours"] == 24
    assert isinstance(body["passes"], list)


@mock_aws
def test_unknown_satellite_returns_404():
    seeded_table()

    response = api.handler(api_event("GET /satellites/{id}", "99999"), None)

    assert response["statusCode"] == 404
    assert "99999" in json.loads(response["body"])["error"]


@mock_aws
def test_bad_hours_returns_400():
    seeded_table()

    response = api.handler(
        api_event("GET /satellites/{id}/passes", "25544", {"hours": "nope"}), None
    )

    assert response["statusCode"] == 400


@mock_aws
def test_unknown_route_returns_404():
    seeded_table()

    response = api.handler(api_event("DELETE /satellites"), None)

    assert response["statusCode"] == 404
