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

## Image and rollouts

Following the OAN naming standard (oan-helm `docs/release/naming-standard.md`), there are no
moving tags and nothing in the chart updates itself:

- `image.tag` has **no default** and must be an immutable tag pinned by digest,
  `<version>-<branch>.<BUILD_NUMBER>@sha256:<digest>` (or set `image.digest`). Moving tags
  (`latest`, `*-latest`, `develop`, `staging`, ...) are rejected at render time.
- A new image reaches a cluster only through a reviewed change to that value and a Jenkins
  build running `helm upgrade`. There is no Keel and no restart CronJob, and `pullPolicy` is `IfNotPresent`.
- Repository: `oan/leads-api` (ap-south-1) today, e.g.
  `staging-ati-7@sha256:e3fba3f392b3add9f9c91ba87528878ff5b8f1c7a8b3e2298c5405a2c1db9121`.
  Switch to `eoan/leads-api/leads-api` once it exists in ECR.

## CI

`.github/workflows/helm-charts.yml` runs on every pull request to `dev` that touches `helm/` or
`apisix/`:
- `helm lint --strict` with `ci/default-values.yaml`, telephony on, and externalDb;
- `helm template` checks for telephony off and on;
- checks that the bare defaults and moving tags fail;
- the APISIX routes chart (exactly one public path).

## Probes

TCP only: the app has no Spring Boot Actuator. Once Actuator is added, switch to
`httpGet` on `/actuator/health/readiness` and `/actuator/health/liveness`.

## Databases

Point `config.SPRING_DATASOURCE_URL` and `config.ELASTICSEARCH_HOST` at the shared instances
by hostname. That follows DNS, so an RDS failover is picked up.

If the app should use in-namespace names instead, enable `externalDb`. It creates
`<release>-postgres` and `<release>-elasticsearch` (or `serviceName`) and fills the config from them:

- `host`: a DNS name, giving an `ExternalName` Service (use this for RDS or a shared instance);
- `ip`: a fixed private IP, giving a Service plus EndpointSlice (only for a host whose IP never changes).

## Redis

The in-chart Redis is a pure cache with no persistence: its data is lost on restart. To use a shared
Redis, set `redis.enabled=false` and `config.SPRING_REDIS_HOST`. The app reads
`SPRING_REDIS_PASSWORD`. When the chart-managed Secret has it, the in-chart Redis starts with
`--requirepass` automatically. With `secrets.existingSecret`, set `redis.auth.enabled=true`.
Without a password, any pod that can reach the Service can read the cache, so set one outside
throwaway environments.

## Secrets

With the chart-managed Secret (`secrets.values`), changing a value and running `helm upgrade`
rolls the pods. With `secrets.existingSecret`, Helm cannot see the Secret's contents, so the pods
are **not** restarted. Run `kubectl -n leads rollout restart deploy/leads-api` after changing it.

## ECR pull secret

`ecrPullSecret` (on by default) writes `leads-api-ecr` before the pods start (pre-install /
pre-upgrade hook Job) and refreshes it every 8 hours (CronJob), using the node IAM role. It
covers the API registry (host of `image.repository`), `ecrPullSecret.extraRegistries` and,
with telephony enabled, `telephony.registry`. Only the hook's Role may `create` Secrets (needed
once; Kubernetes cannot limit `create` by name), and Helm deletes the hook's ServiceAccount, Role
and RoleBinding when the hook succeeds. The CronJob's Role has only `get`, `update` and `patch`
on `leads-api-ecr`. If that Secret is deleted, the next `helm upgrade` recreates it.

## Telephony (lead capture by phone)

The chart bundles [Telephony-Service](https://github.com/A5HW1NRA7AN/Telephony-Service/tree/freeswitch-kubernetes)
(branch `freeswitch-kubernetes`, build 23) as the source subchart `charts/telephony`.
**It is off by default** (`telephony.enabled`). FreeSWITCH runs on the node's network and
answers SIP, so enable it deliberately. Its capabilities are:
- `SYS_NICE`, for real-time priority on media threads;
- `NET_ADMIN`, for socket priority and ToS on SIP and RTP.

`SYS_RAWIO` from the upstream chart is dropped.

```
caller -> SIP trunk -> freeswitch (greeting) -> ESL -> event-publisher
       -> lead-service (lead_db) -> POST /leads/v1/initiate on this release's API (in-cluster)
```

Required when enabled:

| Value | What |
|-------|------|
| `telephony.freeswitch.sipTrunkCidrs` | The SIP trunk's source CIDRs. FreeSWITCH's inbound ACL (`sip_trunk`, default deny) rejects every other caller |
| `telephony.freeswitch.nodeSelector` (required), `extIp` | The node the trunk points at, and its public IP. With host networking, ports 5060 udp/tcp must be free on that node |
| `telephony.leadService.dbUrl` | `lead_db` on the shared PostgreSQL, `jdbc:postgresql://<host>:5432/lead_db` |
| Secret `leads-telephony-secrets` | `DB_USER`, `DB_PASSWORD`, `ESL_PASSWORD` (optional `LEAD_REGISTRY_API_KEY_VALUE`); or `telephony.secret.create=true` with values |

`telephony.postgres.enabled=true` runs an in-chart single-replica `postgres:16-alpine` on a
10Gi PVC instead. The PVC is kept on uninstall and has no backup, so use it only for throwaway environments.

Telephony images live in ECR **ap-south-1** (`eoan/leads-api/{lead-service,event-publisher,freeswitch}:0.1.0-develop.<build>`,
pinned by digest). lead-service posts to this release's API Service; set
`telephony.leadRegistry.serviceName` if you use `nameOverride`/`fullnameOverride`.

```bash
kubectl -n leads rollout status deploy/leads-api-telephony-lead-service
```

## Configuration

Environment variables in `config` and `secrets.values` override `application.properties`
through Spring relaxed binding (`SPRING_DATASOURCE_URL` -> `spring.datasource.url`,
`ELASTICSEARCH_HOST` -> `elasticsearch.host`, `A2C_WEBHOOK_API_KEY` -> `a2c.webhook.api-key`).
