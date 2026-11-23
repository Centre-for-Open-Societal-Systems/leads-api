#!/usr/bin/env bash
# =============================================================================
#  Helm install of helm/leads-api (leads-api + telephony subchart) into one namespace.
#  Called by the Jenkinsfile stage 'Deploy (Helm → leads namespace)' (DEPLOY_LEADS_NS).
#
#  Env in (set by the Jenkinsfile):
#    AWS_ACCOUNT_ID, AWS_REGION, ECR_REPO, IMMUTABLE_TAG  the leads-api image this build pushed
#    KUBECONFIG          kubeconfig of the target cluster (secret file)
#    LEADS_VALUES_FILE   environment values incl. secrets (secret file; see
#                        helm/leads-api/ci/deploy-values.example.yaml)
#    LEADS_NAMESPACE     target namespace (default leads)
#    TELEPHONY           true|false: install the telephony subchart
#    TELEPHONY_TAG       optional ap-south-1 eoan/leads-api/* tag; empty = chart's pinned build
#
#  Every image is pinned by digest, looked up in ECR. --wait --atomic: the build fails
#  (and the release rolls back) unless the pods become ready.
# =============================================================================
set -euo pipefail

: "${AWS_ACCOUNT_ID:?}" "${AWS_REGION:?}" "${ECR_REPO:?}" "${IMMUTABLE_TAG:?}"
: "${KUBECONFIG:?}" "${LEADS_VALUES_FILE:?}"
LEADS_NAMESPACE="${LEADS_NAMESPACE:-leads}"
TELEPHONY="${TELEPHONY:-true}"
TELEPHONY_TAG="${TELEPHONY_TAG:-}"

CHART=helm/leads-api
RELEASE=leads-api
HELM_VERSION=v3.16.4            # same as .github/workflows/helm-charts.yml
TELEPHONY_REGION=ap-south-1
TELEPHONY_REPO_PREFIX=eoan/leads-api

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

digest_of() { # <region> <repository> <tag>
  local d
  d=$(aws ecr describe-images --region "$1" --repository-name "$2" \
        --image-ids imageTag="$3" --query 'imageDetails[0].imageDigest' --output text)
  [[ "$d" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "no image $2:$3 in $1" >&2; exit 1; }
  echo "$d"
}

REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
LEADS_DIGEST=$(digest_of "$AWS_REGION" "$ECR_REPO" "$IMMUTABLE_TAG")
args=(
  --set-string "image.repository=${REGISTRY}/${ECR_REPO}"
  --set-string "image.tag=${IMMUTABLE_TAG}"
  --set-string "image.digest=${LEADS_DIGEST}"
)
echo "leads-api: ${REGISTRY}/${ECR_REPO}:${IMMUTABLE_TAG}@${LEADS_DIGEST}"

if [ "$TELEPHONY" = "true" ]; then
  args+=(--set telephony.enabled=true)
  if [ -n "$TELEPHONY_TAG" ]; then
    for pair in leadService:lead-service eventPublisher:event-publisher freeswitch:freeswitch; do
      key=${pair%%:*}; image=${pair#*:}
      d=$(digest_of "$TELEPHONY_REGION" "$TELEPHONY_REPO_PREFIX/$image" "$TELEPHONY_TAG")
      args+=(--set-string "telephony.${key}.image.tag=${TELEPHONY_TAG}"
             --set-string "telephony.${key}.image.digest=${d}")
      echo "telephony ${image}: ${TELEPHONY_TAG}@${d}"
    done
  else
    echo "telephony: the build pinned in the chart"
  fi
else
  args+=(--set telephony.enabled=false)
fi

"$HELM" dependency build "$CHART"
"$HELM" upgrade --install "$RELEASE" "$CHART" \
  --namespace "$LEADS_NAMESPACE" --create-namespace \
  -f "$LEADS_VALUES_FILE" "${args[@]}" \
  --wait --atomic --timeout 10m --history-max 10

"$HELM" status "$RELEASE" --namespace "$LEADS_NAMESPACE"
