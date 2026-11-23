#!/usr/bin/env bash
# =============================================================================
#  Pin the images for the leads namespace install by digest, making sure each one exists first.
#  Runs on the BUILD agent (docker + buildx + aws); the Helm install runs on the deploy agent,
#  which needs no AWS access. Called by the Jenkinsfile stage 'Resolve images (leads namespace)'.
#
#  leads-api:  the image this build just pushed (oan/leads-api:<IMMUTABLE_TAG>).
#  telephony:  ap-south-1 eoan/leads-api/{lead-service,event-publisher,freeswitch}:<tag>, where
#              <tag> is TELEPHONY_TAG or, when empty, the build pinned in the chart. If an image
#              is missing there, it is copied from the Telephony-Service push in ap-northeast-1
#              (freeswitch-<image>:<build>) with `docker buildx imagetools create`, which keeps the
#              digest; the ap-south-1 repository is created on first use with the eoan settings.
#
#  Env in (set by the Jenkinsfile):
#    AWS_ACCOUNT_ID, AWS_REGION, ECR_REPO, IMMUTABLE_TAG  the leads-api image this build pushed
#    TELEPHONY           true|false: install the telephony subchart
#    TELEPHONY_TAG       optional, e.g. 0.1.0-develop.24; empty = the build pinned in the chart
#    TEL_AWS_ACCESS_KEY_ID / TEL_AWS_SECRET_ACCESS_KEY
#                        the Telephony-Service identity (aws-credentials), used only for the
#                        telephony images; the leads-api lookup uses the agent's own identity
#  Out: the file named by $1, one Helm argument per line, for ci/deploy-leads-helm.sh.
# =============================================================================
set -euo pipefail
shopt -s inherit_errexit   # stop at the first failure inside $(...) too

out="${1:?usage: resolve-leads-images.sh <args-file>}"
: "${AWS_ACCOUNT_ID:?}" "${AWS_REGION:?}" "${ECR_REPO:?}" "${IMMUTABLE_TAG:?}"
TELEPHONY="${TELEPHONY:-true}"
TELEPHONY_TAG="${TELEPHONY_TAG:-}"

TEL_REGION=ap-south-1                      # where the chart pulls telephony from
TEL_PREFIX=eoan/leads-api
SRC_REGION=ap-northeast-1                  # where Telephony-Service pushes every build
SRC_PREFIX=freeswitch-                     # freeswitch-<image>:<BUILD_NUMBER>
CHART_TEL_VALUES=helm/leads-api/charts/telephony/values.yaml

digest_of() { # <region> <repository> <tag>  -> digest; empty if missing; fails on any other error
  local res
  if res=$(aws ecr describe-images --region "$1" --repository-name "$2" --image-ids imageTag="$3" \
             --query 'imageDetails[0].imageDigest' --output text 2>&1); then
    [[ "$res" =~ ^sha256:[a-f0-9]{64}$ ]] && echo "$res"
    return 0
  fi
  case "$res" in *ImageNotFoundException*|*RepositoryNotFoundException*) return 0 ;; esac
  echo "aws ecr describe-images $2:$3 in $1 failed: $res" >&2
  return 1
}

# --- leads-api: pushed by this build ---
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
LEADS_DIGEST=$(digest_of "$AWS_REGION" "$ECR_REPO" "$IMMUTABLE_TAG")
[ -n "$LEADS_DIGEST" ] || { echo "no image ${ECR_REPO}:${IMMUTABLE_TAG} in ${AWS_REGION}" >&2; exit 1; }
args=(
  --set-string "image.repository=${REGISTRY}/${ECR_REPO}"
  --set-string "image.tag=${IMMUTABLE_TAG}"
  --set-string "image.digest=${LEADS_DIGEST}"
)
echo "leads-api: ${ECR_REPO}:${IMMUTABLE_TAG}@${LEADS_DIGEST}"

