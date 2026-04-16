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
# -----------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.hub.id
  subnet_ids         = [data.aws_subnet.hub.id]

  tags = {
    Name = "tgw-attach-hub"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "east" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.east.id
  subnet_ids         = [data.aws_subnet.east.id]

  tags = {
    Name = "tgw-attach-east"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "west" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.west.id
  subnet_ids         = [data.aws_subnet.west.id]

  tags = {
    Name = "tgw-attach-west"
  }
}

# -----------------------------------------------
# Firewall endpoint — look up by managed tag
# -----------------------------------------------

data "aws_vpc_endpoint" "firewall" {
  vpc_id = data.aws_vpc.hub.id

  filter {
    name   = "tag:AWSNetworkFirewallManaged"
    values = ["true"]
  }
}

# -----------------------------------------------
# VPC Route Table Updates
# Tell each VPC to route cross-VPC traffic via TGW
# -----------------------------------------------

data "aws_route_table" "hub" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-rt"]
  }
}

data "aws_route_table" "east" {
  filter {
    name   = "tag:Name"
    values = ["east-public-rt"]
  }
}

data "aws_route_table" "west" {
  filter {
    name   = "tag:Name"
    values = ["west-public-rt"]
  }
}

data "aws_route_table" "hub_firewall" {
  filter {
    name   = "tag:Name"
    values = ["hub-firewall-rt"]
  }
}

resource "aws_route" "hub_to_east" {
  route_table_id         = data.aws_route_table.hub.id
  destination_cidr_block = "10.1.0.0/16"
  vpc_endpoint_id        = data.aws_vpc_endpoint.firewall.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "hub_to_west" {
  route_table_id         = data.aws_route_table.hub.id
  destination_cidr_block = "10.2.0.0/16"
  vpc_endpoint_id        = data.aws_vpc_endpoint.firewall.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

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
