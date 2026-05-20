# ──────────────────────────────────────────────
# Bastion Security Group (Public Subnet)
# ──────────────────────────────────────────────
resource "aws_security_group" "bastion" {
  name        = "${var.project_prefix}-bastion-sg"
  description = "Security group for Bastion Host - SSH access only"
  vpc_id      = aws_vpc.leads.id

  ingress {
    description = "SSH from internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-bastion-sg"
  }
}

# ──────────────────────────────────────────────
# Nginx Security Group (Public Subnet)
# ──────────────────────────────────────────────
resource "aws_security_group" "nginx" {
  name        = "${var.project_prefix}-nginx-sg"
  description = "Security group for Nginx Reverse Proxy"
  vpc_id      = aws_vpc.leads.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH for management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-nginx-sg"
  }
}

# ──────────────────────────────────────────────
# Private Security Group (Backend Consolidated Instance)
# Only accepts traffic from Bastion (SSH) and Nginx (Kong API Gateway)
# ──────────────────────────────────────────────
resource "aws_security_group" "private" {
  name        = "${var.project_prefix}-private-sg"
  description = "Security group for consolidated backend server"
  vpc_id      = aws_vpc.leads.id

  # SSH from Bastion only
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Kong API Gateway from Nginx
  ingress {
    description     = "Kong API Gateway from Nginx"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  # All outbound traffic (needed for ECR pulls, package installs via NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-private-sg"
  }
}
