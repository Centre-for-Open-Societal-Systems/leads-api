# ──────────────────────────────────────────────
# Data Source: Latest Ubuntu 22.04 LTS AMI
# ──────────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ──────────────────────────────────────────────
# SSH Key Pair (auto-generated)
# ──────────────────────────────────────────────
# resource "tls_private_key" "ssh" {
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# resource "aws_key_pair" "generated" {
#   key_name   = var.key_name
#   public_key = tls_private_key.ssh.public_key_openssh
# }

# resource "local_file" "private_key" {
#   content         = tls_private_key.ssh.private_key_pem
#   filename        = "${path.module}/${var.key_name}.pem"
#   file_permission = "0400"
# }

# ──────────────────────────────────────────────
# EC2: Bastion Host (Public Subnet)
# Provides secure SSH access to the private backend
# ──────────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_prefix}-bastion"
    Role = "bastion"
  }
}

# ──────────────────────────────────────────────
# EC2: Nginx Reverse Proxy (Public Subnet)
# Routes external traffic to the private backend
# ──────────────────────────────────────────────
resource "aws_instance" "nginx" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.nginx_instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.nginx.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/nginx_user_data.sh.tpl", {
    backend_ip = var.consolidated_ip
    kong_port  = 8000
  })

  tags = {
    Name = "${var.project_prefix}-nginx"
    Role = "nginx"
  }

  depends_on = [
    aws_internet_gateway.leads,
    aws_instance.main
  ]
}

resource "aws_eip" "nginx" {
  instance = aws_instance.nginx.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_prefix}-nginx-eip"
  }

  depends_on = [aws_internet_gateway.leads]
}

# ──────────────────────────────────────────────
# EC2: Main Consolidated Server (Private Subnet)
# Runs ALL services: PostgreSQL, Redis, Elasticsearch,
#                    pgAdmin, Redis Commander, Kibana, Spring App
# ──────────────────────────────────────────────
resource "aws_instance" "main" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.main_instance_type
  key_name      = var.key_name

  # Private subnet — no public IP
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.private.id]
  associate_public_ip_address = false

  # Using IAM Instance Profile for ECR access
  iam_instance_profile = "EC2-ECR-Read-Role"

  # Assign a static private IP so the Nginx proxy always knows where to find it
  private_ip = var.consolidated_ip

  # Larger root volume for all Docker images + volumes
  root_block_device {
    volume_size = 60
    volume_type = "gp3"
  }

  # Use base64gzip to keep user_data well within the 16KB limit
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/consolidated_user_data.sh.tpl", {
    project_prefix = var.project_prefix
    aws_region     = var.aws_region
    docker_image   = var.docker_image

    # DB credentials
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
    es_username = var.es_username
    es_password = var.es_password
  }))

  tags = {
    Name = "${var.project_prefix}-main"
    Role = "all-in-one"
  }

  depends_on = [aws_route_table_association.private]
}
