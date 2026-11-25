#!/usr/bin/env bash
# =============================================================================
#  Install or upgrade the leads APISIX routes (chart apisix/k8s, oan-leads-gateway) as release
#  `leads-gateway` in namespace `leads`, like a2c-gateway and grievance-gateway for their apps.
#  Called by the Jenkinsfile stage 'Deploy (Helm → leads namespace)' right after
#  ci/deploy-leads-helm.sh, on the same agent with the same kubeconfig.
#
#  The chart holds only ApisixRoute/ApisixUpstream objects; APISIX and its Ingress Controller are
#  the separate release in namespace GATEWAY_APISIX_NAMESPACE, which picks them up. Only
#  POST /leads/v1/initiate is published (apisix/README.md). Telephony (lead-service,
#  event-publisher) is in-cluster only and has no route here.
#  Manage these routes with this chart only, never also with `adc sync`.
#
#  Env in:  KUBECONFIG (credential oan-dev-kubeconfig, admin in leads)
#  Optional: GATEWAY_RELEASE, GATEWAY_APISIX_NAMESPACE, GATEWAY_VALUES, HELM
# =============================================================================
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required (credential oan-dev-kubeconfig)}"

NAMESPACE=leads
RELEASE="${GATEWAY_RELEASE:-leads-gateway}"
APISIX_NS="${GATEWAY_APISIX_NAMESPACE:-api6-gateway}"
CHART=apisix/k8s
VALUES="${GATEWAY_VALUES:-helm/environments/dev/oan-leads-gateway.yaml}"

# helm: as given, else the copy ci/deploy-leads-helm.sh downloaded, else the agent's.
if [ -z "${HELM:-}" ]; then
  if [ -x "${WORKSPACE:-$PWD}/.ci-bin/helm" ]; then HELM="${WORKSPACE:-$PWD}/.ci-bin/helm"; else HELM=helm; fi
fi

# The rate limiter's Redis ships with the APISIX release; find its Service by labels (as a2c's
# ci/deploy-gateway.sh does) rather than trusting a fixed name.
REDIS_SVC="$(kubectl -n "${APISIX_NS}" get svc \
  -l app.kubernetes.io/name=redis,app.kubernetes.io/component=master -o jsonpath='{.items[*].metadata.name}')"
case "${REDIS_SVC}" in
  ''|*' '*) echo "expected exactly one Redis master Service in ${APISIX_NS}, found: '${REDIS_SVC}'" >&2; exit 1 ;;
esac
REDIS_HOST="${REDIS_SVC}.${APISIX_NS}.svc.cluster.local"

echo "=== Gateway ${RELEASE}: namespace ${NAMESPACE}, APISIX in ${APISIX_NS}, redis ${REDIS_HOST} ==="

"$HELM" lint "${CHART}" -f "${VALUES}" --set redis.host="${REDIS_HOST}"

if ! "$HELM" upgrade --install "${RELEASE}" "${CHART}" --namespace "${NAMESPACE}" -f "${VALUES}" \
  --set redis.host="${REDIS_HOST}" --wait --timeout 5m; then
  echo "=== helm upgrade failed ==="
  "$HELM" -n "${NAMESPACE}" history "${RELEASE}" --max 3 || true
  exit 1
fi

"$HELM" -n "${NAMESPACE}" status "${RELEASE}"
kubectl -n "${NAMESPACE}" get apisixroute,apisixupstream
# The Ingress Controller reports whether it took the route.
kubectl -n "${NAMESPACE}" describe apisixroute leads-api-public | sed -n '/^Status:/,$p' || true

echo "=== gateway deploy complete: ${RELEASE} ==="
