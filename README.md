# aws-iac-lab

Personal AWS infrastructure-as-code lab (owner: Derek McWilliams). OpenTofu for
provisioning, Ansible for future day-1 config. The lab replicates enterprise
hub-and-spoke network security patterns across us-east-1 and us-west-2 in AWS
account `351668480009`.

## Read this first: two architectures live in this repo

This repo is mid-transition between two different designs. Do not assume any
single document describes the whole repo.

- **v1 — AWS Network Firewall in the hub VPC.** The original design. Labs
  `lab-02-vpn` through `lab-10-ec2-w2` under `opentofu/` follow it. Fully
  documented in [`docs/architecture.md`](docs/architecture.md), including
  deployment/teardown order and hourly cost.
- **v2 — GWLB-based centralized inspection (in progress).** A rebuild happening
  **in place** inside `opentofu/lab-01-vpc/`. It replaces the old v1 hub VPC
  with a corrected hub VPC (`10.0.0.0/20`, was `10.0.0.0/16`) plus dedicated
  security (inspection) VPCs in both regions, fronted by Gateway Load
  Balancers. Documented in
  [`opentofu/lab-01-vpc/DESIGN.md`](opentofu/lab-01-vpc/DESIGN.md) (the design)
  and [`opentofu/lab-01-vpc/CLAUDE.md`](opentofu/lab-01-vpc/CLAUDE.md)
  (conventions + current build status).

**Important:** the `lab-01-vpc` section of `docs/architecture.md` describes the
OLD v1 code that used to live in that directory. It no longer matches the
directory contents. For anything about `lab-01-vpc` as it exists today, trust
`opentofu/lab-01-vpc/DESIGN.md` and `CLAUDE.md`, not `docs/architecture.md`.
Both versions of lab-01 share the same remote state key
(`hub-vpc/terraform.tfstate`), so applying the rebuilt lab-01 will modify or
replace whatever the old lab-01 deployed — see the runbook before applying.

## Which document answers which question

| Question | Read |
|---|---|
| What is deployed / deployable in labs 02-10 (v1)? | [`docs/architecture.md`](docs/architecture.md) |
| What is the in-progress v2 hub/inspection rebuild? | [`opentofu/lab-01-vpc/DESIGN.md`](opentofu/lab-01-vpc/DESIGN.md) |
| What is done vs TODO in the v2 rebuild, and coding conventions? | [`opentofu/lab-01-vpc/CLAUDE.md`](opentofu/lab-01-vpc/CLAUDE.md) |
| Exact commands to init/plan/apply anything (credentials, backend, order) | [`docs/runbook.md`](docs/runbook.md) |

## Repo layout

```
aws-iac-lab/
├── README.md            # You are here — the entry point
├── docs/
│   ├── architecture.md  # v1 architecture reference (labs 02-10; lab-01 section is stale)
│   └── runbook.md       # Literal command sequences: credentials, backend, per-lab apply
├── apply-all.sh         # Applies all 10 labs in v1 dependency order (assumes tofu init done)
├── destroy-all.sh       # Destroys all 10 labs in reverse order
├── opentofu/
│   ├── lab-01-vpc/      # v2 REBUILD IN PROGRESS — hub VPC + security VPCs + GWLB (see its DESIGN.md)
│   ├── lab-02-vpn/      # v1 — east spoke VPC (10.1.0.0/16)
│   ├── lab-03-vpc/      # v1 — west spoke VPC (10.2.0.0/16)
│   ├── lab-04-firewall/ # v1 — AWS Network Firewall, us-east-1
│   ├── lab-05-tgw/      # v1 — Transit Gateway, us-east-1
│   ├── lab-06-ec2/      # v1 — test instances, us-east-1
│   ├── lab-07-vpc-w2/   # v1 — hub + spoke VPCs, us-west-2
│   ├── lab-08-firewall-w2/ # v1 — AWS Network Firewall, us-west-2
│   ├── lab-09-tgw-w2/   # v1 — TGW + cross-region peering
│   └── lab-10-ec2-w2/   # v1 — test instances, us-west-2
└── ansible/             # Day-1 configuration (future — empty for now)
```

## Current deployment status

These docs do not track what is live in AWS at any given moment (labs are
applied and destroyed to control cost — the full v1 stack runs ~$2/hr). Before
assuming anything is deployed, check: run `tofu state list` inside a lab
directory, or look in the AWS console. The resource IDs hardcoded in
`docs/architecture.md` (vpce-*, tgw-*) are snapshots from a past deployment and
change on every destroy/apply cycle.
