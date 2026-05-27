#!/bin/bash
# ==================================
# Leads Consolidated Instance Bootstrap
# Runs: PostgreSQL, Redis, Elasticsearch, pgAdmin,
#       Redis Commander, Kibana, and the Leads Spring App
# ==================================

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================="
echo "Starting Leads Consolidated Instance Setup"
echo "========================================="

# ----------------------------------
# 1. System tuning for Elasticsearch
# ----------------------------------
echo "[STEP 1] Tuning system for Elasticsearch..."
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# ----------------------------------
# 2. Install Docker & AWS CLI
# ----------------------------------
echo "[STEP 2] Installing Docker and AWS CLI..."

echo "Waiting for NAT Gateway internet connectivity..."
until ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; do
  echo "Still waiting for internet..."
  sleep 5
done

echo "Internet reachable. Running apt-get update..."
n=0
until [ "$n" -ge 10 ]; do
  apt-get update -y && break
  n=$((n+1))
  echo "apt-get update failed. Retrying in 10 seconds... (attempt $n/10)"
  sleep 10
done

apt-get install -y docker.io unzip
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# ----------------------------------
# 3. Authenticate to ECR
# ----------------------------------
echo "[STEP 3] Authenticating to ECR..."
ECR_REGISTRY=$(echo "${docker_image}" | cut -d'/' -f1)

n=0
until [ "$n" -ge 5 ]; do
  aws ecr get-login-password --region ${aws_region} | \
    docker login --username AWS --password-stdin $ECR_REGISTRY && break
  n=$((n+1))
  echo "ECR login failed. Retrying in 5 seconds... (attempt $n/5)"
  sleep 5
done

mkdir -p /opt/${project_prefix}
cd /opt/${project_prefix}

# ==========================================
# 4. DATABASE CONTAINERS
# ==========================================

# ------------------------------------------
# 4a. PostgreSQL (port 5432)
# ------------------------------------------
echo "[DB 1/3] Setting up PostgreSQL..."
docker run -d \
  --name ${project_prefix}-postgres \
  --restart unless-stopped \
  -e POSTGRES_DB=${db_name} \
  -e POSTGRES_USER=${db_username} \
  -e POSTGRES_PASSWORD=${db_password} \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  postgres:16

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
  docker exec ${project_prefix}-postgres pg_isready -U ${db_username} -d ${db_name} && break
  echo "  Waiting... ($i/30)"
  sleep 2
done

# ------------------------------------------
# 4b. Redis (port 6379)
# ------------------------------------------
echo "[DB 2/3] Setting up Redis..."
docker run -d \
  --name ${project_prefix}-redis \
  --restart unless-stopped \
  -p 6379:6379 \
  -v redisdata:/data \
  redis:7-alpine \
  redis-server --appendonly yes

# ------------------------------------------
# 4c. Elasticsearch (port 9200)
# ------------------------------------------
echo "[DB 3/3] Setting up Elasticsearch..."
docker run -d \
  --name ${project_prefix}-elasticsearch \
  --restart unless-stopped \
  -e "discovery.type=single-node" \
  -e "xpack.security.enabled=false" \
  -e "ES_JAVA_OPTS=-Xms1g -Xmx1g" \
  -p 9200:9200 \
  -p 9300:9300 \
  -v esdata:/usr/share/elasticsearch/data \
  elasticsearch:8.13.0

echo "Waiting for Elasticsearch to be ready..."
for i in $(seq 1 30); do
  curl -sf http://localhost:9200/_cluster/health && break
  echo "  Waiting... ($i/30)"
  sleep 3
done

echo "All database containers started."

# ==========================================
# 5. ADMIN UI CONTAINERS
# ==========================================

# ------------------------------------------
# 5a. pgAdmin (port 5050)
# ------------------------------------------
echo "[ADMIN 1/3] Setting up pgAdmin..."
cat > /opt/${project_prefix}/servers.json <<'JSON_EOF'
{
  "Servers": {
    "1": {
      "Name": "${project_prefix} DB",
      "Group": "Servers",
      "Host": "${project_prefix}-postgres",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "${db_username}",
      "SSLMode": "prefer"
    }
  }
}
JSON_EOF

docker run -d \
  --name ${project_prefix}-pgadmin \
  --restart unless-stopped \
  -e PGADMIN_DEFAULT_EMAIL=admin@admin.com \
  -e PGADMIN_DEFAULT_PASSWORD=admin \
  -e PGADMIN_SERVER_JSON_FILE=/pgadmin4/servers.json \
  --link ${project_prefix}-postgres:postgres \
  -p 5050:80 \
  -v /opt/${project_prefix}/servers.json:/pgadmin4/servers.json \
  dpage/pgadmin4

