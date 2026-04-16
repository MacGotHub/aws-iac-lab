resource "aws_vpc" "west" {
  cidr_block = "10.2.0.0/16"

  tags = {
    Name = "west-vpc"
  }
}

# ---- AZ-a ----

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.west.id
  cidr_block        = "10.2.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "west-public-subnet"
  }
}

# ---- AZ-b ----

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.west.id
  cidr_block        = "10.2.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "west-public-subnet-b"
  }
}

resource "aws_internet_gateway" "west" {
  vpc_id = aws_vpc.west.id

  tags = {
    Name = "west-igw"
  }
}

# ---- Route tables ----

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.west.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.west.id
  }

  tags = {
    Name = "west-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "public_b" {
  vpc_id = aws_vpc.west.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.west.id
  }

  tags = {
    Name = "west-public-rt-b"
  }
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_b.id
}
