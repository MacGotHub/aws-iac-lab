resource "aws_vpc" "east" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "east-vpc"
  }
}

# ---- AZ-a ----

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.east.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "east-public-subnet"
  }
}

# ---- AZ-b ----

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.east.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "east-public-subnet-b"
  }
}

resource "aws_internet_gateway" "east" {
  vpc_id = aws_vpc.east.id

  tags = {
    Name = "east-igw"
  }
}

# ---- Route tables ----

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.east.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.east.id
  }

  tags = {
    Name = "east-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "public_b" {
  vpc_id = aws_vpc.east.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.east.id
  }

  tags = {
    Name = "east-public-rt-b"
  }
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_b.id
}
