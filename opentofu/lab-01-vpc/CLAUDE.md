# CLAUDE.md — aws-iac-lab Project Context

This file provides Claude Code with persistent context about this project,
its owner, goals, and conventions. Read this before making any changes.

**Companion documents — read in this order when picking up work:**
1. Repo root `README.md` — explains the v1 (labs 02-10) vs v2 (this
   directory) architecture split.
2. `DESIGN.md` (this directory) — the v2 architecture, build order, and a
   "Definition of Done" checklist for every remaining file.
3. `docs/runbook.md` (repo root) — literal `tofu` command sequences, AWS
   credential and state-backend prerequisites, and a warning about this
   directory's shared v1 state key.
4. `docs/architecture.md` (repo root) — the OLD v1 architecture. Its lab-01
   section is stale; do not use it to reason about this directory.

---

## Owner

- **Name:** Derek McWilliams
- **Role:** Network Security Engineer
- **GitHub:** MacGotHub

---

## Project Purpose

This is Derek's personal AWS IaC lab, used for:
1. Hands-on skill building with OpenTofu and Ansible
2. Replicating and understanding enterprise AWS architecture patterns
3. Building a sandbox reference that mirrors real-world production designs

Code written here should be enterprise-quality.

---

## Tooling

| Tool | Purpose |
|---|---|
| OpenTofu | Infrastructure provisioning (Day 0) |
| Ansible | Configuration management (Day 1) |
| AWS CLI | Ad-hoc verification and troubleshooting |
| Git / GitHub | Version control (repo: MacGotHub/aws-iac-lab) |

**OpenTofu version:** Use whatever is current stable.
**AWS Regions:** us-east-1 (primary), us-west-2 (secondary)
**AWS Account ID:** 351668480009

---

## Repo Structure

```
aws-iac-lab/
├── docs/
│   ├── architecture.md      # v1 architecture (labs 02-10) — lab-01 section stale
│   └── runbook.md           # Literal command sequences + prerequisites
├── opentofu/
│   ├── lab-01-vpc/          # Active — v2 Security VPC inspection architecture (this dir)
│   │   ├── backend.tf       # S3 remote state (351668480009-opentofu-state, key hub-vpc/terraform.tfstate)
│   │   ├── providers.tf     # Provider config — default (us-east-1) + aws.west alias
│   │   ├── locals.tf        # AZ lists, CIDR maps, subnet definitions (THE BRAIN)
│   │   ├── variables.tf     # Environment, region, owner inputs
│   │   ├── vpc_hub.tf       # Hub VPC, for_each over local.hub_vpc ✓
│   │   ├── vpc_security.tf  # Calls modules/security-vpc once per region ✓
│   │   ├── modules/
│   │   │   └── security-vpc/  # Single-region security VPC (VPC, subnets, route tables)
│   │   ├── gwlb.tf          # GWLB, target groups, endpoints (TODO — file doesn't exist yet)
│   │   ├── tgw.tf           # TGW attachments and route tables (TODO — file doesn't exist yet)
│   │   ├── vpc_spoke.tf     # Spoke VPCs east/west (TODO — file doesn't exist yet)
│   │   ├── vpc_onprem.tf    # On-prem sim VPCs + StrongSwan VPN (TODO — file doesn't exist yet)
│   │   └── outputs.tf       # Useful outputs (TODO — file doesn't exist yet)
│   └── lab-02-vpn/ ... lab-10-ec2-w2/   # v1 labs — see docs/architecture.md, do NOT apply v2 conventions retroactively
└── ansible/                 # Day 1 config (future)
```

---

## Architecture Overview

This lab replicates an enterprise connectivity account inspection VPC pattern using
AWS Gateway Load Balancer (GWLB) for centralized firewall inspection.

### Traffic Flow
```
Spoke VPC
    ↓
TGW
    ↓ (default route 0.0.0.0/0 → GWLB endpoint)
TGW Attachment Subnet (/28) — per AZ
    ↓
GWLB Endpoint Subnet (/28) — per AZ
    ↓ (GWLB sends to firewall target group)
Firewall Untrust Subnet (/28) — per AZ  [no instance in lab]
    ↓ (inspected traffic returned to GWLB)
GWLB Endpoint Subnet
    ↓ (RFC-1918 routes → TGW)
TGW → destination spoke
```

### VPC Layout

| VPC | Region | CIDR |
|---|---|---|
| hub-vpc | us-east-1 | 10.0.0.0/20 |
| security-vpc-us-east-1 | us-east-1 | 10.0.16.0/22 |
| security-vpc-us-west-2 | us-west-2 | 10.0.20.0/22 |

### Security VPC Subnet Types (per AZ)

| Tier | Size | Route Table | Purpose |
|---|---|---|---|
| tgw | /28 | rt-tgw-\<az\> (per-AZ) | TGW attachment |
| gwlbe | /28 | rt-gwlbe (shared) | GWLB endpoint |
| untrust | /28 | rt-untrust (shared) | Firewall data plane |
| trust-mgmt | /27 | rt-main (shared, local only) | Firewall trust/mgmt |

### Active AZs

| Region | AZs |
|---|---|
| us-east-1 | us-east-1b, us-east-1c, us-east-1d |
| us-west-2 | us-west-2b, us-west-2c, us-west-2d |

---

## Coding Conventions

### Always follow these patterns:

