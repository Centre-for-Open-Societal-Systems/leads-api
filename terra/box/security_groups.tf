# ──────────────────────────────────────────────
# Main Security Group
# ──────────────────────────────────────────────
resource "aws_security_group" "main" {
  name        = "${var.project_prefix}-main-sg"
  description = "Security group for the Verg consolidated server"
  vpc_id      = aws_vpc.verg.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # App API
  ingress {
    description = "App API"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # pgAdmin
  ingress {
    description = "pgAdmin"
    from_port   = 5050
    to_port     = 5050
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Redis Commander
  ingress {
    description = "Redis Commander"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Kibana
  ingress {
    description = "Kibana"
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Elasticsearch / Elasticvue
  ingress {
    description = "Elasticsearch"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-main-sg"
  }
}
