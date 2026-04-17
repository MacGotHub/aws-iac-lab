# -----------------------------------------------
# Data sources — us-west-2 VPCs (default provider)
# -----------------------------------------------

data "aws_vpc" "hub" {
  filter {
    name   = "tag:Name"
    values = ["hub-vpc-w2"]
  }
}

data "aws_vpc" "north" {
  filter {
    name   = "tag:Name"
    values = ["north-vpc"]
  }
}

data "aws_vpc" "south" {
  filter {
    name   = "tag:Name"
    values = ["south-vpc"]
  }
}

# ---- AZ-a subnets ----

data "aws_subnet" "hub" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-subnet-w2"]
  }
}

data "aws_subnet" "north" {
  filter {
    name   = "tag:Name"
    values = ["north-public-subnet"]
  }
}

data "aws_subnet" "south" {
  filter {
    name   = "tag:Name"
    values = ["south-public-subnet"]
  }
}

# ---- AZ-b subnets ----

data "aws_subnet" "hub_b" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-subnet-w2-b"]
  }
}

data "aws_subnet" "north_b" {
  filter {
    name   = "tag:Name"
    values = ["north-public-subnet-b"]
  }
}

data "aws_subnet" "south_b" {
  filter {
    name   = "tag:Name"
    values = ["south-public-subnet-b"]
  }
}

# -----------------------------------------------
# Data sources — us-east-1 TGW (aliased provider)
# -----------------------------------------------

data "aws_ec2_transit_gateway" "east" {
  provider = aws.east

  filter {
    name   = "tag:Name"
    values = ["lab-tgw"]
  }
}

# -----------------------------------------------
# West TGW
# -----------------------------------------------

resource "aws_ec2_transit_gateway" "main" {
  description                     = "Hub and spoke transit gateway - us-west-2"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name = "lab-tgw-w2"
  }
}

# -----------------------------------------------
# TGW Attachments — west VPCs
# -----------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.hub.id
  subnet_ids         = [data.aws_subnet.hub.id, data.aws_subnet.hub_b.id]

  tags = {
    Name = "tgw-attach-hub-w2"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "north" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.north.id
  subnet_ids         = [data.aws_subnet.north.id, data.aws_subnet.north_b.id]

  tags = {
    Name = "tgw-attach-north"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "south" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = data.aws_vpc.south.id
  subnet_ids         = [data.aws_subnet.south.id, data.aws_subnet.south_b.id]

  tags = {
    Name = "tgw-attach-south"
  }
}

# -----------------------------------------------
# TGW Peering — west initiates, east accepts
# -----------------------------------------------

resource "aws_ec2_transit_gateway_peering_attachment" "west_to_east" {
  transit_gateway_id      = aws_ec2_transit_gateway.main.id
  peer_transit_gateway_id = data.aws_ec2_transit_gateway.east.id
  peer_region             = "us-east-1"

  tags = {
    Name = "tgw-peering-w2-to-e1"
  }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "east_accepts" {
  provider                        = aws.east
  transit_gateway_attachment_id   = aws_ec2_transit_gateway_peering_attachment.west_to_east.id

  tags = {
    Name = "tgw-peering-w2-to-e1"
  }
}

# -----------------------------------------------
# Firewall endpoint locals — update after lab-08-firewall-w2 apply
# -----------------------------------------------

locals {
  firewall_endpoint_az_a = "vpce-0029dc625370e0870"
  firewall_endpoint_az_b = "vpce-0771d8bba389ad990"
}

# -----------------------------------------------
# West route tables
# -----------------------------------------------

data "aws_route_table" "hub" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-rt-w2"]
  }
}

data "aws_route_table" "hub_b" {
  filter {
    name   = "tag:Name"
    values = ["hub-public-rt-w2-b"]
  }
}

data "aws_route_table" "hub_firewall" {
  filter {
    name   = "tag:Name"
    values = ["hub-firewall-rt-w2"]
  }
}

data "aws_route_table" "hub_firewall_b" {
  filter {
    name   = "tag:Name"
    values = ["hub-firewall-rt-w2-b"]
  }
}

