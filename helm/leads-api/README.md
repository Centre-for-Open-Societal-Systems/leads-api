# leads-api Helm chart

Deploys the Leads API Spring Boot app, an optional in-cluster Redis cache, an optional bridge
to databases outside the cluster, an ECR pull secret the release keeps fresh, and (off by
default) the Telephony lead capture. One release, namespace `leads`.

The public route is **not** in this chart: it is the APISIX routes chart `apisix/k8s`
(`oan-leads-gateway`, see [apisix/README.md](../../apisix/README.md)), which exposes only
`POST /leads/v1/initiate`, rate-limited to 5 per minute per client IP. There is no Kong or
nginx Ingress here; the API Service is ClusterIP only.

Production is not covered by this chart yet. Prod still runs from `terra/prod/k8`
(`leads-app`, Kong, the `leads-postgres`/`leads-elasticsearch` Services in `default`); moving
it needs its own migration plan.

## Install (dev)

The install stops with an error naming the missing value if any of these are not set:

| Value | What |
|-------|------|
| `config.SPRING_DATASOURCE_URL` | The shared PostgreSQL by hostname, `jdbc:postgresql://<host>:5432/leads_db` |
| `config.ELASTICSEARCH_HOST` | The Elasticsearch hostname |
| `secrets.values.SPRING_DATASOURCE_USERNAME` / `_PASSWORD`, `ELASTICSEARCH_USERNAME` / `_PASSWORD` | Or `secrets.existingSecret` |
| `A2C_WEBHOOK_API_KEY` / `_SECRET` | Only with `A2C_WEBHOOK_INITIATE_ENABLED=true` |
| `config.SPRING_REDIS_HOST` | Only with `redis.enabled=false` (shared Redis) |

```bash
helm dependency build ./helm/leads-api
helm upgrade --install leads-api ./helm/leads-api -n leads --create-namespace \
  -f my-env-values.yaml -f my-secret-values.yaml     # secret values never from Git
kubectl -n leads rollout status deploy/leads-api
```

Then install the APISIX route (`apisix/README.md`).

## Image

Default: `379220350808.dkr.ecr.ap-south-1.amazonaws.com/oan/leads-api:staging-ati-latest`,
the moving alias pushed by the staging Jenkins build (`staging-ati-<build>` is immutable).
`eoan/leads-api/leads-api` does not exist in ECR yet; switch `image.repository` and
`image.tag` (`develop-latest`) once it does.

## Keeping it on the latest image (dev/staging)

`autoUpdate.mode`:

| mode | how it works | needs |
|------|--------------|-------|
| `keel` (default) | Keel polls ECR every 2m; when the digest of the floating tag changes, it rolls the Deployment (`approvals: 0`) | Keel in the cluster (its pod needs ECR read access, e.g. the node role) |
| `cronjob` | in-chart CronJob runs `kubectl rollout restart` on a schedule; `pullPolicy: Always` pulls the newest image | nothing extra; restarts even when the image hasn't changed |
| `none` | CI deploys a pinned tag with `helm upgrade --set image.tag=...` | the only mode for production |

## Databases

Point `config.SPRING_DATASOURCE_URL` and `config.ELASTICSEARCH_HOST` at the shared instances
by hostname. That follows DNS, so an RDS failover is picked up.

If the app should use in-namespace names instead, enable `externalDb`. It creates
`<release>-postgres` and `<release>-elasticsearch` (or `serviceName`) and fills the config from them:

- `host`: a DNS name, giving an `ExternalName` Service (use this for RDS or a shared instance);
- `ip`: a fixed private IP, giving a Service plus Endpoints (only for a host whose IP never changes).

## Redis

The in-chart Redis is a pure cache with no persistence: its data is lost on restart. To use a shared
Redis, set `redis.enabled=false` and `config.SPRING_REDIS_HOST`. The app reads
`SPRING_REDIS_PASSWORD`; with `redis.auth.enabled=true` the in-chart Redis starts with
`--requirepass` from the same Secret key.

## Secrets

With the chart-managed Secret (`secrets.values`), changing a value and running `helm upgrade`
rolls the pods. With `secrets.existingSecret`, Helm cannot see the Secret's contents, so the pods
are **not** restarted. Run `kubectl -n leads rollout restart deploy/leads-api` after changing it.

## ECR pull secret

`ecrPullSecret` (on by default) writes `leads-api-ecr` before the pods start (pre-install /
pre-upgrade hook Job) and refreshes it every 8 hours (CronJob), using the node IAM role. It
covers the API registry (host of `image.repository`), `ecrPullSecret.extraRegistries` and,
with telephony enabled, `telephony.registry`. Its Role may `create` any Secret in the
namespace, because Kubernetes cannot limit `create` by name. `get`, `update` and `patch` are limited to
`leads-api-ecr`.

## Telephony (lead capture by phone)

The chart bundles [Telephony-Service](https://github.com/A5HW1NRA7AN/Telephony-Service/tree/freeswitch-kubernetes)
(branch `freeswitch-kubernetes`, build 23) as the source subchart `charts/telephony`.
**It is off by default** (`telephony.enabled`). FreeSWITCH runs on the node's network with
`NET_ADMIN`, `SYS_NICE` and `SYS_RAWIO` and answers SIP, so enable it deliberately:

```
caller -> SIP trunk -> freeswitch (greeting) -> ESL -> event-publisher
       -> lead-service (lead_db) -> POST /leads/v1/initiate on this release's API (in-cluster)
```

Required when enabled:

| Value | What |
|-------|------|
| `telephony.freeswitch.sipTrunkCidrs` | The SIP trunk's source CIDRs. FreeSWITCH's inbound ACL (`sip_trunk`, default deny) rejects every other caller |
| `telephony.freeswitch.nodeSelector`, `extIp` | The node the trunk points at, and its public IP |
| `telephony.leadService.dbUrl` | `lead_db` on the shared PostgreSQL, `jdbc:postgresql://<host>:5432/lead_db` |
| Secret `leads-telephony-secrets` | `DB_USER`, `DB_PASSWORD`, `ESL_PASSWORD` (optional `LEAD_REGISTRY_API_KEY_VALUE`); or `telephony.secret.create=true` with values |

`telephony.postgres.enabled=true` runs an in-chart single-replica `postgres:16-alpine` on a
10Gi PVC instead. The PVC is kept on uninstall and has no backup, so use it only for throwaway environments.

Telephony images live in ECR **ap-northeast-1** (`freeswitch-{lead-service,event-publisher,freeswitch}`,
pinned by digest). lead-service posts to this release's API Service; set
`telephony.leadRegistry.serviceName` if you use `nameOverride`/`fullnameOverride`.

```bash
kubectl -n leads rollout status deploy/leads-api-telephony-lead-service
```

## Configuration

Environment variables in `config` and `secrets.values` override `application.properties`
through Spring relaxed binding (`SPRING_DATASOURCE_URL` -> `spring.datasource.url`,
`ELASTICSEARCH_HOST` -> `elasticsearch.host`, `A2C_WEBHOOK_API_KEY` -> `a2c.webhook.api-key`).
