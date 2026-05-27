# ==================================
# Provider
# ==================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Wait for the EKS cluster data to authenticate the Helm and Kubectl providers
data "aws_eks_cluster_auth" "cluster_auth" {
  name = aws_eks_cluster.leads_cluster.name
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.leads_cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.leads_cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster_auth.token
  }
}

provider "kubectl" {
  host                   = aws_eks_cluster.leads_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.leads_cluster.certificate_authority[0].data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.leads_cluster.name, "--region", var.aws_region]
  }
}

# ==================================
# VPC
# ==================================

resource "aws_vpc" "leads" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "VPC: ${var.project_prefix}-${var.aws_region}"
  }
}

# ==================================
# Subnets (3 total: 2 public + 1 private)
# ==================================

# Public Subnet 1 (us-west-2a) — Bastion, NAT Gateway
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.leads.id
  cidr_block              = var.cidr_public_subnet[0]
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "Subnet-public: ${var.project_prefix} public 1 (${var.availability_zones[0]})"
    "kubernetes.io/role/elb" = "1"
  }
}

# Public Subnet 2 (us-west-2b) — Required by EKS (2 AZ minimum)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.leads.id
  cidr_block              = var.cidr_public_subnet[1]
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "Subnet-public: ${var.project_prefix} public 2 (${var.availability_zones[1]})"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnet (us-west-2a) — EKS Worker Nodes + DB EC2
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.leads.id
  cidr_block        = var.cidr_private_subnet
  availability_zone = var.availability_zones[0]

  tags = {
    Name                              = "Subnet-private: ${var.project_prefix} EKS + DB (${var.availability_zones[0]})"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ==================================
# Internet Gateway + Public Routing
# ==================================

resource "aws_internet_gateway" "leads" {
  vpc_id = aws_vpc.leads.id

  tags = {
    Name = "IGW: ${var.project_prefix}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.leads.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.leads.id
  }

  tags = {
    Name = "RT: Public Route Table"
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ==================================
# NAT Gateway + Private Routing
# ==================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "EIP: NAT Gateway ${var.project_prefix}"
  }
}

resource "aws_nat_gateway" "leads" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "NAT GW: ${var.project_prefix}"
  }

  depends_on = [aws_internet_gateway.leads]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.leads.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.leads.id
  }

  tags = {
    Name = "RT: Private Route Table"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ==================================
# Ubuntu AMI Data Source
# ==================================

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

# ==================================
# Security Groups
# ==================================

# Bastion SG — SSH from internet only
resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_prefix}-bastion-sg"
  description = "Security group for Bastion Host - SSH from internet"
  vpc_id      = aws_vpc.leads.id

  ingress {
    description = "Allow SSH from anywhere"
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
    Name = "SG: Bastion ${var.project_prefix}"
  }
}

# Private SG — VPC-internal traffic only + SSH from Bastion
resource "aws_security_group" "private_sg" {
  name        = "${var.project_prefix}-private-sg"
  description = "Security group for private instances - VPC-internal only"
  vpc_id      = aws_vpc.leads.id

  ingress {
    description = "Allow all internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description     = "Allow SSH from Bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG: Private ${var.project_prefix}"
  }
}

# EKS Cluster SG — control plane
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.project_prefix}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.leads.id

  ingress {
    description = "Allow all traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG: EKS Cluster ${var.project_prefix}"
  }
}

# EKS Node SG — worker nodes (allows intra-VPC for Ingress Controller → pods)
resource "aws_security_group" "eks_node_sg" {
  name        = "${var.project_prefix}-eks-node-sg"
  description = "Additional SG for EKS worker nodes - allows intra-VPC access for Ingress Controller"
  vpc_id      = aws_vpc.leads.id

  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG: EKS Node ${var.project_prefix}"
  }
}

# ==================================
# Bastion Host (Public Subnet)
# ==================================

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.key_name

  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_prefix} - Bastion"
    Role = "bastion"
  }
}

# ==================================
# Database EC2 (Private Subnet)
# Runs: PostgreSQL 16 + Elasticsearch 8.13
# ==================================

resource "aws_instance" "database" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.db_instance_type
  key_name      = var.key_name

  # Using existing IAM Role (Instance Profile) for ECR access
  iam_instance_profile = "EC2-ECR-Read-Role"

  # Deploy in the private subnet
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]

  # Static private IP for service discovery
  private_ip = var.db_private_ip

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
  })

  tags = {
    Name = "${var.project_prefix} - Database"
    Role = "database"
  }

  depends_on = [aws_route_table_association.private]
}

# ==================================
# EKS Cluster IAM Roles
# ==================================

# --- Cluster Role ---
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-${var.project_prefix}-${var.aws_region}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "IAM: EKS Cluster Role ${var.project_prefix}"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

# --- Node Group Role ---
resource "aws_iam_role" "eks_node_role" {
  name = "eks-${var.project_prefix}-${var.aws_region}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "IAM: EKS Node Group Role ${var.project_prefix}"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_read_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# ==================================
# EKS Launch Template (attaches node SG)
# ==================================

resource "aws_launch_template" "eks_node_lt" {
  name_prefix = "${var.project_prefix}-eks-node-"
  description = "Launch template for EKS nodes with VPC-access SG"

  vpc_security_group_ids = [
    aws_security_group.eks_node_sg.id,
    aws_eks_cluster.leads_cluster.vpc_config[0].cluster_security_group_id
  ]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "EKS Node: ${var.project_prefix}"
    }
  }

  tags = {
    Name = "LT: EKS Node ${var.project_prefix}"
  }
}

# ==================================
# EKS Cluster
# ==================================

