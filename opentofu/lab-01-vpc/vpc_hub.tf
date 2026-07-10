# =============================================================================
# vpc_hub.tf
# Hub VPC — us-east-1 management plane
#
# Refactored from static per-AZ resource blocks (previously in main.tf, using
# a hardcoded 10.0.0.0/16) to for_each over local.hub_vpc, matching
# local.hub_vpc.cidr (10.0.0.0/20) so it no longer overlaps the security VPC
# ranges (10.0.16.0/22, 10.0.20.0/22) carved out of the same 10.0.0.0/8 space.
# =============================================================================

resource "aws_vpc" "hub" {
  cidr_block           = local.hub_vpc.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "hub-vpc"
  })
}

resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id

  tags = merge(local.common_tags, {
    Name = "hub-igw"
  })
}

resource "aws_subnet" "hub_public" {
  for_each = local.hub_vpc.subnet_cidrs

  vpc_id            = aws_vpc.hub.id
  cidr_block        = each.value.public
  availability_zone = each.key

  tags = merge(local.common_tags, {
    Name = "hub-public-subnet-${each.key}"
    AZ   = each.key
    Tier = "public"
  })
}

# Dedicated subnet for the Network Firewall endpoint
resource "aws_subnet" "hub_firewall" {
  for_each = local.hub_vpc.subnet_cidrs

  vpc_id            = aws_vpc.hub.id
  cidr_block        = each.value.firewall
  availability_zone = each.key

  tags = merge(local.common_tags, {
    Name = "hub-firewall-subnet-${each.key}"
    AZ   = each.key
    Tier = "firewall"
  })
}

resource "aws_route_table" "hub_public" {
  for_each = local.hub_vpc.subnet_cidrs

  vpc_id = aws_vpc.hub.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }

  tags = merge(local.common_tags, {
    Name = "hub-public-rt-${each.key}"
    AZ   = each.key
    Tier = "public"
  })
}

resource "aws_route_table_association" "hub_public" {
  for_each = local.hub_vpc.subnet_cidrs

  subnet_id      = aws_subnet.hub_public[each.key].id
  route_table_id = aws_route_table.hub_public[each.key].id
}

# Route table for the firewall subnet — firewall subnet only needs a path to
# the internet
resource "aws_route_table" "hub_firewall" {
  for_each = local.hub_vpc.subnet_cidrs

  vpc_id = aws_vpc.hub.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }

  tags = merge(local.common_tags, {
    Name = "hub-firewall-rt-${each.key}"
    AZ   = each.key
    Tier = "firewall"
  })
}

resource "aws_route_table_association" "hub_firewall" {
  for_each = local.hub_vpc.subnet_cidrs

  subnet_id      = aws_subnet.hub_firewall[each.key].id
  route_table_id = aws_route_table.hub_firewall[each.key].id
}
