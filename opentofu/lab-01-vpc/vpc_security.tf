# =============================================================================
# vpc_security.tf
# Security / Inspection VPCs — us-east-1 and us-west-2
#
# Architecture mirrors the SGWS connectivity account inspection VPC pattern:
#   - TGW attachment subnets per AZ (/28)
#   - GWLB endpoint subnets per AZ (/28)
#   - Firewall untrust subnets per AZ (/28)
#   - Firewall trust/mgmt subnets per AZ (/27)
#
# Route table design:
#   - rt-tgw-<az>     : per-AZ, default route → GWLB endpoint (AZ-affinity)
#   - rt-gwlbe        : shared, RFC-1918 routes → TGW (return path)
#   - rt-untrust      : shared, default route → IGW (internet egress)
#   - rt-main         : shared, local only (trust/mgmt isolation)
# =============================================================================

# -----------------------------------------------------------------------------
# Security VPCs — one per region
# -----------------------------------------------------------------------------
resource "aws_vpc" "security" {
  for_each = local.security_vpcs

  cidr_block           = each.value.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name   = "vpc10-${each.key}-security"
    Region = each.key
  })
}

# -----------------------------------------------------------------------------
# Internet Gateways — one per security VPC
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "security" {
  for_each = local.security_vpcs

  vpc_id = aws_vpc.security[each.key].id

  tags = merge(local.common_tags, {
    Name   = "igw-${each.key}-vpc10"
    Region = each.key
  })
}

# -----------------------------------------------------------------------------
# TGW Attachment Subnets — one per AZ per region (/28)
# These receive traffic from the TGW and route it to the GWLB endpoint
# -----------------------------------------------------------------------------
resource "aws_subnet" "security_tgw" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az, cidr in vpc.subnet_cidrs : {
          key    = "${region}-${az}-tgw"
          region = region
          az     = az
          cidr   = cidr.tgw
        }
      ]
    ]) : pair.key => pair
  }

  vpc_id            = aws_vpc.security[each.value.region].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name   = "sub-vpc10-${each.value.az}-tgw"
    Region = each.value.region
    AZ     = each.value.az
    Tier   = "tgw"
  })
}

# -----------------------------------------------------------------------------
# GWLB Endpoint Subnets — one per AZ per region (/28)
# GWLB endpoints live here; traffic arrives from TGW route and returns to TGW
# -----------------------------------------------------------------------------
resource "aws_subnet" "security_gwlbe" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az, cidr in vpc.subnet_cidrs : {
          key    = "${region}-${az}-gwlbe"
          region = region
          az     = az
          cidr   = cidr.gwlbe
        }
      ]
    ]) : pair.key => pair
  }

  vpc_id            = aws_vpc.security[each.value.region].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name   = "sub-vpc10-${each.value.az}-gwlbe"
    Region = each.value.region
    AZ     = each.value.az
    Tier   = "gwlbe"
  })
}

# -----------------------------------------------------------------------------
# Firewall Untrust Subnets — one per AZ per region (/28)
# Firewall data plane (untrust) interfaces sit here
# No firewall instances deployed in lab — subnets created for pattern fidelity
# -----------------------------------------------------------------------------
resource "aws_subnet" "security_untrust" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az, cidr in vpc.subnet_cidrs : {
          key    = "${region}-${az}-untrust"
          region = region
          az     = az
          cidr   = cidr.untrust
        }
      ]
    ]) : pair.key => pair
  }

  vpc_id            = aws_vpc.security[each.value.region].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name   = "sub-vpc10-${each.value.az}-palo-untrust"
    Region = each.value.region
    AZ     = each.value.az
    Tier   = "untrust"
  })
}

# -----------------------------------------------------------------------------
# Firewall Trust/Mgmt Subnets — one per AZ per region (/27)
# Firewall trust and management interfaces sit here
# Local-only routing — no default route (matches SGWS main RT pattern)
# -----------------------------------------------------------------------------
resource "aws_subnet" "security_trust_mgmt" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az, cidr in vpc.subnet_cidrs : {
          key    = "${region}-${az}-trust-mgmt"
          region = region
          az     = az
          cidr   = cidr.trust_mgmt
        }
      ]
    ]) : pair.key => pair
  }

  vpc_id            = aws_vpc.security[each.value.region].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name   = "sub-vpc10-${each.value.az}-trust-mgmt"
    Region = each.value.region
    AZ     = each.value.az
    Tier   = "trust-mgmt"
  })
}

# =============================================================================
# ROUTE TABLES
# =============================================================================

