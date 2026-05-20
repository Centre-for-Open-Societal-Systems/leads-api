# ──────────────────────────────────────────────
# Network
# ──────────────────────────────────────────────
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.leads.id
}

# ──────────────────────────────────────────────
# Public Access
# ──────────────────────────────────────────────
output "nginx_public_ip" {
  description = "Public IP of the Nginx reverse proxy (EIP)"
  value       = aws_eip.nginx.public_ip
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion Host"
  value       = aws_instance.bastion.public_ip
}

# ──────────────────────────────────────────────
# Application URLs (via Nginx)
# ──────────────────────────────────────────────
output "app_url" {
  description = "Leads API URL via Nginx"
  value       = "http://${aws_eip.nginx.public_ip}/leads"
}

# ──────────────────────────────────────────────
# Private Backend & Administration SSH Tunnels
# ──────────────────────────────────────────────
output "main_private_ip" {
  description = "Private IP of the consolidated backend server"
  value       = aws_instance.main.private_ip
}

output "ssh_bastion" {
  description = "SSH command to connect to the Bastion Host"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.bastion.public_ip}"
}

output "ssh_main_via_bastion" {
  description = "SSH command to reach the private backend via Bastion (ProxyJump)"
  value       = "ssh -i ${var.key_name}.pem -J ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.main.private_ip}"
}

output "ssh_tunnel_admin_tools" {
  description = "One-click SSH command to securely tunnel all admin tools (pgAdmin, Redis, Kibana, Elasticsearch, Kong) to your localhost"
  value       = "ssh -i ${var.key_name}.pem -J ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.main.private_ip} -L 5050:localhost:5050 -L 8081:localhost:8081 -L 5601:localhost:5601 -L 9200:localhost:9200 -L 8001:localhost:8001 -N"
}

# output "private_key_file" {
#   description = "Path to the generated SSH private key file"
#   value       = local_file.private_key.filename
# }