if [ "$TELEPHONY" != "true" ]; then
  args+=(--set telephony.enabled=false)
  printf '%s\n' "${args[@]}" > "$out"
  exit 0
fi

# --- telephony: everything below runs as the Telephony-Service identity ---
: "${TEL_AWS_ACCESS_KEY_ID:?}" "${TEL_AWS_SECRET_ACCESS_KEY:?}"
export AWS_ACCESS_KEY_ID="$TEL_AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$TEL_AWS_SECRET_ACCESS_KEY"
unset AWS_SESSION_TOKEN

chart_tag() { # <image> -> the tag pinned in the chart
  awk -v img="$TEL_PREFIX/$1" '
    $1=="repository:" && $2==img {f=1; next}
    f && $1=="tag:" {gsub(/"/,"",$2); print $2; exit}' "$CHART_TEL_VALUES"
}

DST_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${TEL_REGION}.amazonaws.com"
SRC_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${SRC_REGION}.amazonaws.com"
logged_in=""
login() {
  [ -n "$logged_in" ] && return 0
  aws ecr get-login-password --region "$TEL_REGION" | docker login -u AWS --password-stdin "$DST_REGISTRY" >/dev/null
  aws ecr get-login-password --region "$SRC_REGION" | docker login -u AWS --password-stdin "$SRC_REGISTRY" >/dev/null
  logged_in=1
}

ensure_telephony() { # <image> <tag>  -> digest in ap-south-1 (copied from ap-northeast-1 if missing)
  local image=$1 tag=$2 repo="$TEL_PREFIX/$1" d build src
  d=$(digest_of "$TEL_REGION" "$repo" "$tag")
  if [ -n "$d" ]; then echo "$d"; return 0; fi

  build=${tag##*.}                                   # 0.1.0-develop.23 -> 23
  [[ "$build" =~ ^[0-9]+$ ]] || { echo "cannot derive a build number from tag $tag" >&2; return 1; }
  src="${SRC_PREFIX}${image}"
  [ -n "$(digest_of "$SRC_REGION" "$src" "$build")" ] \
    || { echo "missing everywhere: $repo:$tag in $TEL_REGION and $src:$build in $SRC_REGION" >&2; return 1; }

  echo "copying $SRC_REGION $src:$build -> $TEL_REGION $repo:$tag" >&2
  aws ecr describe-repositories --region "$TEL_REGION" --repository-names "$repo" >/dev/null 2>&1 \
    || aws ecr create-repository --region "$TEL_REGION" --repository-name "$repo" \
         --image-tag-mutability IMMUTABLE \
         --image-scanning-configuration scanOnPush=true \
         --encryption-configuration encryptionType=AES256 \
         --tags Key=owner,Value=leads-api Key=naming,Value=eoan-standard >/dev/null
  login
  docker buildx imagetools create --tag "$DST_REGISTRY/$repo:$tag" "$SRC_REGISTRY/$src:$build" >&2
  d=$(digest_of "$TEL_REGION" "$repo" "$tag")
  [ -n "$d" ] || { echo "copy of $repo:$tag did not land in $TEL_REGION" >&2; return 1; }
  echo "$d"
}

args+=(--set telephony.enabled=true)
for pair in leadService:lead-service eventPublisher:event-publisher freeswitch:freeswitch; do
  key=${pair%%:*}; image=${pair#*:}
  tag="${TELEPHONY_TAG:-$(chart_tag "$image")}"
  [ -n "$tag" ] || { echo "no tag for $image in $CHART_TEL_VALUES" >&2; exit 1; }
  d=$(ensure_telephony "$image" "$tag")
  # Always pass tag + the digest that exists in ap-south-1 (overrides the chart's pin).
  args+=(--set-string "telephony.${key}.image.tag=${tag}"
         --set-string "telephony.${key}.image.digest=${d}")
  echo "telephony ${image}: ${tag}@${d}"
done

printf '%s\n' "${args[@]}" > "$out"