# -----------------------------------------------------------------------------
# TGW Route Tables — one per AZ per region (AZ-affinity design)
# Default route points to GWLB endpoint in the SAME AZ
# This prevents cross-AZ traffic through the inspection path
# -----------------------------------------------------------------------------
resource "aws_route_table" "security_tgw" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az in vpc.azs : {
          key    = "${region}-${az}-tgw"
          region = region
          az     = az
        }
      ]
    ]) : pair.key => pair
  }

  vpc_id = aws_vpc.security[each.value.region].id

  tags = merge(local.common_tags, {
    Name   = "rt-${each.value.az}-vpc10-security-tgw"
    Region = each.value.region
    AZ     = each.value.az
    Tier   = "tgw"
  })
}

# Associate TGW subnets to their per-AZ route tables
resource "aws_route_table_association" "security_tgw" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az in vpc.azs : {
          key    = "${region}-${az}-tgw"
          region = region
          az     = az
        }
      ]
    ]) : pair.key => pair
  }

  subnet_id      = aws_subnet.security_tgw["${each.value.region}-${each.value.az}-tgw"].id
  route_table_id = aws_route_table.security_tgw[each.key].id
}

# -----------------------------------------------------------------------------
# GWLBE Route Tables — one shared per region
# RFC-1918 summary routes back to TGW (return path after inspection)
# Routes added in tgw.tf once TGW resource IDs are known
# -----------------------------------------------------------------------------
resource "aws_route_table" "security_gwlbe" {
  for_each = local.security_vpcs

  vpc_id = aws_vpc.security[each.key].id

  tags = merge(local.common_tags, {
    Name   = "rt-${each.key}-vpc10-security-gwlbe"
    Region = each.key
    Tier   = "gwlbe"
  })
}

# Associate GWLBE subnets to the shared GWLBE route table
resource "aws_route_table_association" "security_gwlbe" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az in vpc.azs : {
          key    = "${region}-${az}-gwlbe"
          region = region
          az     = az
        }
      ]
    ]) : pair.key => pair
  }

  subnet_id      = aws_subnet.security_gwlbe["${each.value.region}-${each.value.az}-gwlbe"].id
  route_table_id = aws_route_table.security_gwlbe[each.value.region].id
}

# -----------------------------------------------------------------------------
# Untrust Route Tables — one shared per region
# Default route → IGW (internet egress for firewall untrust interfaces)
# -----------------------------------------------------------------------------
resource "aws_route_table" "security_untrust" {
  for_each = local.security_vpcs

  vpc_id = aws_vpc.security[each.key].id

  # Default route to IGW — untrust interfaces need internet access
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.security[each.key].id
  }

  tags = merge(local.common_tags, {
    Name   = "rt-${each.key}-vpc10-security-untrust"
    Region = each.key
    Tier   = "untrust"
  })
}

# Associate untrust subnets to the shared untrust route table
resource "aws_route_table_association" "security_untrust" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az in vpc.azs : {
          key    = "${region}-${az}-untrust"
          region = region
          az     = az
        }
      ]
    ]) : pair.key => pair
  }

  subnet_id      = aws_subnet.security_untrust["${each.value.region}-${each.value.az}-untrust"].id
  route_table_id = aws_route_table.security_untrust[each.value.region].id
}

# -----------------------------------------------------------------------------
# Main Route Tables — one shared per region (local only)
# Trust/mgmt subnets are isolated — no default route, no TGW route
# Matches SGWS pattern where trust/mgmt interfaces have no direct routing
# -----------------------------------------------------------------------------
resource "aws_route_table" "security_main" {
  for_each = local.security_vpcs

  vpc_id = aws_vpc.security[each.key].id

  # Local route only — intentionally no default route
  # Trust/mgmt subnet traffic stays within the VPC

  tags = merge(local.common_tags, {
    Name   = "rt-${each.key}-vpc10-security-main"
    Region = each.key
    Tier   = "main"
  })
}

# Associate trust/mgmt subnets to the main route table
resource "aws_route_table_association" "security_trust_mgmt" {
  for_each = {
    for pair in flatten([
      for region, vpc in local.security_vpcs : [
        for az in vpc.azs : {
          key    = "${region}-${az}-trust-mgmt"
          region = region
          az     = az
        }
      ]
    ]) : pair.key => pair
  }

  subnet_id      = aws_subnet.security_trust_mgmt["${each.value.region}-${each.value.az}-trust-mgmt"].id
  route_table_id = aws_route_table.security_main[each.value.region].id
}