1. **`for_each` over repeated resource blocks** — never write the same resource
   block multiple times for different AZs or regions. Use `for_each` driven
   by `locals`.
   **Known exception:** a provider cannot vary per-key within a single
   `for_each`/module block, so multi-region resources that need distinct
   provider configs (e.g. `modules/security-vpc`, called once per region with
   a different `providers = { aws = ... }` binding) are the one case where two
   near-identical blocks are correct instead of a single `for_each`. Everything
   *within* each region (AZs, subnet tiers) still uses `for_each`.

2. **`locals.tf` is the single source of truth** — all AZ lists, CIDRs, and
   structural data live in `locals.tf`. Other files reference locals, they
   don't define their own data.

3. **Explicit CIDRs over `cidrsubnet()`** — use explicit CIDR strings in
   locals for readability and console cross-referencing.

4. **Common tags on every resource** — always merge `local.common_tags` with
   resource-specific tags using `merge()`.

5. **Naming convention follows enterprise production patterns:**
   - VPCs: `security-vpc-<region>`
   - Subnets: `sub-security-vpc-<az>-<tier>`
   - Route tables: `rt-<region>-security-vpc-<tier>`
   - IGWs: `igw-<region>-security-vpc`

6. **Comments explaining the why** — not just what the code does, but why
   design decisions were made (e.g. AZ-affinity routing rationale).

7. **No firewall instances in lab** — subnets are created for pattern fidelity
   but no VM-Series or placeholder EC2 instances are deployed to keep costs low.

---

## What NOT to Do

- Do not use `count` for multi-AZ or multi-region resources — use `for_each`
- Do not hardcode resource IDs — reference them via resource attributes
- Do not create resources outside `locals.tf` data structures — extend locals first
- Do not collapse per-AZ route tables into a single shared table for TGW subnets —
  AZ-affinity routing is intentional and important
- Do not add NAT Gateways unless explicitly requested — cost concern in personal lab

---

## Current Status

### Completed
- `locals.tf` — full AZ/CIDR/subnet structure for both regions
- `variables.tf` — environment, owner, region inputs
- `vpc_security.tf` + `modules/security-vpc/` — security VPCs, subnets, route
  tables, associations, called once per region with the correct provider
  (fixes a bug where the us-west-2 VPC/subnets would have been created in
  us-east-1 under the single default provider)
- `vpc_hub.tf` — hub VPC refactored to for_each over `local.hub_vpc`, CIDR
  corrected to `10.0.0.0/20` (was hardcoded to `10.0.0.0/16`, which
  overlapped the security VPC ranges carved from the same `10.0.0.0/8` space)
- `providers.tf` — added `aws.west` alias for the us-west-2 module call

### In Progress / TODO

Full per-file verification checklists live in `DESIGN.md` under
"Definition of Done — per remaining file" — use those, not intuition, to
decide when a file is finished. Short form:

- `gwlb.tf` — GWLB per region, target groups, GWLB endpoints per AZ.
  *Done when:* plan shows per region 1 GWLB + 1 target group + 1 listener +
  1 endpoint service + 3 GWLB endpoints (one per AZ in `locals.tf`), each
  per-AZ TGW route table gets a same-AZ `0.0.0.0/0` → GWLBe route, and
  endpoint IDs are exposed keyed by AZ for `tgw.tf`. Empty/unhealthy target
  groups are expected (no firewall instances — open decision in DESIGN.md).
- `tgw.tf` — TGW, VPC attachments, TGW route tables, RFC-1918 return routes.
  *Done when:* 2 TGWs + peering, security VPC attachments with
  `appliance_mode_support = "enable"`, `rt-tgw-spokes`/`rt-tgw-security`
  split per TGW, and the shared GWLBE route tables get their three RFC-1918
  routes → TGW.
- `vpc_spoke.tf` — spoke VPCs east (10.1.0.0/16) and west (10.2.0.0/16) with
  TGW attachments. *Done when:* attachments are associated with
  `rt-tgw-spokes` and spoke route tables default to the TGW. (Planned in
  DESIGN.md; end-to-end pings won't work until firewall targets exist.)
- `vpc_onprem.tf` — on-prem sim VPCs (10.10.0.0/16 / 10.20.0.0/16),
  StrongSwan t3.micro, customer gateway, TGW VPN attachment, static routes.
  *Done when:* plan-level resources exist and VPN attachments use
  `rt-tgw-spokes`; tunnel-UP requires future Ansible config, out of scope.
- `outputs.tf` — VPC IDs, subnet IDs, GWLB ARNs, TGW ID (module already
  exposes what's needed: `module.security_vpc_east/west.*`).
  *Done when:* `tofu output` shows the IDs for both regions and nothing
  anywhere needs a hardcoded AWS ID.

### Known Dependencies
- GWLBE route table RFC-1918 routes need TGW ID from `tgw.tf`
- TGW route table default routes need GWLB endpoint IDs from `gwlb.tf`
- Build order: `vpc_security.tf` → `gwlb.tf` → `tgw.tf` → `vpc_spoke.tf` →
  `vpc_onprem.tf` → `outputs.tf` (full chain in DESIGN.md; literal commands
  in `docs/runbook.md` — note OpenTofu applies the whole directory each time,
  not single files)

---

## Production Reference Notes

Key routing patterns this lab is built to replicate:

- Separate per-AZ TGW route tables for AZ-affinity
- GWLBE route table uses three RFC-1918 summary routes back to TGW:
  10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
- Untrust route table has single default route to IGW (shared across AZs)
- Main route table has local route only — trust/mgmt subnets are isolated
- New AZs being added: us-east-1c and us-west-2c