data "aws_route_table" "north" {
  filter {
    name   = "tag:Name"
    values = ["north-public-rt"]
  }
}

data "aws_route_table" "north_b" {
  filter {
    name   = "tag:Name"
    values = ["north-public-rt-b"]
  }
}

data "aws_route_table" "south" {
  filter {
    name   = "tag:Name"
    values = ["south-public-rt"]
  }
}

data "aws_route_table" "south_b" {
  filter {
    name   = "tag:Name"
    values = ["south-public-rt-b"]
  }
}

# ---- Hub AZ-a routes (spoke traffic → firewall endpoint) ----

resource "aws_route" "hub_to_north" {
  route_table_id         = data.aws_route_table.hub.id
  destination_cidr_block = "10.4.0.0/16"
  vpc_endpoint_id        = local.firewall_endpoint_az_a
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "hub_to_south" {
  route_table_id         = data.aws_route_table.hub.id
  destination_cidr_block = "10.5.0.0/16"
  vpc_endpoint_id        = local.firewall_endpoint_az_a
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ---- Hub AZ-b routes ----

resource "aws_route" "hub_b_to_north" {
  route_table_id         = data.aws_route_table.hub_b.id
  destination_cidr_block = "10.4.0.0/16"
  vpc_endpoint_id        = local.firewall_endpoint_az_b
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "hub_b_to_south" {
  route_table_id         = data.aws_route_table.hub_b.id
  destination_cidr_block = "10.5.0.0/16"
  vpc_endpoint_id        = local.firewall_endpoint_az_b
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ---- Firewall AZ-a routes (post-inspection back to TGW) ----

resource "aws_route" "firewall_to_north" {
  route_table_id         = data.aws_route_table.hub_firewall.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "firewall_to_south" {
  route_table_id         = data.aws_route_table.hub_firewall.id
  destination_cidr_block = "10.5.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ---- Firewall AZ-b routes ----

resource "aws_route" "firewall_b_to_north" {
  route_table_id         = data.aws_route_table.hub_firewall_b.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "firewall_b_to_south" {
  route_table_id         = data.aws_route_table.hub_firewall_b.id
  destination_cidr_block = "10.5.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ---- North routes ----

resource "aws_route" "north_to_hub" {
  route_table_id         = data.aws_route_table.north.id
  destination_cidr_block = "10.3.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.north]
}

resource "aws_route" "north_to_south" {
  route_table_id         = data.aws_route_table.north.id
  destination_cidr_block = "10.5.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.north]
}

resource "aws_route" "north_to_e1_hub" {
  route_table_id         = data.aws_route_table.north.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "north_to_e1_east" {
  route_table_id         = data.aws_route_table.north.id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "north_to_e1_west" {
  route_table_id         = data.aws_route_table.north.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "north_b_to_hub" {
  route_table_id         = data.aws_route_table.north_b.id
  destination_cidr_block = "10.3.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.north]
}

resource "aws_route" "north_b_to_south" {
  route_table_id         = data.aws_route_table.north_b.id
  destination_cidr_block = "10.5.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.north]
}

resource "aws_route" "north_b_to_e1_hub" {
  route_table_id         = data.aws_route_table.north_b.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "north_b_to_e1_east" {
  route_table_id         = data.aws_route_table.north_b.id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "north_b_to_e1_west" {
  route_table_id         = data.aws_route_table.north_b.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

# ---- South routes ----

resource "aws_route" "south_to_hub" {
  route_table_id         = data.aws_route_table.south.id
  destination_cidr_block = "10.3.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.south]
}

resource "aws_route" "south_to_north" {
  route_table_id         = data.aws_route_table.south.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.south]
}

resource "aws_route" "south_to_e1_hub" {
  route_table_id         = data.aws_route_table.south.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "south_to_e1_east" {
  route_table_id         = data.aws_route_table.south.id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "south_to_e1_west" {
  route_table_id         = data.aws_route_table.south.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "south_b_to_hub" {
  route_table_id         = data.aws_route_table.south_b.id
  destination_cidr_block = "10.3.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.south]
}

resource "aws_route" "south_b_to_north" {
  route_table_id         = data.aws_route_table.south_b.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.south]
}

resource "aws_route" "south_b_to_e1_hub" {
  route_table_id         = data.aws_route_table.south_b.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "south_b_to_e1_east" {
  route_table_id         = data.aws_route_table.south_b.id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "south_b_to_e1_west" {
  route_table_id         = data.aws_route_table.south_b.id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

# -----------------------------------------------
# TGW static routes — cross-region via peering
# Both TGW default route tables need entries pointing
# the other region's CIDRs over the peering attachment
# -----------------------------------------------

data "aws_ec2_transit_gateway_route_table" "west" {
  filter {
    name   = "transit-gateway-id"
    values = [aws_ec2_transit_gateway.main.id]
  }
  filter {
    name   = "default-association-route-table"
    values = ["true"]
  }
}

data "aws_ec2_transit_gateway_route_table" "east" {
  provider = aws.east

  filter {
    name   = "transit-gateway-id"
    values = [data.aws_ec2_transit_gateway.east.id]
  }
  filter {
    name   = "default-association-route-table"
    values = ["true"]
  }
}

# West TGW: route east-region CIDRs over peering
resource "aws_ec2_transit_gateway_route" "west_to_east_hub" {
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.west.id
  destination_cidr_block         = "10.0.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_ec2_transit_gateway_route" "west_to_east_east" {
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.west.id
  destination_cidr_block         = "10.1.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_ec2_transit_gateway_route" "west_to_east_west" {
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.west.id
  destination_cidr_block         = "10.2.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

# East TGW: route west-region CIDRs over peering
resource "aws_ec2_transit_gateway_route" "east_to_west_hub" {
  provider                       = aws.east
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.east.id
  destination_cidr_block         = "10.3.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_ec2_transit_gateway_route" "east_to_west_north" {
  provider                       = aws.east
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.east.id
  destination_cidr_block         = "10.4.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_ec2_transit_gateway_route" "east_to_west_south" {
  provider                       = aws.east
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.east.id
  destination_cidr_block         = "10.5.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.west_to_east.id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

# -----------------------------------------------
# East VPC route tables — add routes to west-region CIDRs
# -----------------------------------------------

data "aws_route_table" "east_public" {
  provider = aws.east
  filter {
    name   = "tag:Name"
    values = ["east-public-rt"]
  }
}

data "aws_route_table" "east_public_b" {
  provider = aws.east
  filter {
    name   = "tag:Name"
    values = ["east-public-rt-b"]
  }
}

data "aws_route_table" "west_public" {
  provider = aws.east
  filter {
    name   = "tag:Name"
    values = ["west-public-rt"]
  }
}

data "aws_route_table" "west_public_b" {
  provider = aws.east
  filter {
    name   = "tag:Name"
    values = ["west-public-rt-b"]
  }
}

resource "aws_route" "east_to_w2_north" {
  provider               = aws.east
  route_table_id         = data.aws_route_table.east_public.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "east_to_w2_south" {
  provider               = aws.east
  route_table_id         = data.aws_route_table.east_public.id
  destination_cidr_block = "10.5.0.0/16"
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "east_b_to_w2_north" {
  provider               = aws.east
  route_table_id         = data.aws_route_table.east_public_b.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "east_b_to_w2_south" {
  provider               = aws.east
  route_table_id         = data.aws_route_table.east_public_b.id
  destination_cidr_block = "10.5.0.0/16"
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "west_e1_to_w2_north" {
  provider               = aws.east
  route_table_id         = data.aws_route_table.west_public.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "west_e1_to_w2_south" {
  provider               = aws.east
  route_table_id         = data.aws_route_table.west_public.id
  destination_cidr_block = "10.5.0.0/16"
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "west_e1_b_to_w2_north" {
  provider               = aws.east
  route_table_id         = data.aws_route_table.west_public_b.id
  destination_cidr_block = "10.4.0.0/16"
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}

resource "aws_route" "west_e1_b_to_w2_south" {
  provider               = aws.east
  route_table_id         = data.aws_route_table.west_public_b.id
  destination_cidr_block = "10.5.0.0/16"
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
  depends_on             = [aws_ec2_transit_gateway_peering_attachment_accepter.east_accepts]
}
