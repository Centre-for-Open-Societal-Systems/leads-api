# ==================================
# Leads App ConfigMap
# ==================================
# Non-sensitive configuration for the Spring Boot application.
# DB and ES hostnames point to ExternalName services that
# resolve to the private DB EC2 at ${db_private_ip}.

apiVersion: v1
kind: ConfigMap
metadata:
  name: leads-app-config
  namespace: default
data:
  # PostgreSQL — via ExternalName service "leads-postgres"
  SPRING_DATASOURCE_URL: "jdbc:postgresql://leads-postgres:5432/${db_name}"

  # Redis — in-cluster pod
  SPRING_REDIS_HOST: "redis"
  SPRING_REDIS_PORT: "6379"

  # Elasticsearch — via ExternalName service "leads-elasticsearch"
  ELASTICSEARCH_HOST: "leads-elasticsearch"
  ELASTICSEARCH_PORT: "9200"

  # Webhook Settings
  A2C_WEBHOOK_INITIATE_URL: "${a2c_webhook_url}"
  A2C_WEBHOOK_INITIATE_ENABLED: "${a2c_webhook_enabled}"
