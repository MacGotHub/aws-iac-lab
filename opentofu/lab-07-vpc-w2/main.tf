# -----------------------------------------------
# Hub VPC — us-west-2 (10.3.0.0/16)
# -----------------------------------------------

resource "aws_vpc" "hub" {
  cidr_block = "10.3.0.0/16"

  tags = {
    Name = "hub-vpc-w2"
  }
}

# ---- AZ-a ----

resource "aws_subnet" "hub_public" {
  vpc_id            = aws_vpc.hub.id
  cidr_block        = "10.3.1.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "hub-public-subnet-w2"
  }
}

resource "aws_subnet" "hub_firewall" {
  vpc_id            = aws_vpc.hub.id
  cidr_block        = "10.3.2.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "hub-firewall-subnet-w2"
  }
}

# ---- AZ-b ----

resource "aws_subnet" "hub_public_b" {
  vpc_id            = aws_vpc.hub.id
  cidr_block        = "10.3.3.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "hub-public-subnet-w2-b"
  }
}

resource "aws_subnet" "hub_firewall_b" {
  vpc_id            = aws_vpc.hub.id
  cidr_block        = "10.3.4.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "hub-firewall-subnet-w2-b"
  }
}

resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id

  tags = {
    Name = "hub-igw-w2"
  }
}

# ---- Route tables ----

resource "aws_route_table" "hub_public" {
  vpc_id = aws_vpc.hub.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }

  tags = {
    Name = "hub-public-rt-w2"
  }
}

resource "aws_route_table_association" "hub_public" {
  subnet_id      = aws_subnet.hub_public.id
  route_table_id = aws_route_table.hub_public.id
}

resource "aws_route_table" "hub_public_b" {
  vpc_id = aws_vpc.hub.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }

  tags = {
    Name = "hub-public-rt-w2-b"
  }
}

resource "aws_route_table_association" "hub_public_b" {
  subnet_id      = aws_subnet.hub_public_b.id
  route_table_id = aws_route_table.hub_public_b.id
}

resource "aws_route_table" "hub_firewall" {
  vpc_id = aws_vpc.hub.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }

  tags = {
    Name = "hub-firewall-rt-w2"
  }
}

resource "aws_route_table_association" "hub_firewall" {
  subnet_id      = aws_subnet.hub_firewall.id
  route_table_id = aws_route_table.hub_firewall.id
}

resource "aws_route_table" "hub_firewall_b" {
  vpc_id = aws_vpc.hub.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }

  tags = {
    Name = "hub-firewall-rt-w2-b"
  }
}

resource "aws_route_table_association" "hub_firewall_b" {
  subnet_id      = aws_subnet.hub_firewall_b.id
  route_table_id = aws_route_table.hub_firewall_b.id
}

# -----------------------------------------------
# North Spoke VPC (10.4.0.0/16)
# -----------------------------------------------

resource "aws_vpc" "north" {
  cidr_block = "10.4.0.0/16"

  tags = {
    Name = "north-vpc"
  }
}

resource "aws_subnet" "north" {
  vpc_id            = aws_vpc.north.id
  cidr_block        = "10.4.1.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "north-public-subnet"
  }
}

resource "aws_subnet" "north_b" {
  vpc_id            = aws_vpc.north.id
  cidr_block        = "10.4.2.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "north-public-subnet-b"
  }
}

resource "aws_internet_gateway" "north" {
  vpc_id = aws_vpc.north.id

  tags = {
    Name = "north-igw"
  }
}

resource "aws_route_table" "north" {
  vpc_id = aws_vpc.north.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.north.id
  }

  tags = {
    Name = "north-public-rt"
  }
}

resource "aws_route_table_association" "north" {
  subnet_id      = aws_subnet.north.id
  route_table_id = aws_route_table.north.id
}

resource "aws_route_table" "north_b" {
  vpc_id = aws_vpc.north.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.north.id
  }

  tags = {
    Name = "north-public-rt-b"
  }
}

resource "aws_route_table_association" "north_b" {
  subnet_id      = aws_subnet.north_b.id
  route_table_id = aws_route_table.north_b.id
}

# -----------------------------------------------
# South Spoke VPC (10.5.0.0/16)
# -----------------------------------------------

resource "aws_vpc" "south" {
  cidr_block = "10.5.0.0/16"

  tags = {
    Name = "south-vpc"
  }
}

resource "aws_subnet" "south" {
  vpc_id            = aws_vpc.south.id
  cidr_block        = "10.5.1.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "south-public-subnet"
  }
}

resource "aws_subnet" "south_b" {
  vpc_id            = aws_vpc.south.id
  cidr_block        = "10.5.2.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "south-public-subnet-b"
  }
}

resource "aws_internet_gateway" "south" {
  vpc_id = aws_vpc.south.id

  tags = {
    Name = "south-igw"
  }
}

resource "aws_route_table" "south" {
  vpc_id = aws_vpc.south.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.south.id
  }

  tags = {
    Name = "south-public-rt"
  }
}

resource "aws_route_table_association" "south" {
  subnet_id      = aws_subnet.south.id
  route_table_id = aws_route_table.south.id
}

resource "aws_route_table" "south_b" {
  vpc_id = aws_vpc.south.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.south.id
  }

  tags = {
    Name = "south-public-rt-b"
  }
}

resource "aws_route_table_association" "south_b" {
  subnet_id      = aws_subnet.south_b.id
  route_table_id = aws_route_table.south_b.id
}
