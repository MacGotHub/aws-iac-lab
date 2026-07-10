# DESIGN.md — aws-iac-lab Architecture Design Document

**Author:** Derek McWilliams
**Last Updated:** July 2026
**Status:** In Progress

---

## Purpose

This document describes the architecture and design decisions behind the
aws-iac-lab project. It serves as a reference for understanding why things
are built the way they are, and as a guide for extending the lab in the future.

**Scope:** this document covers the **v2 rebuild** happening in
`opentofu/lab-01-vpc/` (GWLB-based centralized inspection). The original v1
architecture (AWS Network Firewall in the hub VPC) still used by labs 02-10
is documented separately in `docs/architecture.md` at the repo root — its
lab-01 section is stale and superseded by this document. For the literal
`tofu init/plan/apply` commands, credentials, and state-backend prerequisites,
see `docs/runbook.md`.

---

## Background

This lab is built to replicate and learn enterprise AWS networking patterns
used in large-scale production environments. The architecture centers on
centralized firewall inspection using Palo Alto VM-Series firewalls behind
AWS Gateway Load Balancers (GWLB).

The lab does not use real firewall instances — the networking plumbing is built
to match production patterns exactly, with firewall instances as a future addition.

---

## Full Topology

```
  "on-prem-east"                            "on-prem-west"
  10.10.0.0/16                              10.20.0.0/16
  (simulated — EC2 StrongSwan)              (simulated — EC2 StrongSwan)
         │ Site-to-Site VPN                        │ Site-to-Site VPN
         │                                         │
  ┌──────▼──────────────────┐        ┌─────────────▼────────────┐
  │   TGW (us-east-1)       │◄──────►│   TGW (us-west-2)        │
  │   tgw-east              │ Peering│   tgw-west               │
  └──────┬──────────────────┘        └─────────────┬────────────┘
         │                                         │
    ┌────┴──────────────┐                   ┌──────┴────────────┐
    │                   │                   │                   │
    ▼                   ▼                   ▼                   ▼
security-vpc       spoke-vpc-east      security-vpc       spoke-vpc-west
us-east-1          10.1.0.0/16         us-west-2          10.2.0.0/16
10.0.16.0/22       (workload)          10.0.20.0/22       (workload)
```

---

## High Level Architecture — Security VPC (per region)

```
                        ┌─────────────────────────────────┐
                        │         Transit Gateway          │
                        │         (us-east-1)              │
                        └────────────┬────────────────────┘
                                     │
                    ┌────────────────▼────────────────────┐
                    │         Security VPC                 │
                    │         security-vpc-us-east-1       │
                    │         10.0.16.0/22                 │
                    │                                      │
                    │  ┌──────────────────────────────┐   │
                    │  │   AZ: us-east-1b              │   │
                    │  │   tgw subnet    10.0.16.0/28  │   │
                    │  │   gwlbe subnet  10.0.16.16/28 │   │
                    │  │   untrust sub   10.0.16.32/28 │   │
                    │  │   trust/mgmt    10.0.16.64/27 │   │
                    │  └──────────────────────────────┘   │
                    │                                      │
                    │  ┌──────────────────────────────┐   │
                    │  │   AZ: us-east-1c              │   │
                    │  │   tgw subnet    10.0.16.96/28 │   │
                    │  │   gwlbe subnet 10.0.16.112/28 │   │
                    │  │   untrust sub  10.0.16.128/28 │   │
                    │  │   trust/mgmt   10.0.16.160/27 │   │
                    │  └──────────────────────────────┘   │
                    │                                      │
                    │  ┌──────────────────────────────┐   │
                    │  │   AZ: us-east-1d              │   │
                    │  │   tgw subnet   10.0.16.192/28 │   │
                    │  │   gwlbe subnet 10.0.16.208/28 │   │
                    │  │   untrust sub  10.0.16.224/28 │   │
                    │  │   trust/mgmt   10.0.17.0/27   │   │
                    │  └──────────────────────────────┘   │
                    └─────────────────────────────────────┘
```

Same pattern is replicated in us-west-2 using 10.0.20.0/22.

---

## Traffic Flow — Inspection Path

This is the most important concept to understand. All spoke VPC traffic
passes through this inspection path before reaching its destination.

