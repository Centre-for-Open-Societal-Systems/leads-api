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
# EC2: Main Consolidated Server
# ──────────────────────────────────────────────
resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.main_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]
  iam_instance_profile = "EC2-ECR-Read-Role"

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Increase vm.max_map_count (required by Elasticsearch)
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf

    # Install Docker, Docker Compose, and AWS CLI
    apt-get update -y
    apt-get install -y docker.io docker-compose awscli
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    # Login to ECR
    ECR_REGISTRY=$(echo "${var.docker_image}" | cut -d'/' -f1)
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin $ECR_REGISTRY

    mkdir -p /opt/${var.project_prefix}
    cd /opt/${var.project_prefix}

    # Create servers.json for pgAdmin
    cat << 'JSON_EOF' > servers.json
    {
      "Servers": {
        "1": {
          "Name": "${var.project_prefix} DB",
          "Group": "Servers",
          "Host": "postgres",
          "Port": 5432,
          "MaintenanceDB": "postgres",
          "Username": "${var.db_username}",
          "SSLMode": "prefer"
        }
      }
    }
    JSON_EOF

    # Create docker-compose.yml
    cat << 'COMPOSE_EOF' > docker-compose.yml
    version: '3.8'

    services:
      postgres:
        image: postgres:16
        container_name: ${var.project_prefix}-postgres
        environment:
          POSTGRES_DB: ${var.db_name}
          POSTGRES_USER: ${var.db_username}
          POSTGRES_PASSWORD: ${var.db_password}
        ports:
          - "5432:5432"
        volumes:
          - pgdata:/var/lib/postgresql/data
        restart: always

      redis:
        image: redis:7-alpine
        container_name: ${var.project_prefix}-redis
        ports:
          - "6379:6379"
        volumes:
          - redisdata:/data
        restart: always

      elasticsearch:
        image: elasticsearch:8.13.0
        container_name: ${var.project_prefix}-elasticsearch
        environment:
          - discovery.type=single-node
          - xpack.security.enabled=false
          - ES_JAVA_OPTS=-Xms1g -Xmx1g
        ports:
          - "9200:9200"
          - "9300:9300"
        volumes:
          - esdata:/usr/share/elasticsearch/data
        restart: always

      pgadmin:
        image: dpage/pgadmin4
        container_name: ${var.project_prefix}-pgadmin
        environment:
          PGADMIN_DEFAULT_EMAIL: admin@admin.com
          PGADMIN_DEFAULT_PASSWORD: admin
          PGADMIN_SERVER_JSON_FILE: /pgadmin4/servers.json
        ports:
          - "5050:80"
        volumes:
          - ./servers.json:/pgadmin4/servers.json
        depends_on:
          - postgres
        restart: always

      redis-commander:
        image: rediscommander/redis-commander:latest
        container_name: ${var.project_prefix}-redis-commander
        environment:
          - REDIS_HOSTS=local:redis:6379
        ports:
          - "8081:8081"
        depends_on:
          - redis
        restart: always

      kibana:
        image: kibana:8.13.0
        container_name: ${var.project_prefix}-kibana
        environment:
          - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
        ports:
          - "5601:5601"
        depends_on:
          - elasticsearch
        restart: always

      app:
        image: ${var.docker_image}
        container_name: ${var.project_prefix}-app
        environment:
          SPRING_DATASOURCE_URL: jdbc:postgresql://${var.project_prefix}-postgres:5432/${var.db_name}
          SPRING_DATASOURCE_USERNAME: ${var.db_username}
          SPRING_DATASOURCE_PASSWORD: ${var.db_password}
          SPRING_REDIS_HOST: ${var.project_prefix}-redis
          SPRING_REDIS_PORT: 6379
          ELASTICSEARCH_HOST: ${var.project_prefix}-elasticsearch
          ELASTICSEARCH_PORT: 9200
          ELASTICSEARCH_USERNAME: ${var.es_username}
          ELASTICSEARCH_PASSWORD: ${var.es_password}
        ports:
          - "8080:8080"
        depends_on:
          - postgres
          - redis
          - elasticsearch
        restart: always

    volumes:
      pgdata:
      redisdata:
      esdata:
    COMPOSE_EOF

    # Start the stack
    docker-compose up -d
  EOF

  tags = {
    Name = "${var.project_prefix}-main"
  }
}