# ------------------------------------------
# 5b. Redis Commander (port 8081)
# ------------------------------------------
echo "[ADMIN 2/3] Setting up Redis Commander..."
docker run -d \
  --name ${project_prefix}-redis-commander \
  --restart unless-stopped \
  -e REDIS_HOSTS=local:${project_prefix}-redis:6379 \
  --link ${project_prefix}-redis:redis \
  -p 8081:8081 \
  rediscommander/redis-commander:latest

# ------------------------------------------
# 5c. Kibana (port 5601)
# ------------------------------------------
echo "[ADMIN 3/3] Setting up Kibana..."
docker run -d \
  --name ${project_prefix}-kibana \
  --restart unless-stopped \
  -e ELASTICSEARCH_HOSTS=http://${project_prefix}-elasticsearch:9200 \
  --link ${project_prefix}-elasticsearch:elasticsearch \
  -p 5601:5601 \
  kibana:8.13.0

# ==========================================
# 6. LEADS SPRING BOOT APPLICATION (port 8080)
# ==========================================
echo "[STEP 6] Starting Leads Spring Boot application..."

docker pull "${docker_image}"

docker run -d \
  --name ${project_prefix}-app \
  --restart unless-stopped \
  --link ${project_prefix}-postgres:postgres \
  --link ${project_prefix}-redis:redis \
  --link ${project_prefix}-elasticsearch:elasticsearch \
  -e SPRING_DATASOURCE_URL="jdbc:postgresql://${project_prefix}-postgres:5432/${db_name}" \
  -e SPRING_DATASOURCE_USERNAME="${db_username}" \
  -e SPRING_DATASOURCE_PASSWORD="${db_password}" \
  -e SPRING_REDIS_HOST="${project_prefix}-redis" \
  -e SPRING_REDIS_PORT="6379" \
  -e ELASTICSEARCH_HOST="${project_prefix}-elasticsearch" \
  -e ELASTICSEARCH_PORT="9200" \
  -e ELASTICSEARCH_USERNAME="${es_username}" \
  -e ELASTICSEARCH_PASSWORD="${es_password}" \
  -e A2C_WEBHOOK_INITIATE_URL="${a2c_webhook_url}" \
  -e A2C_WEBHOOK_INITIATE_ENABLED="${a2c_webhook_enabled}" \
  -e A2C_WEBHOOK_API_KEY="${a2c_webhook_api_key}" \
  -e A2C_WEBHOOK_API_SECRET="${a2c_webhook_api_secret}" \
  -p 8080:8080 \
  "${docker_image}"

# ==========================================
# 7. KONG API GATEWAY (port 8000 / 8001)
# ==========================================
echo "[STEP 7] Setting up Kong API Gateway..."
cat > /opt/${project_prefix}/kong.yml <<'EOF'
_format_version: "3.0"
_transform: true

services:
  - name: leads-app-service
    url: http://leads-app:8080
    routes:
      - name: leads-app-initiate-route
        paths:
          - /leads/v1/initiate
        strip_path: false
        plugins:
          - name: rate-limiting
            config:
              minute: 5
              limit_by: ip
              policy: local
      - name: leads-app-default-route
        paths:
          - /leads
        strip_path: false
EOF

docker run -d \
  --name ${project_prefix}-kong \
  --restart unless-stopped \
  --link ${project_prefix}-app:leads-app \
  -p 8000:8000 \
  -p 8001:8001 \
  -v /opt/${project_prefix}/kong.yml:/etc/kong/kong.yml \
  -e "KONG_DATABASE=off" \
  -e "KONG_DECLARATIVE_CONFIG=/etc/kong/kong.yml" \
  -e "KONG_PROXY_LISTEN=0.0.0.0:8000" \
  -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" \
  kong:3.6-ubuntu

echo "========================================="
echo "Leads Consolidated Instance Setup Complete"
echo "All services are running on this instance"
echo "App API (Raw)   -> http://localhost:8080"
echo "Kong Gateway    -> http://localhost:8000"
echo "Kong Admin API  -> http://localhost:8001"
echo "pgAdmin         -> http://localhost:5050"
echo "Redis UI        -> http://localhost:8081"
echo "Kibana          -> http://localhost:5601"
echo "========================================="
