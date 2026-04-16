# AWS IAC Lab Architecture

## Overview

This lab builds a hub and spoke network architecture on AWS using OpenTofu.
All infrastructure is defined as code and state is stored remotely in S3.

```
[east-vpc 10.1.0.0/16] ──TGW attachment──┐
                                           ├── [Transit Gateway] ── [hub-vpc 10.0.0.0/16 + Firewall]
[west-vpc 10.2.0.0/16] ──TGW attachment──┘
```

Traffic between spokes flows through the hub VPC where it is inspected
by AWS Network Firewall before being allowed to continue.

---

## State Backend (bootstrapped manually via AWS CLI)

Before any OpenTofu code runs, two resources must exist to store and lock state:

| Resource | Name | Purpose |
|---|---|---|
| S3 Bucket | `351668480009-opentofu-state` | Stores all `.tfstate` files, one per lab |
| DynamoDB Table | `opentofu-state-lock` | Prevents concurrent `tofu apply` runs |

Each lab stores its state at a unique key inside the bucket:

| Lab | State Key |
|---|---|
| lab-01-vpc | `hub-vpc/terraform.tfstate` |
| lab-02-vpn | `east-vpc/terraform.tfstate` |
| lab-03-vpc | `west-vpc/terraform.tfstate` |
| lab-04-firewall | `firewall/terraform.tfstate` |
| lab-05-tgw | `tgw/terraform.tfstate` |

---

## lab-01-vpc — Hub VPC

**Location:** `opentofu/lab-01-vpc/`

**Purpose:** The central hub VPC in the hub and spoke architecture. All spoke
traffic is routed through this VPC for firewall inspection. Also serves as the
security-focused VPC.

**CIDR:** `10.0.0.0/16`

### Resources

| Resource | Name Tag | File | Purpose |
|---|---|---|---|
| `aws_vpc` | `hub-vpc` | `main.tf:1` | The VPC itself |
| `aws_subnet` | `hub-public-subnet` | `main.tf:9` | Public subnet for general hub resources |
| `aws_subnet` | `hub-firewall-subnet` | `main.tf:19` | Dedicated subnet for the Network Firewall endpoint |
| `aws_internet_gateway` | `hub-igw` | `main.tf:30` | Connects the hub VPC to the internet |
| `aws_route_table` | `hub-public-rt` | `main.tf:38` | Routes public subnet traffic to the IGW |
| `aws_route_table` | `hub-firewall-rt` | `main.tf:55` | Routes firewall subnet traffic to the IGW |
| `aws_route_table_association` | — | `main.tf:50` | Associates hub-public-rt with hub-public-subnet |
| `aws_route_table_association` | — | `main.tf:65` | Associates hub-firewall-rt with hub-firewall-subnet |

### Referenced by
- `lab-04-firewall/main.tf` — looks up `hub-vpc` and `hub-firewall-subnet` via data sources to deploy the firewall
- `lab-05-tgw/main.tf` — looks up `hub-vpc`, `hub-public-subnet`, and `hub-public-rt` via data sources to attach to Transit Gateway

---

## lab-02-vpn — East Spoke VPC

**Location:** `opentofu/lab-02-vpn/`

**Purpose:** The east spoke VPC. Connects to the hub via Transit Gateway.
Represents an application or workload VPC that relies on the hub for
centralized security inspection.

**CIDR:** `10.1.0.0/16`

### Resources

| Resource | Name Tag | File | Purpose |
|---|---|---|---|
| `aws_vpc` | `east-vpc` | `main.tf:1` | The VPC itself |
| `aws_subnet` | `east-public-subnet` | `main.tf:9` | Public subnet for east workloads |
| `aws_internet_gateway` | `east-igw` | `main.tf:19` | Connects east VPC to the internet |
| `aws_route_table` | `east-public-rt` | `main.tf:27` | Routes public subnet traffic |
| `aws_route_table_association` | — | `main.tf:40` | Associates east-public-rt with east-public-subnet |

### Referenced by
- `lab-05-tgw/main.tf` — looks up `east-vpc`, `east-public-subnet`, and `east-public-rt` via data sources to attach to Transit Gateway and add cross-VPC routes

---

## lab-03-vpc — West Spoke VPC

**Location:** `opentofu/lab-03-vpc/`

**Purpose:** The west spoke VPC. Mirrors the east VPC in structure. Connects
to the hub via Transit Gateway.

**CIDR:** `10.2.0.0/16`

### Resources

| Resource | Name Tag | File | Purpose |
|---|---|---|---|
| `aws_vpc` | `west-vpc` | `main.tf:1` | The VPC itself |
| `aws_subnet` | `west-public-subnet` | `main.tf:9` | Public subnet for west workloads |
| `aws_internet_gateway` | `west-igw` | `main.tf:19` | Connects west VPC to the internet |
| `aws_route_table` | `west-public-rt` | `main.tf:27` | Routes public subnet traffic |
| `aws_route_table_association` | — | `main.tf:40` | Associates west-public-rt with west-public-subnet |

### Referenced by
- `lab-05-tgw/main.tf` — looks up `west-vpc`, `west-public-subnet`, and `west-public-rt` via data sources to attach to Transit Gateway and add cross-VPC routes

