apiVersion: v1
kind: Secret
metadata:
  name: leads-secrets
  namespace: default
type: Opaque
stringData:
  SPRING_DATASOURCE_USERNAME: "${db_username}"
  SPRING_DATASOURCE_PASSWORD: "${db_password}"
  ELASTICSEARCH_USERNAME: "${es_username}"
  ELASTICSEARCH_PASSWORD: "${es_password}"
  A2C_WEBHOOK_API_KEY: "${a2c_webhook_api_key}"
  A2C_WEBHOOK_API_SECRET: "${a2c_webhook_api_secret}"
