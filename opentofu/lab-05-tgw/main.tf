# -----------------------------------------------
# Data sources — look up existing VPCs by name
# -----------------------------------------------

data "aws_vpc" "hub" {
  filter {
    name   = "tag:Name"
    values = ["hub-vpc"]
  }
}

data "aws_vpc" "east" {
  filter {
    name   = "tag:Name"
    values = ["east-vpc"]
  }
}

data "aws_vpc" "west" {
  filter {
    name   = "tag:Name"
    values = ["west-vpc"]
  }
}

# ---- AZ-a subnets ----

data "aws_subnet" "hub" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-subnet"]
  }
}

data "aws_subnet" "east" {
  filter {
    name   = "tag:Name"
    values = ["east-public-subnet"]
  }
}

data "aws_subnet" "west" {
  filter {
    name   = "tag:Name"
    values = ["west-public-subnet"]
  }
}

# ---- AZ-b subnets ----

data "aws_subnet" "hub_b" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-subnet-b"]
  }
}

data "aws_subnet" "east_b" {
  filter {
    name   = "tag:Name"
    values = ["east-public-subnet-b"]
  }
}

data "aws_subnet" "west_b" {
  filter {
    name   = "tag:Name"
    values = ["west-public-subnet-b"]
  }
}

# -----------------------------------------------
# Transit Gateway
# -----------------------------------------------

resource "aws_ec2_transit_gateway" "main" {
  description                     = "Hub and spoke transit gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name = "lab-tgw"
  }
}

# -----------------------------------------------
# TGW Attachments — connect each VPC to the TGW
# Both AZs included per attachment for redundancy
# -----------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.hub.id
  subnet_ids         = [data.aws_subnet.hub.id, data.aws_subnet.hub_b.id]

  tags = {
    Name = "tgw-attach-hub"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "east" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.east.id
  subnet_ids         = [data.aws_subnet.east.id, data.aws_subnet.east_b.id]

  tags = {
    Name = "tgw-attach-east"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "west" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.west.id
  subnet_ids         = [data.aws_subnet.west.id, data.aws_subnet.west_b.id]

  tags = {
    Name = "tgw-attach-west"
  }
}

# -----------------------------------------------
# Firewall endpoints — one per AZ
# -----------------------------------------------

# Firewall endpoint IDs — sourced from lab-04-firewall outputs
# These are stable per deployment; update if firewall is redeployed
locals {
  firewall_endpoint_az_a = "vpce-0087ab32e47f384ed"
  firewall_endpoint_az_b = "vpce-0efcb6b55446d8966"
}

# -----------------------------------------------
# VPC Route Table Updates
# -----------------------------------------------

data "aws_route_table" "hub" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-rt"]
  }
}

data "aws_route_table" "hub_b" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-rt-b"]
  }
}

data "aws_route_table" "east" {
  filter {
    name   = "tag:Name"
    values = ["east-public-rt"]
  }
}

data "aws_route_table" "east_b" {
  filter {
    name   = "tag:Name"
    values = ["east-public-rt-b"]
  }
}

data "aws_route_table" "west" {
  filter {
    name   = "tag:Name"
    values = ["west-public-rt"]
  }
}

data "aws_route_table" "west_b" {
  filter {
    name   = "tag:Name"
    values = ["west-public-rt-b"]
  }
}

data "aws_route_table" "hub_firewall" {
  filter {
    name   = "tag:Name"
    values = ["hub-firewall-rt"]
  }
}

data "aws_route_table" "hub_firewall_b" {
  filter {
    name   = "tag:Name"
    values = ["hub-firewall-rt-b"]
  }
}

# ---- Hub AZ-a routes ----

resource "aws_route" "hub_to_east" {
  route_table_id         = data.aws_route_table.hub.id
  destination_cidr_block = "10.1.0.0/16"
  vpc_endpoint_id        = local.firewall_endpoint_az_a
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "hub_to_west" {
  route_table_id         = data.aws_route_table.hub.id
  destination_cidr_block = "10.2.0.0/16"
  vpc_endpoint_id        = local.firewall_endpoint_az_a
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ---- Hub AZ-b routes ----

resource "aws_route" "hub_b_to_east" {
  route_table_id         = data.aws_route_table.hub_b.id
  destination_cidr_block = "10.1.0.0/16"
  vpc_endpoint_id        = local.firewall_endpoint_az_b
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "hub_b_to_west" {
  route_table_id         = data.aws_route_table.hub_b.id
  destination_cidr_block = "10.2.0.0/16"
  vpc_endpoint_id        = local.firewall_endpoint_az_b
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ---- Firewall AZ-a routes (post-inspection back to TGW) ----

resource "aws_route" "firewall_to_east" {
  route_table_id         = data.aws_route_table.hub_firewall.id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "firewall_to_west" {
  route_table_id         = data.aws_route_table.hub_firewall.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ---- Firewall AZ-b routes (post-inspection back to TGW) ----

resource "aws_route" "firewall_b_to_east" {
  route_table_id         = data.aws_route_table.hub_firewall_b.id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "firewall_b_to_west" {
  route_table_id         = data.aws_route_table.hub_firewall_b.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ---- East routes ----

resource "aws_route" "east_to_hub" {
  route_table_id         = data.aws_route_table.east.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.east]
}

resource "aws_route" "east_to_west" {
  route_table_id         = data.aws_route_table.east.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.east]
}

resource "aws_route" "east_b_to_hub" {
  route_table_id         = data.aws_route_table.east_b.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.east]
}

resource "aws_route" "east_b_to_west" {
  route_table_id         = data.aws_route_table.east_b.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.east]
}

# ---- West routes ----

resource "aws_route" "west_to_hub" {
  route_table_id         = data.aws_route_table.west.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.west]
}

resource "aws_route" "west_to_east" {
  route_table_id         = data.aws_route_table.west.id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.west]
}

resource "aws_route" "west_b_to_hub" {
  route_table_id         = data.aws_route_table.west_b.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.west]
}

resource "aws_route" "west_b_to_east" {
  route_table_id         = data.aws_route_table.west_b.id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.west]
}
