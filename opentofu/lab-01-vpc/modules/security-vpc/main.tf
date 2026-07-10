# =============================================================================
# Security / Inspection VPC — single region
#
# One instance of this module is called per region from vpc_security.tf, each
# with a different `providers = { aws = ... }` binding. This is the standard
# Terraform/OpenTofu pattern for multi-region for_each: a provider can't vary
# per-key within a single for_each, so the region dimension is handled by
# calling this module once per region instead. Everything below this point
# (AZs, subnet tiers) still uses for_each per CLAUDE.md convention #1.
#
# Route table design:
#   - rt-tgw-<az>     : per-AZ, default route → GWLB endpoint (AZ-affinity)
#   - rt-gwlbe        : shared, RFC-1918 routes → TGW (return path)
#   - rt-untrust      : shared, default route → IGW (internet egress)
#   - rt-main         : shared, local only (trust/mgmt isolation)
# =============================================================================

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name   = "security-vpc-${var.region}"
    Region = var.region
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name   = "igw-${var.region}-security-vpc"
    Region = var.region
  })
}

# -----------------------------------------------------------------------------
# TGW Attachment Subnets — one per AZ (/28)
# -----------------------------------------------------------------------------
resource "aws_subnet" "tgw" {
  for_each = var.subnet_cidrs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.tgw
  availability_zone = each.key

  tags = merge(var.common_tags, {
    Name   = "sub-security-vpc-${each.key}-tgw"
    Region = var.region
    AZ     = each.key
    Tier   = "tgw"
  })
}

# -----------------------------------------------------------------------------
# GWLB Endpoint Subnets — one per AZ (/28)
# -----------------------------------------------------------------------------
resource "aws_subnet" "gwlbe" {
  for_each = var.subnet_cidrs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.gwlbe
  availability_zone = each.key

  tags = merge(var.common_tags, {
    Name   = "sub-security-vpc-${each.key}-gwlbe"
    Region = var.region
    AZ     = each.key
    Tier   = "gwlbe"
  })
}

# -----------------------------------------------------------------------------
# Firewall Untrust Subnets — one per AZ (/28)
# No firewall instances deployed in lab — subnets created for pattern fidelity
# -----------------------------------------------------------------------------
resource "aws_subnet" "untrust" {
  for_each = var.subnet_cidrs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.untrust
  availability_zone = each.key

  tags = merge(var.common_tags, {
    Name   = "sub-security-vpc-${each.key}-untrust"
    Region = var.region
    AZ     = each.key
    Tier   = "untrust"
  })
}

# -----------------------------------------------------------------------------
# Firewall Trust/Mgmt Subnets — one per AZ (/27)
# Local-only routing — no default route (intentional, trust/mgmt isolation)
# -----------------------------------------------------------------------------
resource "aws_subnet" "trust_mgmt" {
  for_each = var.subnet_cidrs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.trust_mgmt
  availability_zone = each.key

  tags = merge(var.common_tags, {
    Name   = "sub-security-vpc-${each.key}-trust-mgmt"
    Region = var.region
    AZ     = each.key
    Tier   = "trust-mgmt"
  })
}

# =============================================================================
# ROUTE TABLES
# =============================================================================

# Per-AZ TGW route tables — AZ-affinity, default route added later in gwlb.tf
# once the GWLB endpoint ID for that AZ is known.
resource "aws_route_table" "tgw" {
  for_each = toset(var.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name   = "rt-${each.key}-security-vpc-tgw"
    Region = var.region
    AZ     = each.key
    Tier   = "tgw"
  })
}

resource "aws_route_table_association" "tgw" {
  for_each = toset(var.azs)

  subnet_id      = aws_subnet.tgw[each.key].id
  route_table_id = aws_route_table.tgw[each.key].id
}

# Shared GWLBE route table — RFC-1918 return routes to TGW added later in
# tgw.tf once the TGW attachment ID is known.
resource "aws_route_table" "gwlbe" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name   = "rt-${var.region}-security-vpc-gwlbe"
    Region = var.region
    Tier   = "gwlbe"
  })
}

resource "aws_route_table_association" "gwlbe" {
  for_each = toset(var.azs)

  subnet_id      = aws_subnet.gwlbe[each.key].id
  route_table_id = aws_route_table.gwlbe.id
}

# Shared untrust route table — default route to IGW (internet egress)
resource "aws_route_table" "untrust" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.common_tags, {
    Name   = "rt-${var.region}-security-vpc-untrust"
    Region = var.region
    Tier   = "untrust"
  })
}

resource "aws_route_table_association" "untrust" {
  for_each = toset(var.azs)

  subnet_id      = aws_subnet.untrust[each.key].id
  route_table_id = aws_route_table.untrust.id
}

# Shared main route table — local only, trust/mgmt subnets are isolated
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name   = "rt-${var.region}-security-vpc-main"
    Region = var.region
    Tier   = "main"
  })
}

resource "aws_route_table_association" "trust_mgmt" {
  for_each = toset(var.azs)

  subnet_id      = aws_subnet.trust_mgmt[each.key].id
  route_table_id = aws_route_table.main.id
}
