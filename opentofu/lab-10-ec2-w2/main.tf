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

resource "tls_private_key" "lab_w2" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab_w2" {
  key_name   = "lab-key-w2"
  public_key = tls_private_key.lab_w2.public_key_openssh
}

resource "local_sensitive_file" "private_key_w2" {
  content         = tls_private_key.lab_w2.private_key_pem
  filename        = "${path.module}/lab-key-w2.pem"
  file_permission = "0600"
}

resource "aws_security_group" "north" {
  name        = "north-sg"
  description = "Allow SSH and ICMP"
  vpc_id      = data.aws_vpc.north.id

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
    Name = "north-sg"
  }
}

resource "aws_security_group" "south" {
  name        = "south-sg"
  description = "Allow SSH and ICMP"
  vpc_id      = data.aws_vpc.south.id

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
    Name = "south-sg"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "north" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet.north.id
  vpc_security_group_ids      = [aws_security_group.north.id]
  key_name                    = aws_key_pair.lab_w2.key_name
  associate_public_ip_address = true

  tags = {
    Name = "north-instance"
  }
}

resource "aws_instance" "south" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet.south.id
  vpc_security_group_ids      = [aws_security_group.south.id]
  key_name                    = aws_key_pair.lab_w2.key_name
  associate_public_ip_address = true

  tags = {
    Name = "south-instance"
  }
}
