# leads AWS Infrastructure Deployment

This directory contains Terraform scripts to deploy a secure, consolidated, three-tier AWS infrastructure for the leads application. 

It isolates the database and application services inside a **Private Subnet**, while routing public traffic securely through an **Nginx Reverse Proxy** and administrative shell access via a **Bastion Host** located in the **Public Subnet**.

---

## Architecture

*   **VPC**: A dedicated Virtual Private Cloud (`10.0.0.0/16` by default) with isolated public and private subnets.
*   **Public Subnet (`10.0.1.0/24`)**:
    *   **Nginx Reverse Proxy** (`t2.micro`): Attached to an Elastic IP. Serves as the single public gateway, directing API requests (`/leads/`) to the internal Kong proxy and blocking all direct database/admin UI access from the public internet.
    *   **Bastion Host** (`t2.micro`): Provides a secure entry point for administrators to access the private backend via SSH and port-forwarding.
    *   **NAT Gateway**: Allows services in the private subnet to securely pull external dependencies and ECR images without exposing themselves to the public internet.
*   **Private Subnet (`10.0.2.0/24`)**:
    *   **Main Consolidated Server** (`t3.xlarge`): A single instance with a static private IP (`10.0.2.10`) that runs all core application services, data stores, and the Kong gateway via Docker.
*   **IAM Profile**: The main instance uses the `EC2-ECR-Read-Role` profile to authenticate with Amazon ECR and pull application Docker images securely.

### Service Stack

The private backend instance automatically runs the following containerized services:
*   **Kong API Gateway 3.6 (Open Source)**: Running in lightweight DB-less (declarative) mode. Proxies API requests, secures backend microservices, and enforces rate-limiting.
*   **PostgreSQL 16**: Primary database.
*   **Redis 7**: Caching and session layer.
*   **Elasticsearch 8.13.0**: Search and indexing engine.
*   **leads Application**: Core Spring Boot application.
*   **pgAdmin**: Database management UI (private, accessible via SSH tunnel).
*   **Redis Commander**: Redis key/value management UI (private, accessible via SSH tunnel).
*   **Kibana**: Elasticsearch analytics dashboard (private, accessible via SSH tunnel).

---

## Prerequisites

1.  **Terraform**: Installed on your local machine.
2.  **AWS CLI**: Installed and configured with appropriate access credentials.
3.  **AWS Key Name**: Provide a name for the key pair to be generated (`key_name` variable).
4.  **Amazon ECR Repository**: A repository containing the built leads application Docker image.
5.  **IAM Role**: An IAM role named `EC2-ECR-Read-Role` must exist in your AWS account with ECR read permissions.

---

## Usage

1.  **Initialize Terraform** and fetch updates:
    ```bash
    terraform init -upgrade
    ```

2.  **Configure Variables**:
    *   Copy the example variables file:
        ```bash
        cp terraform.tfvars.example terraform.tfvars
        ```
    *   Open `terraform.tfvars` and fill in:
        *   `key_name`: The name to assign to your generated key pair.
        *   `docker_image`: The full ECR URI of your Leads application image.
        *   Database and Elasticsearch passwords.

3.  **Review the Deployment Plan**:
    ```bash
    terraform plan
    ```

4.  **Apply the Infrastructure**:
    ```bash
    terraform apply
    ```
    *Type `yes` when prompted to confirm.*

---

## Post-Deployment & Access Guide

After a successful deployment, Terraform will output the public IPs for Nginx and the Bastion host, as well as pre-built commands.

### 1. Hitting the Leads API
The application is hosted securely in the private subnet and exposed to the public internet solely through the Nginx reverse proxy on port 80:

*   **API Endpoint**: `http://<nginx_public_ip>/leads/`
*   **Example (cURL)**:
    ```bash
    curl http://<nginx_public_ip>/leads/v1/search
    ```

### 2. Testing Kong's Rate Limiting
To test if Kong is successfully proxying traffic and enforcing the production-equivalent rate-limiting policy (5 requests per minute, per IP, on the `/leads/v1/initiate` endpoint):

1. **Successful Request**:
   Run a `GET` request to the protected endpoint:
   ```bash
   curl -i http://<nginx_public_ip>/leads/v1/initiate
   ```
   You should see these HTTP response headers returned by the Kong Gateway:
   * `RateLimit-Limit: 5`
   * `RateLimit-Remaining: 4`
   * `RateLimit-Reset: 58`

2. **Triggering Rate Limiting**:
   Perform 6 rapid requests in under a minute. The 6th request will be blocked at the gateway and return an `HTTP/1.1 429 Too Many Requests` status code with the payload:
   ```json
   {
     "message": "API rate limit exceeded"
   }
   ```

---

### 3. Secure Administration via SSH Tunneling (Required)
For security hardening, all web administrative tools and raw databases are strictly isolated inside the private subnet. They are not exposed to Nginx and cannot be reached via the public internet.

To access them, you can establish a secure, encrypted **SSH Tunnel** through the Bastion host to your local machine.

#### The One-Command Multi-Tunnel (Recommended)
You can tunnel **all five administrative tools** to your localhost with a single, unified terminal command:
```bash
ssh -i leads-key.pem -J ubuntu@<bastion_public_ip> ubuntu@10.0.2.10 \
  -L 5050:localhost:5050 \
  -L 8081:localhost:8081 \
  -L 5601:localhost:5601 \
  -L 9200:localhost:9200 \
  -L 8001:localhost:8001 -N
```
Keep this terminal command running. You can now access all UIs and ports locally on your machine:

| Tool / Service | Local URL / Access | Default Credentials / Context |
| :--- | :--- | :--- |
| **pgAdmin** | [http://localhost:5050](http://localhost:5050) | `admin@admin.com` / `admin` |
| **Redis Commander** | [http://localhost:8081](http://localhost:8081) | No authentication |
| **Kibana** | [http://localhost:5601](http://localhost:5601) | No authentication |
| **Elasticsearch** | [http://localhost:9200](http://localhost:9200) | Direct URL for **Elasticvue** extension |
| **Kong Admin API** | [http://localhost:8001](http://localhost:8001) | REST API endpoint for managing Kong config |

---

## Direct Console SSH Access

To access the console of the Bastion host or the private backend server directly:

*   **Bastion Console**:
    ```bash
    ssh -i leads-key.pem ubuntu@<bastion_public_ip>
    ```
*   **Private Backend Console** (Proxied via Bastion):
    ```bash
    ssh -i leads-key.pem -J ubuntu@<bastion_public_ip> ubuntu@10.0.2.10
    ```

---

## Cleanup

To tear down the infrastructure and stop incurring AWS charges:
```bash
terraform destroy
```
*Type `yes` when prompted to confirm.*
