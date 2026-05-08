# Verg AWS Infrastructure Deployment

This directory contains Terraform scripts to deploy a consolidated, single-instance AWS infrastructure for the Verg application. 

It provisions a single EC2 instance within a custom VPC and uses an automated startup script (`user_data`) to set up a Docker Compose stack containing the Verg application and its required data stores.

## Architecture

*   **VPC**: A dedicated Virtual Private Cloud (`10.0.0.0/16` by default) with a public subnet and an Internet Gateway.
*   **Security Group**: Configured to allow inbound traffic for SSH, the application API, and various administrative interfaces.
*   **EC2 Instance**: A single `t3.xlarge` instance running the latest Ubuntu 22.04 LTS.
*   **IAM Role**: The instance is assigned the `EC2-ECR-Read-Role` profile to authenticate with Amazon ECR and pull the application's Docker image securely.

### Docker Compose Stack

The EC2 instance automatically starts the following services using Docker Compose:
*   **PostgreSQL 16**: Primary relational database.
*   **Redis 7**: In-memory data structure store for caching.
*   **Elasticsearch 8.13.0**: Search and analytics engine.
*   **Verg Application**: The core Spring Boot application, pulled directly from your Amazon ECR repository.
*   **pgAdmin**: Web-based administration tool for PostgreSQL.
*   **Redis Commander**: Web management tool for Redis.
*   **Kibana**: Data visualization dashboard for Elasticsearch.

## Prerequisites

1.  **Terraform**: Installed on your local machine.
2.  **AWS CLI**: Installed and configured with appropriate access credentials.
3.  **AWS Key Pair**: An existing EC2 Key Pair in your AWS account for SSH access.
4.  **Amazon ECR Repository**: A repository containing the built Verg application Docker image.
5.  **IAM Role**: An IAM role named `EC2-ECR-Read-Role` must exist in your AWS account with permissions to read from ECR (e.g., the `AmazonEC2ContainerRegistryReadOnly` managed policy).

## Usage

1.  **Initialize Terraform** to download the necessary providers and modules.
    ```bash
    terraform init
    ```

2.  **Configure Variables**:
    *   Copy the example variables file to create your own configuration:
        ```bash
        cp terraform.tfvars.example terraform.tfvars
        ```
    *   Open `terraform.tfvars` and fill in the required values:
        *   `key_name`: The name of your AWS Key Pair.
        *   `docker_image`: The full URI of your application's Docker image in ECR.
        *   Database and Elasticsearch credentials (`db_password`, `es_password`, etc.).

3.  **Review the Deployment Plan**:
    ```bash
    terraform plan
    ```

4.  **Apply the Infrastructure**:
    ```bash
    terraform apply
    ```
    *Type `yes` when prompted to confirm the deployment.*

## Outputs & Access

After a successful `terraform apply`, Terraform will display several useful outputs in the terminal:

*   **`main_public_ip`**: The public IP address of the newly created EC2 instance.
*   **`app_url`**: The URL to access the Verg application API (`http://<IP>:8080`).
*   **`ssh_main`**: The command to SSH into the instance (note: you may need to replace the placeholder `batman.pem` with your actual private key file name).

### Administrative Interfaces

The following admin interfaces are automatically exposed by the Docker Compose stack:

| Service | Port | URL | Default Login |
| :--- | :--- | :--- | :--- |
| **pgAdmin** | 5050 | `http://<IP>:5050` | `admin@admin.com` / `admin` |
| **Redis Commander** | 8081 | `http://<IP>:8081` | No authentication |
| **Kibana** | 5601 | `http://<IP>:5601` | No authentication |
| **Elasticsearch** | 9200 | `http://<IP>:9200` | No authentication (local dev config) |

> [!WARNING]
> This infrastructure is currently configured for development/testing purposes. Security groups are open to all IPs (`0.0.0.0/0`) and some services are running without strict authentication. Do not use this exact configuration for production environments without strictly limiting access via the `security_groups.tf` configuration.

## Cleanup

To tear down the infrastructure and avoid incurring further AWS charges, run:

```bash
terraform destroy
```
*Type `yes` when prompted to confirm the destruction.*
