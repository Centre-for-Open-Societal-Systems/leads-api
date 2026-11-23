#!/usr/bin/env bash
# =============================================================================
#  Pin the images for the leads namespace install by digest. Runs on the BUILD agent (it has
#  the AWS identity that pushed the image); the Helm install runs on the deploy agent, which
#  needs no AWS access. Called by the Jenkinsfile stage 'Resolve images (leads namespace)'.
#
#  Env in (set by the Jenkinsfile):
#    AWS_ACCOUNT_ID, AWS_REGION, ECR_REPO, IMMUTABLE_TAG  the leads-api image this build pushed
#    TELEPHONY           true|false: install the telephony subchart
#    TELEPHONY_TAG       optional ap-south-1 eoan/leads-api/* tag; empty = chart's pinned build
#  Out: the file named by $1, one Helm argument per line, for ci/deploy-leads-helm.sh.
# =============================================================================
set -euo pipefail

out="${1:?usage: resolve-leads-images.sh <args-file>}"
: "${AWS_ACCOUNT_ID:?}" "${AWS_REGION:?}" "${ECR_REPO:?}" "${IMMUTABLE_TAG:?}"
TELEPHONY="${TELEPHONY:-true}"
TELEPHONY_TAG="${TELEPHONY_TAG:-}"
TELEPHONY_REGION=ap-south-1
TELEPHONY_REPO_PREFIX=eoan/leads-api

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
echo "leads-api: ${ECR_REPO}:${IMMUTABLE_TAG}@${LEADS_DIGEST}"

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
    # The chart's pinned build must exist too, or the install would roll back.
    for image in lead-service event-publisher freeswitch; do
      tag=$(awk -v img="$TELEPHONY_REPO_PREFIX/$image" '
        $1=="repository:" && $2==img {f=1; next}
        f && $1=="tag:" {gsub(/"/,"",$2); print $2; exit}' helm/leads-api/charts/telephony/values.yaml)
      digest_of "$TELEPHONY_REGION" "$TELEPHONY_REPO_PREFIX/$image" "${tag:?no tag for $image}" >/dev/null
      echo "telephony ${image}: ${tag} (pinned in the chart)"
    done
  fi
else
  args+=(--set telephony.enabled=false)
fi

printf '%s\n' "${args[@]}" > "$out"
