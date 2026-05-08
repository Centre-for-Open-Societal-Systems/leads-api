# ──────────────────────────────────────────────
# Application
# ──────────────────────────────────────────────
output "main_public_ip" {
  description = "Public IP of the Verg consolidated server"
  value       = aws_instance.main.public_ip
}

output "app_url" {
  description = "URL to access the Verg application"
  value       = "http://${aws_instance.main.public_ip}:8080"
}

# ──────────────────────────────────────────────
# SSH Commands
# ──────────────────────────────────────────────
output "ssh_main" {
  description = "SSH command to connect to the main server"
  value       = "ssh -i batman.pem ubuntu@${aws_instance.main.public_ip}"
}

# ──────────────────────────────────────────────
# Admin UI URLs
# ──────────────────────────────────────────────
output "pgadmin_url" {
  description = "pgAdmin URL (login: admin@admin.com / admin)"
  value       = "http://${aws_instance.main.public_ip}:5050"
}

output "redis_commander_url" {
  description = "Redis Commander URL"
  value       = "http://${aws_instance.main.public_ip}:8081"
}

output "kibana_url" {
  description = "Kibana URL"
  value       = "http://${aws_instance.main.public_ip}:5601"
}

output "elasticvue_es_url" {
  description = "Elasticsearch URL for Elasticvue browser extension"
  value       = "http://${aws_instance.main.public_ip}:9200"
}
