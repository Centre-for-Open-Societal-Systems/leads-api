#!/usr/bin/env bash
# =============================================================================
#  Helm install of helm/leads-api (leads-api + telephony subchart) into namespace `leads`.
#  The namespace is fixed: telephony runs only in `leads`, in the same release as leads-api.
#  Runs on the DEPLOY agent (label oan-ci-deploy, the one that reaches the clusters), called by
#  the Jenkinsfile stage 'Deploy (Helm → leads namespace)'. Needs no AWS access: the images
#  were pinned by digest on the build agent (ci/resolve-leads-images.sh).
#
#  Args:  $1  file from ci/resolve-leads-images.sh (one Helm argument per line)
#  Env in (set by the Jenkinsfile):
#    KUBECONFIG          the oan_dev deployer kubeconfig (credential oan-dev-kubeconfig: jenkins-a2c-deployer,
#                        admin in leads via oan-helm environments/dev/values/oan-cluster-access.yaml)
#    LEADS_VALUES_FILE   optional: overrides layered over helm/environments/dev/leads-api.yaml
#                        (Jenkins credential LEADS_VALUES_CRED, e.g. the real Elasticsearch
#                        host/credentials or telephony; template helm/leads-api/ci/deploy-values.example.yaml).
#                        Unset: the Git dev values alone; the chart reads the PostgreSQL password
#                        from frappe-common/oan-frappe-common-db at install time.
#
#  --wait --atomic: the build fails (and the release rolls back) unless the pods become ready.
#  The namespace must exist (the deployer has no cluster-scoped rights): a cluster admin creates
#  it once (oan-helm PR 267), so there is no --create-namespace.
# =============================================================================
set -euo pipefail

args_file="${1:?usage: deploy-leads-helm.sh <args-file>}"
: "${KUBECONFIG:?}"
mapfile -t args < "$args_file"
[ "${#args[@]}" -gt 0 ] || { echo "empty $args_file" >&2; exit 1; }

NAMESPACE=leads                 # fixed, not a parameter
CHART=helm/leads-api
ENV_VALUES=helm/environments/dev/leads-api.yaml   # non-secret dev values, in Git
RELEASE=leads-api
HELM_VERSION=v3.16.4            # same as .github/workflows/helm-charts.yml

values=(-f "$ENV_VALUES")
[ -n "${LEADS_VALUES_FILE:-}" ] && values+=(-f "$LEADS_VALUES_FILE")

# --- helm: the agent's if present, else a pinned download verified by its sha256 ---
HELM=helm
if ! command -v helm >/dev/null 2>&1; then
  BIN_DIR="${WORKSPACE:-$PWD}/.ci-bin"
  HELM="$BIN_DIR/helm"
  if [ ! -x "$HELM" ]; then
    mkdir -p "$BIN_DIR"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    archive="helm-${HELM_VERSION}-linux-amd64.tar.gz"
    curl -fsSL "https://get.helm.sh/${archive}" -o "$tmp/$archive"
    curl -fsSL "https://get.helm.sh/${archive}.sha256sum" -o "$tmp/$archive.sha256sum"
    (cd "$tmp" && sha256sum -c "$archive.sha256sum")
    tar -xzf "$tmp/$archive" -C "$tmp"
    mv "$tmp/linux-amd64/helm" "$HELM"
  fi
fi
"$HELM" version --short

"$HELM" dependency build "$CHART"
"$HELM" upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  "${values[@]}" "${args[@]}" \
  --wait --atomic --timeout 10m --history-max 10

"$HELM" status "$RELEASE" --namespace "$NAMESPACE"