```
Step 1: Spoke VPC sends traffic to destination
Step 2: TGW receives traffic, looks up TGW route table
Step 3: TGW route table sends traffic to Security VPC TGW attachment
Step 4: TGW attachment subnet route table:
          0.0.0.0/0 → GWLB endpoint (same AZ — AZ affinity)
Step 5: GWLB endpoint sends traffic to GWLB
Step 6: GWLB load balances to firewall instance in target group
Step 7: Firewall inspects traffic, returns to GWLB
Step 8: GWLB returns traffic to GWLB endpoint
Step 9: GWLB endpoint subnet route table:
          10.0.0.0/8     → TGW
          172.16.0.0/12  → TGW
          192.168.0.0/16 → TGW
Step 10: TGW forwards to destination spoke VPC
```

---

## Route Table Design

### Why per-AZ TGW route tables?

Each TGW attachment subnet has its own route table. The default route in each
points to the GWLB endpoint in the **same AZ**. This is called AZ-affinity
routing and is critical for two reasons:

1. **Cost** — cross-AZ data transfer in AWS is charged. Keeping traffic in
   the same AZ avoids unnecessary charges.
2. **Availability** — if a firewall in one AZ fails, only that AZ is affected.
   Traffic in other AZs continues through their own firewalls uninterrupted.

### Why a shared GWLBE route table?

The GWLB endpoint route table only needs three RFC-1918 summary routes pointing
back to the TGW. These routes are the same regardless of AZ, so one shared
route table is sufficient and simpler to manage.

### Why local-only routing for trust/mgmt subnets?

Firewall management interfaces should not have direct internet or TGW routing.
Management traffic is controlled by the firewall itself. Isolating these subnets
to local-only routing is a security best practice.

---

## Transit Gateway Design

### Two TGWs with peering

One TGW per region. TGW peering connects them for cross-region traffic. All
spoke VPC and VPN traffic is inspected by the Security VPC in its local region
before crossing the peering link.

### TGW route tables (per TGW)

Each TGW needs two route tables:

| Route Table | Attached To | Routes |
|---|---|---|
| `rt-tgw-spokes` | Spoke VPC attachments, VPN attachment | `0.0.0.0/0` → Security VPC attachment |
| `rt-tgw-security` | Security VPC attachment | Spoke CIDRs → spoke attachments, peer CIDR → peering attachment |

The split design forces all spoke and VPN traffic through the Security VPC for
inspection before it can reach any other attachment.

### TGW appliance mode

The Security VPC TGW attachment must have `appliance_mode_support = "enable"`.
Without it, the TGW may route return traffic through a different AZ than the
outbound flow, breaking stateful firewall inspection.

### TGW peering routing

Peering attachments are static — no dynamic routing. Routes for the remote
region's CIDRs must be added manually to each TGW's route tables. Traffic
crossing the peering link must also be inspected, so peering routes live in
`rt-tgw-security` (post-inspection return path) and spokes see only a default
route toward the Security VPC.

---

## VPN / On-Prem Simulation

Two simulated on-prem networks, one per region. Each uses an EC2 instance
running StrongSwan as a software VPN router, placed in its own VPC to simulate
a physically separate network.

| Name | CIDR | Region | VPN target |
|---|---|---|---|
| on-prem-east | 10.10.0.0/16 | us-east-1 | tgw-east |
| on-prem-west | 10.20.0.0/16 | us-west-2 | tgw-west |

### AWS side components
- `aws_customer_gateway` — points to the EC2 instance's public IP
- `aws_ec2_transit_gateway_vpn_attachment` — VPN attached to the TGW directly
- Static routes (BGP is an option but static keeps it simple for the lab)

### EC2 side (StrongSwan)
- Single t3.micro per on-prem VPC
- IPsec tunnel to TGW VPN endpoints
- Routes the on-prem CIDR into the tunnel

VPN traffic follows the same inspection path as spoke traffic — the TGW
`rt-tgw-spokes` table routes VPN attachment traffic to the Security VPC first.

> **Status:** Planned. Not yet implemented.

---

## GWLB and Firewall Inspection

### How GWLB interception works

GWLB operates at Layer 3 using GENEVE encapsulation. It is not a proxy — it
is a transparent bump-in-the-wire. Traffic enters a GWLB Endpoint (GWLBe),
is forwarded to the GWLB, distributed to a firewall in the target group,
returned to the GWLB, and exits back through the same GWLBe. From the route
table's perspective, the GWLBe is just a next-hop `vpce-xxxxxxxx` ID.

### Components

| Resource | Purpose |
|---|---|
| `aws_lb` (type=gateway) | GWLB itself — sits in untrust subnet |
| `aws_lb_target_group` (type=instance) | Firewall instances register here |
| `aws_lb_listener` | Wires GWLB to target group |
| `aws_vpc_endpoint_service` | Publishes GWLB as a consumable endpoint service |
| `aws_vpc_endpoint` (type=GatewayLoadBalancer) | GWLBe — one per AZ, sits in gwlbe subnet |

