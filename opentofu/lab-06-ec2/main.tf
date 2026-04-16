# -----------------------------------------------
# Data sources — look up existing VPCs and subnets
# -----------------------------------------------

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
# SSH Key Pair
# -----------------------------------------------

resource "tls_private_key" "lab" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab" {
  key_name   = "lab-key"
  public_key = tls_private_key.lab.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.lab.private_key_pem
  filename        = "${path.module}/lab-key.pem"
  file_permission = "0600"
}

# -----------------------------------------------
# Security Groups
# -----------------------------------------------

resource "aws_security_group" "east" {
  name        = "east-sg"
  description = "Allow SSH and ICMP"
  vpc_id      = data.aws_vpc.east.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "east-sg"
  }
}

resource "aws_security_group" "west" {
  name        = "west-sg"
  description = "Allow SSH and ICMP"
  vpc_id      = data.aws_vpc.west.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "west-sg"
  }
}

# -----------------------------------------------
# EC2 Instances
# -----------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "east" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet.east.id
  vpc_security_group_ids      = [aws_security_group.east.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  tags = {
    Name = "east-instance"
  }
}

resource "aws_instance" "west" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet.west.id
  vpc_security_group_ids      = [aws_security_group.west.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  tags = {
    Name = "west-instance"
  }
}
