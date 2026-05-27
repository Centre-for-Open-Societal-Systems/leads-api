# ==================================
# General
# ==================================

variable "project_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "leads"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-1"
}

# ==================================
# Networking
# ==================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_public_subnet" {
  description = "CIDR blocks for the 2 public subnets (EKS requires 2 AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.3.0/24"]
}

variable "cidr_private_subnet" {
  description = "CIDR block for the private subnet (EKS nodes + DB EC2)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zones" {
  description = "Availability Zones (EKS requires at least 2)"
  type        = list(string)
  default     = ["us-west-1a", "us-west-1c"]
}

# ==================================
# SSH Key
# ==================================

variable "key_name" {
  description = "Name of the existing AWS key pair for SSH access"
  type        = string
  default     = "leads-management"
}

# ==================================
# Database EC2
# ==================================

variable "db_instance_type" {
  description = "Instance type for the database EC2 (runs PostgreSQL + Elasticsearch)"
  type        = string
  default     = "t3.xlarge"
}

variable "db_private_ip" {
  description = "Static private IP for the database EC2 instance"
  type        = string
  default     = "10.0.2.10"
}

# ==================================
# Database Credentials
# ==================================

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "leads_db"
}

variable "db_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "leads_user"
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

# ==================================
# Application
# ==================================

variable "docker_image" {
  description = "ECR image URI for the Spring Boot application"
  type        = string
}

# ==================================
# EKS
# ==================================

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "leads-cluster"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.31"
}

variable "eks_node_instance_type" {
  description = "Instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

# ==================================
# Webhook Configuration
# ==================================

variable "a2c_webhook_url" {
  description = "Webhook URL for initiating leads"
  type        = string
  default     = "http://development.localhost:8000/api/method/oan_a2c.api.v1.webhooks.lead_inbound"
}

variable "a2c_webhook_enabled" {
  description = "Flag to enable or disable the webhook"
  type        = string
  default     = "true"
}

variable "a2c_webhook_api_key" {
  description = "API key for the webhook"
  type        = string
  sensitive   = true
}

variable "a2c_webhook_api_secret" {
  description = "API secret for the webhook"
  type        = string
  sensitive   = true
}
