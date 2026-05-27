# ==================================
# Leads Spring Boot Application
# ==================================
# Deployment with 2 replicas + ClusterIP Service.
# Image URI is injected by Terraform templatefile().
# Configuration from ConfigMap (non-sensitive) and Secret (credentials).

apiVersion: apps/v1
kind: Deployment
metadata:
  name: leads-app
  namespace: default
  labels:
    app: leads-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: leads-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels:
        app: leads-app
    spec:
      containers:
        - name: leads-app
          image: ${docker_image}
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: leads-app-config
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: leads-secrets
                  key: SPRING_DATASOURCE_USERNAME
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: leads-secrets
                  key: SPRING_DATASOURCE_PASSWORD
            - name: ELASTICSEARCH_USERNAME
              valueFrom:
                secretKeyRef:
                  name: leads-secrets
                  key: ELASTICSEARCH_USERNAME
            - name: ELASTICSEARCH_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: leads-secrets
                  key: ELASTICSEARCH_PASSWORD
            - name: A2C_WEBHOOK_API_KEY
              valueFrom:
                secretKeyRef:
                  name: leads-secrets
                  key: A2C_WEBHOOK_API_KEY
            - name: A2C_WEBHOOK_API_SECRET
              valueFrom:
                secretKeyRef:
                  name: leads-secrets
                  key: A2C_WEBHOOK_API_SECRET
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "2Gi"
              cpu: "1000m"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 5
          livenessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 20
            failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: leads-app
  namespace: default
spec:
  selector:
    app: leads-app
  ports:
    - port: 80
      targetPort: 8080
  type: ClusterIP
