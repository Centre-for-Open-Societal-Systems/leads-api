# leads-api Helm chart

Deploys the Leads API Spring Boot app (image from ECR `eoan/leads-api/leads-api`), with an optional
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


## Telephony (lead capture by phone)

The chart bundles [Telephony-Service](https://github.com/A5HW1NRA7AN/Telephony-Service/tree/freeswitch-kubernetes)
(branch `freeswitch-kubernetes`, build 23) as the source subchart `charts/telephony`
(`telephony.enabled`, on by default; off in `values-prod.yaml`). One release installs both
in the same namespace (`leads`):

```
caller -> SIP trunk -> freeswitch (greeting) -> ESL -> event-publisher
       -> lead-service (lead_db PostgreSQL) -> POST /leads/v1/initiate on this release's API
```

| Resource | Values |
|----------|--------|
| FreeSWITCH Deployment (host network, greeting, ESL outbound socket) | `telephony.freeswitch` (`extIp`, `nodeSelector`) |
| event-publisher Deployment | `telephony.eventPublisher` |
| lead-service Deployment + Service :8080 | `telephony.leadService`, `telephony.leadRegistry` |
| lead_db PostgreSQL Deployment + PVC | `telephony.postgres` |
| Secret `leads-telephony-secrets` (`DB_USER`, `DB_PASSWORD`, `ESL_PASSWORD`, optional `LEAD_REGISTRY_API_KEY_VALUE`) | `telephony.secret` (`create: true` to let the chart own it) |

Telephony images live in ECR **ap-northeast-1** (`freeswitch-{lead-service,event-publisher,freeswitch}`,
pinned by digest). `leadRegistry.url` defaults to the API Service of this release; set
`telephony.leadRegistry.serviceName` if you use `nameOverride`/`fullnameOverride`.

## Namespace setup

Nothing is created by hand in the namespace except the credential Secrets (or set
`secrets.values` / `telephony.secret.create`):

- **Image pull.** `ecrPullSecret` (on by default) writes `leads-api-ecr` before the pods start
  (pre-install/pre-upgrade hook Job) and refreshes it every 8 hours (CronJob), using the node
  IAM role. It covers the API registry (host of `image.repository`), `ecrPullSecret.extraRegistries`
  and, with telephony enabled, `telephony.registry`.
- **Install** into `leads`:

```bash
helm dependency build ./helm/leads-api
helm upgrade --install leads-api ./helm/leads-api -n leads --create-namespace \
  -f my-secret-values.yaml
kubectl -n leads rollout status deploy/leads-api
kubectl -n leads rollout status deploy/leads-api-telephony-lead-service
```

## Keeping it on the latest image

Develop builds are published to `379220350808.dkr.ecr.ap-south-1.amazonaws.com/eoan/leads-api/leads-api`
with two tags: `<version>-develop.<build>` (immutable, e.g. `0.1.0-develop.12`) and `develop-latest` (moving),
the chart default. `values-prod.yaml` keeps prod on the legacy ECR `leads-a2c` (us-west-2, `prod-latest`).
`staging` builds go to `oan/leads-api` in ap-south-1 with a `staging-ati-` prefix and are
deployed by GitOps (oan-kustomize + ArgoCD); to point the chart there, set
`image.repository=<acct>.dkr.ecr.ap-south-1.amazonaws.com/oan/leads-api` and `image.tag=staging-ati-latest`.

The chart supports three ways to follow new builds (`autoUpdate.mode`):

| mode | how it works | needs |
|------|--------------|-------|
| `keel` (default) | Keel polls ECR every 2m; when the digest of `develop-latest` changes, it rolls the Deployment | Keel in the cluster (its pod needs ECR read access, e.g. the node role) |
| `cronjob` | in-chart CronJob runs `kubectl rollout restart` on a schedule; `pullPolicy: Always` pulls the newest image | nothing extra; restarts even when the image hasn't changed |
| `none` | CI deploys on push (below) | Jenkins access to the cluster |

Install Keel once:

```bash
helm repo add keel https://charts.keel.sh
helm upgrade --install keel keel/keel -n keel --create-namespace \
  --set helmProvider.enabled=false --set aws.region=ap-south-1
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
