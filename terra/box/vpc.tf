# ──────────────────────────────────────────────
# VPC
# ──────────────────────────────────────────────
resource "aws_vpc" "verg" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_prefix}-vpc"
  }
}

# ──────────────────────────────────────────────
# Public Subnets
# ──────────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.verg.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_prefix}-public-subnet"
  }
}

# ──────────────────────────────────────────────
# Internet Gateway
# ──────────────────────────────────────────────
resource "aws_internet_gateway" "verg" {
  vpc_id = aws_vpc.verg.id

  tags = {
    Name = "${var.project_prefix}-igw"
  }
}

# ──────────────────────────────────────────────
# Route Table
# ──────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.verg.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.verg.id
  }

  tags = {
    Name = "${var.project_prefix}-public-rt"
  }
}

# Associate Route Table with subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