### Firewall instances

> **Status: Open decision.** Three options under consideration:
>
> 1. **Stub only** — build all GWLB plumbing with empty target groups. Validates
>    routing topology but target group will be unhealthy. No inspection actually occurs.
> 2. **Simulated firewall (EC2)** — t3.micro with iptables forwarding as a stand-in.
>    Lets you test the full GWLB inspection path end-to-end at minimal cost.
> 3. **Palo Alto VM-Series** — matches production exactly. AWS Marketplace free trial
>    available. ~$1.50-2.00/hr per instance when running. Add Ansible day-1 config.
>
> The GWLB infrastructure will be built regardless of which option is chosen.
> Firewall instances can be added later without changing the network plumbing.

---

## CIDR Allocation

All lab resources fit within `10.0.0.0/8` summary space:

| VPC | CIDR | Region | Purpose |
|---|---|---|---|
| hub-vpc | 10.0.0.0/20 | us-east-1 | Management plane |
| security-vpc-us-east-1 | 10.0.16.0/22 | us-east-1 | Inspection VPC |
| security-vpc-us-west-2 | 10.0.20.0/22 | us-west-2 | Inspection VPC |
| spoke-vpc-east | 10.1.0.0/16 | us-east-1 | Workload / connectivity testing |
| spoke-vpc-west | 10.2.0.0/16 | us-west-2 | Workload / connectivity testing |
| on-prem-east | 10.10.0.0/16 | us-east-1 | Simulated on-prem (StrongSwan EC2) |
| on-prem-west | 10.20.0.0/16 | us-west-2 | Simulated on-prem (StrongSwan EC2) |

### Security VPC East (10.0.16.0/22) Subnet Detail

| Subnet | CIDR | AZ | Tier |
|---|---|---|---|
| sub-security-vpc-us-east-1b-tgw | 10.0.16.0/28 | us-east-1b | TGW |
| sub-security-vpc-us-east-1b-gwlbe | 10.0.16.16/28 | us-east-1b | GWLBE |
| sub-security-vpc-us-east-1b-untrust | 10.0.16.32/28 | us-east-1b | Untrust |
| sub-security-vpc-us-east-1b-trust-mgmt | 10.0.16.64/27 | us-east-1b | Trust/Mgmt |
| sub-security-vpc-us-east-1c-tgw | 10.0.16.96/28 | us-east-1c | TGW |
| sub-security-vpc-us-east-1c-gwlbe | 10.0.16.112/28 | us-east-1c | GWLBE |
| sub-security-vpc-us-east-1c-untrust | 10.0.16.128/28 | us-east-1c | Untrust |
| sub-security-vpc-us-east-1c-trust-mgmt | 10.0.16.160/27 | us-east-1c | Trust/Mgmt |
| sub-security-vpc-us-east-1d-tgw | 10.0.16.192/28 | us-east-1d | TGW |
| sub-security-vpc-us-east-1d-gwlbe | 10.0.16.208/28 | us-east-1d | GWLBE |
| sub-security-vpc-us-east-1d-untrust | 10.0.16.224/28 | us-east-1d | Untrust |
| sub-security-vpc-us-east-1d-trust-mgmt | 10.0.17.0/27 | us-east-1d | Trust/Mgmt |

### Security VPC West (10.0.20.0/22) Subnet Detail

| Subnet | CIDR | AZ | Tier |
|---|---|---|---|
| sub-security-vpc-us-west-2b-tgw | 10.0.20.0/28 | us-west-2b | TGW |
| sub-security-vpc-us-west-2b-gwlbe | 10.0.20.16/28 | us-west-2b | GWLBE |
| sub-security-vpc-us-west-2b-untrust | 10.0.20.32/28 | us-west-2b | Untrust |
| sub-security-vpc-us-west-2b-trust-mgmt | 10.0.20.64/27 | us-west-2b | Trust/Mgmt |
| sub-security-vpc-us-west-2c-tgw | 10.0.20.96/28 | us-west-2c | TGW |
| sub-security-vpc-us-west-2c-gwlbe | 10.0.20.112/28 | us-west-2c | GWLBE |
| sub-security-vpc-us-west-2c-untrust | 10.0.20.128/28 | us-west-2c | Untrust |
| sub-security-vpc-us-west-2c-trust-mgmt | 10.0.20.160/27 | us-west-2c | Trust/Mgmt |
| sub-security-vpc-us-west-2d-tgw | 10.0.20.192/28 | us-west-2d | TGW |
| sub-security-vpc-us-west-2d-gwlbe | 10.0.20.208/28 | us-west-2d | GWLBE |
| sub-security-vpc-us-west-2d-untrust | 10.0.20.224/28 | us-west-2d | Untrust |
| sub-security-vpc-us-west-2d-trust-mgmt | 10.0.21.0/27 | us-west-2d | Trust/Mgmt |

