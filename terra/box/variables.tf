# ──────────────────────────────────────────────
# Project
# ──────────────────────────────────────────────
variable "project_prefix" {
  description = "Prefix to be used for all resource names"
  type        = string
  default = "leads"
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
  description = "CIDR block for Public Subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "AZ for Public Subnet"
  type        = string
  default     = "us-west-2a"
}

# ──────────────────────────────────────────────
# EC2
# ──────────────────────────────────────────────
variable "main_instance_type" {
  description = "EC2 instance type for the main consolidated server"
  type        = string
  default     = "t3.xlarge"
}

variable "key_name" {
  description = "Name of the existing AWS key pair for SSH access"
  type        = string
}

# variable "my_ip" {
#   description = "Your public IP (CIDR format) for SSH access to instances (e.g., 203.0.113.5/32)"
#   type        = string
# }

# ──────────────────────────────────────────────
# Application
# ──────────────────────────────────────────────
variable "docker_image" {
  description = "ECR image for the application"
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
}
