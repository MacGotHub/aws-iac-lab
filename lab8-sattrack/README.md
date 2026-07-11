# Lab 8 — SatTrack

A serverless satellite tracker: a live CesiumJS 3D globe of satellites, pass
predictions for a home location, and SNS alerts when the ISS (or other
visible satellites) pass overhead.

> **Reconstructed 2026-07-10.** The original brief was lost in a PC crash
> before it was committed. This version is rebuilt from the kickoff message
> that re-specified the project. If anything below doesn't match what was
> actually decided before the crash, fix it here before Phase 1 work
> continues — this file is the source of truth going forward.

## Scope — read this before touching anything

Lab 8 is **standalone and non-VPC by design**.

- Do **not** attach the Lambdas to a VPC.
- Do **not** connect to the inspection VPC / Transit Gateway / Network
  Firewall architecture built in Labs 1–7 (see the root
  [`README.md`](../README.md) and [`docs/architecture.md`](../docs/architecture.md)
  for that architecture — it is unrelated to this lab).
- This is a serverless app, not a network workload. It needs no VPC, NAT
  gateway, or subnet routing.
- Lab 8 does **not** depend on Labs 1–7 being deployed.
- The only possibly-shared resource with the rest of the repo is the
  account-level **GitHub OIDC provider** — check whether one already exists
  in account `351668480009` before creating a new one (see CI/CD section).

## What it does

1. **Live 3D globe** (CesiumJS) showing current satellite positions.
2. **Pass predictions** for home location: Plantation, FL — 26.13°N, 80.23°W.
3. **SNS alerts** when the ISS / other visible satellites pass overhead.

## Stack

| Component | Choice |
|---|---|
| IaC | OpenTofu |
| Compute | Python 3.12 Lambdas |
| Data store | DynamoDB (single table) |
| Frontend hosting | S3 + CloudFront |
| API | API Gateway HTTP API |
| Scheduling | EventBridge schedules |
| Notifications | SNS |
| TLE data source | CelesTrak (no auth required) |
| Region | us-east-1 |
| AWS account | 351668480009 |
| Orbit math | Skyfield (as a Lambda layer) |
| Frontend | CesiumJS, using Cesium ion Community (free) account + Default Token |

## The DevSecOps showcase (resume piece)

GitHub Actions deploys via **OIDC** — no stored AWS keys — with `tflint` and
`checkov` gates on PRs.

- Before creating a GitHub OIDC provider, check whether one already exists in
  account `351668480009` from a prior lab, and reuse it if so.
- Cesium ion Default Token is injected at deploy time via the Actions
  workflow — never hardcoded in committed source.

## Build plan — one phase at a time, plan before apply

1. **TLE data pipeline** — `tle_fetcher` Lambda + EventBridge + DynamoDB + S3.
2. **Compute API** — Skyfield Lambda layer; 5 routes.
3. **CesiumJS frontend** — the globe.
4. **Pass alerts** — daily Lambda → SNS.
5. **CI/CD pipeline** — OIDC + tflint/checkov scanning gates.

Each phase: scaffold code, write tests, build the OpenTofu module, run
`tofu plan` for review — no `tofu apply` without explicit sign-off.

## Status

- [x] Phase 1 — TLE data pipeline (deployed 2026-07-10; DynamoDB table
      `sattrack`, S3 bucket `sattrack-tle-archive-351668480009`, Lambda
      `sattrack-tle-fetcher` on a 2-hour EventBridge schedule, tracking the
      `stations` CelesTrak group — 23 satellites as of first fetch)
- [ ] Phase 2 — Compute API
- [ ] Phase 3 — CesiumJS frontend
- [ ] Phase 4 — Pass alerts
- [ ] Phase 5 — CI/CD pipeline