---

## OpenTofu Code Design Decisions

### locals.tf is the brain

All structural data — AZ lists, CIDRs, subnet types — lives in `locals.tf`.
Resource files (`vpc_security.tf`, `gwlb.tf`, `tgw.tf`) consume locals via
`for_each`. This means:
- Adding a new AZ = one change in `locals.tf`, everything else updates automatically
- Adding a new region = one new block in `locals.tf`
- No copy/paste of resource blocks

### for_each over count

`for_each` is used instead of `count` for all multi-AZ and multi-region
resources. This is because `for_each` uses stable keys (e.g. `us-east-1b`)
while `count` uses numeric indices. If you remove an AZ from the middle of
a `count` list, Terraform/OpenTofu will destroy and recreate resources
unexpectedly. `for_each` avoids this problem entirely.

### Explicit CIDRs

CIDRs are defined explicitly in `locals.tf` rather than computed with
`cidrsubnet()`. This makes it easy to:
- Cross-reference with what you see in the AWS console
- Review in pull requests without mental math

---

## Build Order and Dependencies

The dependency chain determines the order files must be **written**. OpenTofu
always plans/applies the whole directory, not individual files — so the
workflow is: write the next file, then `tofu validate` / `tofu plan` /
`tofu apply` on the directory, then move to the next file. The exact command
loop (including credential and backend prerequisites, and a warning about the
shared v1 state key) is in `docs/runbook.md`, section 3.

```
vpc_security.tf   (done)
        │
        ▼
gwlb.tf           ← needs Security VPC + subnet IDs
        │
        ▼
tgw.tf            ← needs GWLB endpoint IDs for TGW attachment subnet routes
        │          ← needs Security VPC attachment ID for route tables
        ▼
vpc_spoke.tf      ← needs TGW ID for attachment
        │
        ▼
vpc_onprem.tf     ← needs TGW ID for customer gateway + VPN attachment
        │
        ▼
outputs.tf        ← collects everything
```

---

## File Plan

