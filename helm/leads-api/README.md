# leads-api Helm chart

Deploys the Leads API Spring Boot app (image from ECR `leads-a2c`), with an optional
in-cluster Redis, an external Postgres/Elasticsearch bridge, Kong routes with rate
limiting, and automatic updates to the latest image.

## Install

```bash
# dev (creates the secret from values)
helm upgrade --install leads-api ./helm/leads-api -n leads --create-namespace \
  --set secrets.values.SPRING_DATASOURCE_USERNAME=leads_user \
  --set secrets.values.SPRING_DATASOURCE_PASSWORD=*** \
  --set secrets.values.ELASTICSEARCH_USERNAME=elastic \
  --set secrets.values.ELASTICSEARCH_PASSWORD=***

# prod (uses an existing `leads-secrets` Secret, external DB EC2, Kong)
helm upgrade --install leads-api ./helm/leads-api -n default \
  -f helm/leads-api/values-prod.yaml --set externalDb.ip=<db-private-ip>
```

## Keeping it on the latest image

Jenkins pushes two tags per build: `<env>-latest` (moving) and `<env>-<BUILD_NUMBER>` (immutable).
`dev`/`main` builds go to the legacy ECR `leads-a2c` (us-west-2), which is the chart default.
`staging` builds go to `oan/leads-api` in ap-south-1 with a `staging-ati-` prefix and are
deployed by GitOps (oan-kustomize + ArgoCD); to point the chart there, set
`image.repository=<acct>.dkr.ecr.ap-south-1.amazonaws.com/oan/leads-api` and `image.tag=staging-ati-latest`.

The chart supports three ways to follow new builds (`autoUpdate.mode`):

| mode | how it works | needs |
|------|--------------|-------|
| `keel` (default) | Keel polls ECR every 2m; when the digest of `dev-latest` changes, it rolls the Deployment | Keel in the cluster (its pod needs ECR read access, e.g. the node role) |
| `cronjob` | in-chart CronJob runs `kubectl rollout restart` on a schedule; `pullPolicy: Always` pulls the newest image | nothing extra; restarts even when the image hasn't changed |
| `none` | CI deploys on push (below) | Jenkins access to the cluster |

Install Keel once:

```bash
helm repo add keel https://charts.keel.sh
helm upgrade --install keel keel/keel -n keel --create-namespace \
  --set helmProvider.enabled=false --set aws.region=us-west-2
```

### Push-based option (most traceable)

Add this stage after the legacy `Build & Push` stage in the `Jenkinsfile` to pin each release
to its immutable tag:

```groovy
stage('Deploy (Helm)') {
    steps {
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
            sh """
                aws eks update-kubeconfig --region ${AWS_REGION} --name <cluster-name>
                helm upgrade --install leads-api ./helm/leads-api -n default \
                  -f helm/leads-api/values-prod.yaml \
                  --set image.tag=${IMMUTABLE_TAG} --set autoUpdate.mode=none \
                  --wait --timeout 10m
            """
        }
    }
}
```

## Configuration

Environment variables in `config` and `secrets.values` override `application.properties`
through Spring relaxed binding (`SPRING_DATASOURCE_URL` -> `spring.datasource.url`,
`ELASTICSEARCH_HOST` -> `elasticsearch.host`, `A2C_WEBHOOK_API_KEY` -> `a2c.webhook.api-key`).
Changing a config or secret value and running `helm upgrade` rolls the pods automatically.

### Redis password

The app reads `SPRING_REDIS_PASSWORD` (`spring.redis.password`, empty = no AUTH). Put it in the
Secret (`secrets.values.SPRING_REDIS_PASSWORD` or a key in `secrets.existingSecret`) and set
`redis.auth.enabled=true` so the in-chart Redis starts with `--requirepass` from the same key.
