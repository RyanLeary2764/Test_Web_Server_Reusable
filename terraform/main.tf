data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
resource "aws_vpc" "preview" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.project_name }
}
resource "aws_subnet" "preview" {
  vpc_id            = aws_vpc.preview.id
  cidr_block        = "10.42.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}
resource "aws_internet_gateway" "preview" {
  vpc_id = aws_vpc.preview.id
}
resource "aws_route_table" "preview" {
  vpc_id = aws_vpc.preview.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.preview.id
  }
}
resource "aws_route_table_association" "preview" {
  subnet_id      = aws_subnet.preview.id
  route_table_id = aws_route_table.preview.id
}
resource "aws_security_group" "preview" {
  name_prefix = "${var.project_name}-"
  description = "Restricted SSH and HTTP preview access"
  vpc_id      = aws_vpc.preview.id
  ingress {
    description = "SSH from operator network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    description = "HTTP preview from operator network"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_key_pair" "preview" {
  key_name_prefix = "${var.project_name}-"
  public_key      = file(pathexpand(var.ssh_public_key_path))
}
resource "aws_instance" "preview" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.preview.id
  vpc_security_group_ids      = [aws_security_group.preview.id]
  key_name                    = aws_key_pair.preview.key_name
  associate_public_ip_address = true
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 12
    encrypted   = true
  }
  tags       = { Name = var.project_name }
  depends_on = [aws_route_table_association.preview]
}