---

## lab-04-firewall — AWS Network Firewall

**Location:** `opentofu/lab-04-firewall/`

**Purpose:** Deploys AWS Network Firewall into the hub VPC's firewall subnet.
Inspects all traffic flowing through the hub. Uses both stateless rules (fast
path) and stateful rules (deep packet inspection via Suricata rule syntax).

### Resources

| Resource | Name Tag | File | Purpose |
|---|---|---|---|
| `aws_networkfirewall_rule_group` | `lab-stateless-rules` | `main.tf:23` | Stateless rules — forwards all TCP to stateful engine |
| `aws_networkfirewall_rule_group` | `lab-stateful-rules` | `main.tf:61` | Stateful rules — blocks traffic to known bad domains |
| `aws_networkfirewall_firewall_policy` | `lab-firewall-policy` | `main.tf:96` | Combines rule groups, sets default actions |
| `aws_networkfirewall_firewall` | `lab-firewall` | `main.tf:124` | The firewall deployed in hub-firewall-subnet |

### Data Sources

| Data Source | Looks Up | Used For |
|---|---|---|
| `data.aws_vpc.hub` | VPC named `hub-vpc` | Scopes firewall to hub VPC |
| `data.aws_subnet.firewall` | Subnet named `hub-firewall-subnet` | Deploys firewall endpoint into correct subnet |

### Rule Logic
- **Stateless:** All TCP traffic is forwarded to the stateful engine (`aws:forward_to_sfe`)
- **Stateful:** Suricata rules drop TLS (port 443) and HTTP (port 80) traffic to `malware.example.com`
- Rule order is `STRICT_ORDER` — rules are evaluated top to bottom, first match wins

---

## lab-05-tgw — Transit Gateway

**Location:** `opentofu/lab-05-tgw/`

**Purpose:** Creates an AWS Transit Gateway and connects all three VPCs to it.
Updates route tables in each VPC so cross-VPC traffic is routed through the
TGW. This is the backbone of the hub and spoke architecture.

### Resources

| Resource | Name Tag | File | Purpose |
|---|---|---|---|
| `aws_ec2_transit_gateway` | `lab-tgw` | `main.tf:48` | The Transit Gateway itself |
| `aws_ec2_transit_gateway_vpc_attachment` | `tgw-attach-hub` | `main.tf:62` | Attaches hub VPC to TGW |
| `aws_ec2_transit_gateway_vpc_attachment` | `tgw-attach-east` | `main.tf:73` | Attaches east VPC to TGW |
| `aws_ec2_transit_gateway_vpc_attachment` | `tgw-attach-west` | `main.tf:84` | Attaches west VPC to TGW |
| `aws_route` | — | `main.tf:106` | Hub route to east (`10.1.0.0/16` via TGW) |
| `aws_route` | — | `main.tf:114` | Hub route to west (`10.2.0.0/16` via TGW) |
| `aws_route` | — | `main.tf:122` | East route to hub (`10.0.0.0/16` via TGW) |
| `aws_route` | — | `main.tf:130` | East route to west (`10.2.0.0/16` via TGW) |
| `aws_route` | — | `main.tf:138` | West route to hub (`10.0.0.0/16` via TGW) |
| `aws_route` | — | `main.tf:146` | West route to east (`10.1.0.0/16` via TGW) |

### Data Sources

| Data Source | Looks Up | Used For |
|---|---|---|
| `data.aws_vpc.hub` | VPC named `hub-vpc` | TGW attachment |
| `data.aws_vpc.east` | VPC named `east-vpc` | TGW attachment |
| `data.aws_vpc.west` | VPC named `west-vpc` | TGW attachment |
| `data.aws_subnet.hub` | Subnet named `hub-public-subnet` | TGW attachment subnet |
| `data.aws_subnet.east` | Subnet named `east-public-subnet` | TGW attachment subnet |
| `data.aws_subnet.west` | Subnet named `west-public-subnet` | TGW attachment subnet |
| `data.aws_route_table.hub` | Route table named `hub-public-rt` | Adds cross-VPC routes |
| `data.aws_route_table.east` | Route table named `east-public-rt` | Adds cross-VPC routes |
| `data.aws_route_table.west` | Route table named `west-public-rt` | Adds cross-VPC routes |

### Dependency Notes
All `aws_route` resources declare `depends_on` pointing to their respective
TGW attachment. This is required because the route references the TGW as a
gateway, but the TGW cannot accept routes until the attachment is active.
OpenTofu cannot infer this dependency automatically from the resource
references alone.

---

## Deployment Order

Labs must be deployed in this order due to dependencies:

```
1. lab-01-vpc    (no dependencies)
2. lab-02-vpn    (no dependencies)
3. lab-03-vpc    (no dependencies)
4. lab-04-firewall  (depends on lab-01-vpc)
5. lab-05-tgw    (depends on lab-01-vpc, lab-02-vpn, lab-03-vpc)
```

## Teardown Order

Destroy in reverse order to avoid dependency errors:

```
1. lab-05-tgw
2. lab-04-firewall
3. lab-03-vpc
4. lab-02-vpn
5. lab-01-vpc
```

Run `tofu destroy` from each lab directory.
