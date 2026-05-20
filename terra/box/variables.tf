# ──────────────────────────────────────────────
# Project
# ──────────────────────────────────────────────
variable "project_prefix" {
  description = "Prefix to be used for all resource names"
  type        = string
  default     = "leads"
}

# ──────────────────────────────────────────────
# Region
# ──────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

# ──────────────────────────────────────────────
# Networking
# ──────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the Public Subnet (Bastion + Nginx)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the Private Subnet (Consolidated Backend)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "Availability Zone for subnets"
  type        = string
  default     = "us-west-2a"
}

# ──────────────────────────────────────────────
# EC2
# ──────────────────────────────────────────────
variable "main_instance_type" {
  description = "EC2 instance type for the consolidated backend server"
  type        = string
  default     = "t3.xlarge"
}

variable "nginx_instance_type" {
  description = "EC2 instance type for the Nginx reverse proxy"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of the AWS key pair to create for SSH access"
  type        = string
  default     = "batman"
}

variable "consolidated_ip" {
  description = "Static private IP for the consolidated backend instance"
  type        = string
  default     = "10.0.2.10"
}

# ──────────────────────────────────────────────
# Application
# ──────────────────────────────────────────────
variable "docker_image" {
  description = "ECR image URI for the Leads Spring Boot application"
  type        = string
}

# ──────────────────────────────────────────────
# Database Credentials
# ──────────────────────────────────────────────
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "postgres_db"
}

variable "db_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "postgres_user"
}

variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "es_username" {
  description = "Elasticsearch username"
  type        = string
  default     = "elastic"
}

variable "es_password" {
  description = "Elasticsearch password"
  type        = string
  sensitive   = true
}
