# Leads API on APISIX

The Leads API is published through the shared OAN APISIX gateway (oan-helm
[docs/apisix-gateway.md](https://github.com/Centre-for-Open-Societal-Systems/oan-helm/blob/main/docs/apisix-gateway.md)),
like A2C and grievance. Kong is not used.

`apisix/k8s` is the `oan-leads-gateway` chart. It holds only APISIX Ingress Controller objects:

| Object | What |
|--------|------|
| `ApisixRoute leads-api-public` | **Only `POST /leads/v1/initiate`** on `hosts`. Rate limit 5 per 60 s per client IP (`limit-count`, counters in the gateway Redis, `allow_degradation: false`), body size limit, optional CORS |
| `ApisixUpstream leads-api` | Timeouts and retries for the leads-api Service |
| `ApisixTls oan-leads-tls` | Only with `tls.secretName` |

Nothing else is public: search, read, create, update, delete, qualify, process and Swagger
are reachable only inside the cluster (`http://leads-api.leads.svc.cluster.local`). The Leads
API has no inbound auth, so the rate limit is what protects `initiate`.

## Install

Jenkins installs it as release `leads-gateway` on every leads deploy (stage 'Deploy (Helm → leads
namespace)', `ci/deploy-leads-gateway.sh`, after the leads-api release), as a2c does with `a2c-gateway`.
By hand:

Install into the namespace of the leads-api release (`leads`), in the cluster that runs APISIX.
oan-helm's `gateway-common.yaml` sets `redis.host` (the gateway's Redis for the counters):

```sh
helm upgrade --install leads-gateway apisix/k8s -n leads \
  -f <oan-helm>/environments/dev/values/gateway-common.yaml \
  -f helm/environments/dev/oan-leads-gateway.yaml --atomic --wait

kubectl -n leads get apisixroute,apisixupstream
kubectl -n leads describe apisixroute leads-api-public | tail -20    # Accepted / Synced
```

## Test

```sh
kubectl -n api6-gateway port-forward svc/apisix-gateway 9080:80 &
H='Host: leads-api.development.oanstaging.com'
URL=http://localhost:9080/leads/v1/initiate

# 1. initiate reaches the API
curl -si -H "$H" -H 'Content-Type: application/json' -X POST --data @lead.json "$URL" | head -5

# 2. the 6th request within a minute gets 429
for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w '%{http_code}\n' -H "$H" -X POST "$URL"; done

# 3. nothing else is routed: 404 from APISIX
curl -si -H "$H" http://localhost:9080/swagger-ui/index.html | head -1
curl -si -H "$H" -X POST http://localhost:9080/leads/v1/search | head -1
```

Manage these routes with this chart only, never also with `adc sync`.
