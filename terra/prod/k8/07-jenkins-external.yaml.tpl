# ==================================
# External Service — Jenkins EC2
# ==================================
# Allows K8s Ingress to route traffic to the Jenkins VM
# in the private subnet. Same pattern as leads-postgres.

apiVersion: v1
kind: Namespace
metadata:
  name: jenkins
---
apiVersion: v1
kind: Service
metadata:
  name: jenkins-external
  namespace: jenkins
spec:
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Endpoints
metadata:
  name: jenkins-external
  namespace: jenkins
subsets:
  - addresses:
      - ip: ${jenkins_private_ip}
    ports:
      - port: 8080
