# ==================================
# Bastion
# ==================================

output "bastion_public_ip" {
  description = "Public IP of the Bastion Host (SSH jump box)"
  value       = aws_instance.bastion.public_ip
}

output "ssh_bastion" {
  description = "SSH command to connect to the Bastion Host"
  value       = "ssh -i batman.pem ubuntu@${aws_instance.bastion.public_ip}"
}

# ==================================
# Database EC2
# ==================================

output "db_private_ip" {
  description = "Private IP of the database EC2 (PostgreSQL + Elasticsearch)"
  value       = aws_instance.database.private_ip
}

output "ssh_to_db_via_bastion" {
  description = "SSH to DB EC2 via Bastion (run from your laptop)"
  value       = "ssh -i batman.pem -o ProxyJump=ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.database.private_ip}"
}

output "tunnel_postgres" {
  description = "SSH tunnel for PostgreSQL (access at localhost:5432)"
  value       = "ssh -i batman.pem -L 5432:${aws_instance.database.private_ip}:5432 ubuntu@${aws_instance.bastion.public_ip}"
}

output "tunnel_elasticsearch" {
  description = "SSH tunnel for Elasticsearch (access at localhost:9200)"
  value       = "ssh -i batman.pem -L 9200:${aws_instance.database.private_ip}:9200 ubuntu@${aws_instance.bastion.public_ip}"
}

# ==================================
# EKS
# ==================================

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.leads_cluster.endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.leads_cluster.name
}

output "eks_kubeconfig_command" {
  description = "Command to update kubeconfig for kubectl access"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.leads_cluster.name} --region ${var.aws_region}"
}

# ==================================
# Application Access
# ==================================

output "app_url" {
  description = "Application URL (available after NLB DNS propagates — run: kubectl get svc -n ingress-nginx)"
  value       = "Run: kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

# ==================================
# VPC
# ==================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.leads.id
}



# ==================================
# Jenkins
# ==================================

output "jenkins_private_ip" {
  description = "Private IP of the Jenkins EC2"
  value       = aws_instance.jenkins.private_ip
}

output "ssh_to_jenkins_via_bastion" {
  description = "SSH to Jenkins via Bastion"
  value       = "ssh -i batman.pem -o ProxyJump=ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.jenkins.private_ip}"
}

output "tunnel_jenkins" {
  description = "SSH tunnel for Jenkins UI (access at localhost:8080)"
  value       = "ssh -i batman.pem -L 8080:${aws_instance.jenkins.private_ip}:8080 ubuntu@${aws_instance.bastion.public_ip}"
}