resource "aws_eks_cluster" "leads_cluster" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id,
      aws_subnet.private.id
    ]
    security_group_ids      = [aws_security_group.eks_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]

  tags = {
    Name = "EKS: ${var.project_prefix}"
  }
}

# ==================================
# EKS Managed Node Group
# ==================================

resource "aws_eks_node_group" "leads_nodes" {
  cluster_name    = aws_eks_cluster.leads_cluster.name
  node_group_name = "${var.project_prefix}-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.private.id]

  instance_types = [var.eks_node_instance_type]

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 1
  }

  # Attach the launch template so nodes get the VPC-access SG
  launch_template {
    id      = aws_launch_template.eks_node_lt.id
    version = aws_launch_template.eks_node_lt.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_policy,
    aws_nat_gateway.leads
  ]

  tags = {
    Name = "EKS Node: ${var.project_prefix}"
  }
}

# ==================================
# NGINX Ingress Controller via Helm
# ==================================

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.10.1"

  values = [
    <<-EOF
    controller:
      service:
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    EOF
  ]

  depends_on = [
    aws_eks_node_group.leads_nodes
  ]
}

# ==================================
# Kong API Gateway via Helm (Phase 2)
# ==================================
# Deployed in DB-less mode, behind NGINX. 
# Proxy service is ClusterIP (no AWS NLB created).
# Ingress Controller is enabled to process KongPlugin CRDs.

resource "helm_release" "kong" {
  name             = "kong"
  repository       = "https://charts.konghq.com"
  chart            = "kong"
  namespace        = "kong"
  create_namespace = true
  version          = "2.38.0"

  values = [
    <<-EOF
    env:
      database: "off"
    proxy:
      type: ClusterIP
    ingressController:
      installCRDs: true
      ingressClass: kong
    EOF
  ]

  depends_on = [
    aws_eks_node_group.leads_nodes
  ]
}

# ==================================
# Kubernetes Manifests Deployment
# ==================================
# Applied via Terraform kubectl provider — same pattern as OAN.
# Strict deployment order enforced using explicit dependencies.

# ----------------------------------
# Secrets
# ----------------------------------
data "kubectl_file_documents" "secrets" {
  content = templatefile("${path.module}/k8/00-secrets.yaml.tpl", {
    db_username            = var.db_username
    db_password            = var.db_password
    es_username            = var.es_username
    es_password            = var.es_password
    a2c_webhook_api_key    = var.a2c_webhook_api_key
    a2c_webhook_api_secret = var.a2c_webhook_api_secret
  })
}

resource "kubectl_manifest" "secrets" {
  for_each   = data.kubectl_file_documents.secrets.manifests
  yaml_body  = each.value
  depends_on = [aws_eks_node_group.leads_nodes]
}

# ----------------------------------
# ConfigMap
# ----------------------------------
data "kubectl_file_documents" "configmap" {
  content = templatefile("${path.module}/k8/01-configmap.yaml.tpl", {
    db_private_ip       = var.db_private_ip
    db_name             = var.db_name
    a2c_webhook_url     = var.a2c_webhook_url
    a2c_webhook_enabled = var.a2c_webhook_enabled
  })
}

resource "kubectl_manifest" "configmap" {
  for_each   = data.kubectl_file_documents.configmap.manifests
  yaml_body  = each.value
  depends_on = [aws_eks_node_group.leads_nodes]
}

# ----------------------------------
# Redis
# ----------------------------------
data "kubectl_file_documents" "redis" {
  content = file("${path.module}/k8/02-redis.yaml")
}

resource "kubectl_manifest" "redis" {
  for_each   = data.kubectl_file_documents.redis.manifests
  yaml_body  = each.value
  depends_on = [aws_eks_node_group.leads_nodes]
}

# ----------------------------------
# ExternalName Services (DB + ES)
# ----------------------------------
data "kubectl_file_documents" "db_external" {
  content = templatefile("${path.module}/k8/03-db-external.yaml.tpl", {
    db_private_ip = var.db_private_ip
  })
}

resource "kubectl_manifest" "db_external" {
  for_each   = data.kubectl_file_documents.db_external.manifests
  yaml_body  = each.value
  depends_on = [aws_eks_node_group.leads_nodes]
}

# ----------------------------------
# Spring Boot Application
# ----------------------------------
data "kubectl_file_documents" "leads_app" {
  content = templatefile("${path.module}/k8/04-leads-app.yaml.tpl", {
    docker_image = var.docker_image
  })
}

resource "kubectl_manifest" "leads_app" {
  for_each         = data.kubectl_file_documents.leads_app.manifests
  yaml_body        = each.value
  apply_only       = true
  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.secrets,
    kubectl_manifest.configmap,
    kubectl_manifest.redis,
    kubectl_manifest.db_external
  ]
}

# ----------------------------------
# Phase 2 Routing (NGINX -> Kong -> App)
# ----------------------------------

data "kubectl_file_documents" "nginx_to_kong" {
  content = file("${path.module}/k8/05-nginx-to-kong.yaml")
}

resource "kubectl_manifest" "nginx_to_kong" {
  for_each  = data.kubectl_file_documents.nginx_to_kong.manifests
  yaml_body = each.value

  depends_on = [
    helm_release.ingress_nginx,
    helm_release.kong
  ]
}

data "kubectl_file_documents" "kong_to_app" {
  content = file("${path.module}/k8/06-kong-to-app.yaml")
}

resource "kubectl_manifest" "kong_to_app" {
  for_each  = data.kubectl_file_documents.kong_to_app.manifests
  yaml_body = each.value

  depends_on = [
    helm_release.kong,
    kubectl_manifest.leads_app
  ]
}
