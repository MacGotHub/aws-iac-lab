# CLAUDE.md — aws-iac-lab Project Context

This file provides Claude Code with persistent context about this project,
its owner, goals, and conventions. Read this before making any changes.

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
├── opentofu/
│   └── lab-01-vpc/         # Active — Security VPC inspection architecture
│       ├── main.tf          # Provider config, TGW
│       ├── locals.tf        # AZ lists, CIDR maps, subnet definitions (THE BRAIN)
│       ├── variables.tf     # Environment, region, owner inputs
│       ├── vpc_hub.tf       # Hub VPC (refactor in progress)
│       ├── vpc_security.tf  # Security/inspection VPCs both regions ✓
│       ├── gwlb.tf          # GWLB, target groups, endpoints (TODO)
│       ├── tgw.tf           # TGW attachments and route tables (TODO)
│       └── outputs.tf       # Useful outputs (TODO)
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
- `vpc_security.tf` — security VPCs, subnets, route tables, associations

### In Progress / TODO
- `gwlb.tf` — GWLB per region, target groups, GWLB endpoints per AZ
- `tgw.tf` — TGW, VPC attachments, TGW route tables, RFC-1918 return routes
- `vpc_hub.tf` — refactor existing hub VPC to match for_each pattern
- `outputs.tf` — VPC IDs, subnet IDs, GWLB ARNs, TGW ID

### Known Dependencies
- GWLBE route table RFC-1918 routes need TGW ID from `tgw.tf`
- TGW route table default routes need GWLB endpoint IDs from `gwlb.tf`
- Build order: `vpc_security.tf` → `gwlb.tf` → `tgw.tf`

---

## Production Reference Notes

Key routing patterns this lab is built to replicate:

- Separate per-AZ TGW route tables for AZ-affinity
- GWLBE route table uses three RFC-1918 summary routes back to TGW:
  10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
- Untrust route table has single default route to IGW (shared across AZs)
- Main route table has local route only — trust/mgmt subnets are isolated
- New AZs being added: us-east-1c and us-west-2c