| File | Status | Description |
|---|---|---|
| `locals.tf` | Done | AZ lists, CIDRs, subnet definitions — the brain |
| `variables.tf` | Done | Environment, region, owner inputs |
| `vpc_security.tf` + `modules/security-vpc/` | Done | Security VPCs, subnets, route tables — one module call per region (provider can't vary per-key in a single for_each) |
| `gwlb.tf` | TODO | GWLB per region, target groups, GWLBe per AZ |
| `tgw.tf` | TODO | Two TGWs, peering, VPC attachments, route tables |
| `vpc_spoke.tf` | TODO | Spoke VPCs (east + west), TGW attachments |
| `vpc_hub.tf` | Done | Hub VPC refactored to for_each pattern, CIDR corrected to 10.0.0.0/20 |
| `vpc_onprem.tf` | TODO | On-prem simulation VPCs, StrongSwan EC2, VPN |
| `outputs.tf` | TODO | VPC IDs, subnet IDs, GWLB ARNs, TGW ID |

Note: the TODO files do not exist yet in the directory — do not go looking
for stubs. Each one is created from scratch when its turn in the build order
comes.

---

## Definition of Done — per remaining file

Concrete verification checklists so "done" is not a judgment call. Every file
must also pass the generic gates: `tofu validate` succeeds; `tofu plan` shows
only the expected `+ create` lines (no surprise destroys/replacements of
already-applied resources); a second `tofu plan` after `tofu apply` reports
"No changes"; all resources use `for_each` driven by `locals.tf`, carry
`merge(local.common_tags, ...)` tags, and follow the naming conventions in
`CLAUDE.md`.

### gwlb.tf — done when:

- [ ] Plan shows, **per region** (x2, using the default and `aws.west`
      providers): 1 `aws_lb` (type `gateway`) spanning that region's untrust
      subnets, 1 `aws_lb_target_group`, 1 `aws_lb_listener`,
      1 `aws_vpc_endpoint_service`, and 1 `aws_vpc_endpoint` (type
      `GatewayLoadBalancer`) **per AZ** in the gwlbe subnets — 3 per region,
      matching the AZ lists in `locals.tf` (us-east-1b/c/d, us-west-2b/c/d).
- [ ] Each per-AZ TGW route table (`module.security_vpc_east/west.tgw_route_table_ids`)
      gets its `0.0.0.0/0` route pointing at the GWLB endpoint **in the same
      AZ** (AZ affinity — key both maps by AZ so this is structural, not
      positional).
- [ ] GWLB endpoint IDs are exposed keyed by AZ (module output or local) so
      `tgw.tf` and future files can consume them without hardcoding `vpce-*` IDs.
- [ ] Expected imperfection: target groups have **no registered targets**
      (firewall instance choice is still an open decision — see "Firewall
      instances" above). Unhealthy/empty target groups are correct at this stage.

### tgw.tf — done when:

- [ ] Plan shows 2 `aws_ec2_transit_gateway` (one per region) plus a peering
      attachment and its accepter.
- [ ] Each security VPC has a TGW VPC attachment using that region's
      `module.security_vpc_*.tgw_subnet_ids`, with
      `appliance_mode_support = "enable"` (required for stateful inspection —
      see "TGW appliance mode" above).
- [ ] Each TGW has the two route tables from "Transit Gateway Design":
      `rt-tgw-spokes` (default route → security VPC attachment) and
      `rt-tgw-security` (spoke CIDRs → spoke attachments; remote-region CIDRs
      → peering attachment, added statically).
- [ ] The shared GWLBE route table in each region
      (`module.security_vpc_*.gwlbe_route_table_id`) gets its three RFC-1918
      return routes (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) → that
      region's TGW.
- [ ] TGW IDs and attachment IDs are exposed for `vpc_spoke.tf` /
      `vpc_onprem.tf` to consume.

### vpc_spoke.tf — done when:

- [ ] Plan shows spoke-vpc-east (10.1.0.0/16, us-east-1) and spoke-vpc-west
      (10.2.0.0/16, us-west-2) with TGW attachments, driven from `locals.tf`.
      (Subnet layout inside the spokes is not yet specified in this document —
      decide and record it here before/while writing the file.)
- [ ] Spoke attachments are associated with `rt-tgw-spokes` (NOT
      `rt-tgw-security`) so all spoke traffic is forced through inspection.
- [ ] Spoke VPC route tables send non-local traffic to the TGW.
- [ ] Note: end-to-end pings will NOT work until firewall instances (or a
      stand-in) exist — with empty GWLB target groups, traffic blackholes at
      the GWLB. Plan-level correctness is the bar here.

### vpc_onprem.tf — done when:

- [ ] Plan shows both on-prem VPCs (on-prem-east 10.10.0.0/16, on-prem-west
      10.20.0.0/16), each with a t3.micro StrongSwan EC2 instance,
      an `aws_customer_gateway` pointing at the instance's public IP, a VPN
      attachment on the regional TGW, and static routes (no BGP).
- [ ] VPN attachments are associated with `rt-tgw-spokes` so VPN traffic is
      inspected like spoke traffic.
- [ ] Note: the IPsec tunnel only comes UP after StrongSwan is configured on
      the instance. That day-1 configuration (planned for Ansible) is not yet
      designed — tunnel-UP is out of scope for this file's definition of done.

### outputs.tf — done when:

- [ ] `tofu output` after apply shows: hub/security/spoke VPC IDs, subnet ID
      maps (keyed by AZ), GWLB ARNs and endpoint IDs, and TGW IDs, for both
      regions.
- [ ] No file in this directory (and no future consumer) needs a hardcoded
      AWS resource ID — everything is reachable via outputs or resource
      references. (The module already exposes the per-region pieces via
      `module.security_vpc_east/west.*` — this file surfaces them at root level.)

---

## Production Mapping Reference

The table below maps lab resource naming to equivalent production naming conventions:

| Lab Resource | Production Equivalent Pattern |
|---|---|
| security-vpc-\<region\> | security-vpc-\<region\> |
| sub-security-vpc-\<az\>-tgw | sub-security-vpc-\<az\>-tgw |
| sub-security-vpc-\<az\>-gwlbe | sub-security-vpc-\<az\>-gwlbe |
| sub-security-vpc-\<az\>-untrust | sub-security-vpc-\<az\>-palo-untrust |
| rt-\<az\>-security-vpc-tgw | rt-\<region\>-security-vpc-tgw-\<az\> |
| rt-\<region\>-security-vpc-gwlbe | rt-\<region\>-security-vpc-gwlbe |
| rt-\<region\>-security-vpc-untrust | rt-\<region\>-security-vpc-untrust |
| rt-\<region\>-security-vpc-main | rt-\<region\>-security-vpc-main |

The us-east-1c and us-west-2c AZs represent newly added AZs extending
an existing two-AZ inspection architecture to three AZs per region.
