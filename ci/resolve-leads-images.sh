#!/usr/bin/env bash
# =============================================================================
#  Pin the images for the leads namespace install by digest, making sure each one exists in
#  ap-south-1 first, so the release pulls everything from one registry (ECR pull secret
#  leads-api-ecr). Runs on the BUILD agent (docker + buildx + aws); the Helm install runs on the
#  deploy agent, which needs no AWS access. Called by the Jenkinsfile stage
#  'Resolve images (leads namespace)'.
#
#  leads-api:  the image this build just pushed, $ECR_REPO:$IMMUTABLE_TAG in $AWS_REGION.
#              Already in ap-south-1 (staging, oan/leads-api): used as it is. Otherwise (the
#              legacy dev/main push to leads-a2c, us-west-2, left unchanged) it is copied to
#              ap-south-1 eoan/leads-api/leads-api:<LEADS_VERSION>-<branch>.<BUILD_NUMBER>
#              (dev -> 0.1.0-develop.<N>), the OAN naming standard.
#  telephony:  ap-south-1 eoan/leads-api/{lead-service,event-publisher,freeswitch}:<tag>, where
#              <tag> is TELEPHONY_TAG or, when empty, the build pinned in the chart. If missing,
#              it is copied from the Telephony-Service push in ap-northeast-1
#              (freeswitch-<image>:<build>).
#  Copies use `docker buildx imagetools create` (registry to registry, same digest); a missing
#  ap-south-1 repository is created with the eoan settings (immutable, scan on push, AES256).
#
#  Env in (set by Jenkins / the Jenkinsfile):
#    AWS_ACCOUNT_ID, AWS_REGION, ECR_REPO, IMMUTABLE_TAG  the leads-api image this build pushed
#    BUILD_NUMBER, DEPLOY_TARGET                          name the ap-south-1 leads-api copy
#    LEADS_VERSION       optional, default 0.1.0 (the chart's appVersion)
#    TELEPHONY           true|false: install the telephony subchart
#    TELEPHONY_TAG       optional, e.g. 0.1.0-develop.24; empty = the build pinned in the chart
#    TEL_AWS_ACCESS_KEY_ID / TEL_AWS_SECRET_ACCESS_KEY
#                        the Telephony-Service identity (aws-credentials), used only for the
#                        telephony images; leads-api uses the identity that pushed it
#  Out: the file named by $1, one Helm argument per line, for ci/deploy-leads-helm.sh.
# =============================================================================
set -euo pipefail
shopt -s inherit_errexit   # stop at the first failure inside $(...) too

out="${1:?usage: resolve-leads-images.sh <args-file>}"
: "${AWS_ACCOUNT_ID:?}" "${AWS_REGION:?}" "${ECR_REPO:?}" "${IMMUTABLE_TAG:?}"
TELEPHONY="${TELEPHONY:-true}"
TELEPHONY_TAG="${TELEPHONY_TAG:-}"
LEADS_VERSION="${LEADS_VERSION:-0.1.0}"

DST_REGION=ap-south-1                      # every image of the release is pulled from here
DST_PREFIX=eoan/leads-api
TEL_SRC_REGION=ap-northeast-1              # where Telephony-Service pushes every build
TEL_SRC_PREFIX=freeswitch-                 # freeswitch-<image>:<BUILD_NUMBER>
CHART_TEL_VALUES=helm/leads-api/charts/telephony/values.yaml

registry() { echo "${AWS_ACCOUNT_ID}.dkr.ecr.$1.amazonaws.com"; }

digest_of() { # <region> <repository> <tag>  -> digest; empty if missing; fails on any other error
  local res err rc=0
  err=$(mktemp)
  # stderr kept apart: a CLI warning on a successful call must not hide the digest.
  res=$(aws ecr describe-images --region "$1" --repository-name "$2" --image-ids imageTag="$3" \
          --query 'imageDetails[0].imageDigest' --output text 2>"$err") || rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$err"
    [[ "$res" =~ ^sha256:[a-f0-9]{64}$ ]] && echo "$res"
    return 0
  fi
  if grep -qE 'ImageNotFoundException|RepositoryNotFoundException' "$err"; then rm -f "$err"; return 0; fi
  echo "aws ecr describe-images $2:$3 in $1 failed: $(cat "$err")" >&2
  rm -f "$err"
  return 1
}

# <dst repo> <dst tag> <src region> <src repo> <src tag>  -> digest of dst in ap-south-1.
# Copies src -> dst when dst is missing; fails if src is missing too, or if an existing dst
# has a different digest from src.
ensure_image() {
  local dst=$1 dtag=$2 sregion=$3 src=$4 stag=$5 d s
  s=$(digest_of "$sregion" "$src" "$stag")
  d=$(digest_of "$DST_REGION" "$dst" "$dtag")
  if [ -n "$d" ]; then
    if [ -n "$s" ] && [ "$s" != "$d" ]; then
      echo "$dst:$dtag in $DST_REGION is $d but $src:$stag in $sregion is $s" >&2; return 1
    fi
    echo "$d"; return 0
  fi
  [ -n "$s" ] || { echo "missing everywhere: $dst:$dtag in $DST_REGION and $src:$stag in $sregion" >&2; return 1; }

  echo "copying $sregion $src:$stag -> $DST_REGION $dst:$dtag" >&2
  aws ecr describe-repositories --region "$DST_REGION" --repository-names "$dst" >/dev/null 2>&1 \
    || aws ecr create-repository --region "$DST_REGION" --repository-name "$dst" \
         --image-tag-mutability IMMUTABLE \
         --image-scanning-configuration scanOnPush=true \
         --encryption-configuration encryptionType=AES256 \
         --tags Key=owner,Value=leads-api Key=naming,Value=eoan-standard >/dev/null
  aws ecr get-login-password --region "$DST_REGION" \
    | docker login -u AWS --password-stdin "$(registry "$DST_REGION")" >/dev/null
  aws ecr get-login-password --region "$sregion" \
    | docker login -u AWS --password-stdin "$(registry "$sregion")" >/dev/null
  docker buildx imagetools create --tag "$(registry "$DST_REGION")/$dst:$dtag" \
    "$(registry "$sregion")/$src:$stag" >&2
  d=$(digest_of "$DST_REGION" "$dst" "$dtag")
  [ -n "$d" ] || { echo "copy of $dst:$dtag did not land in $DST_REGION" >&2; return 1; }
  [ "$d" = "$s" ] || { echo "copy of $dst:$dtag has digest $d, source has $s" >&2; return 1; }
  echo "$d"
}

# --- leads-api: pushed by this build (identity that pushed it) ---
if [ "$AWS_REGION" = "$DST_REGION" ]; then
  LEADS_REPO=$ECR_REPO
  LEADS_TAG=$IMMUTABLE_TAG
  LEADS_DIGEST=$(digest_of "$AWS_REGION" "$ECR_REPO" "$IMMUTABLE_TAG")
  [ -n "$LEADS_DIGEST" ] || { echo "no image ${ECR_REPO}:${IMMUTABLE_TAG} in ${AWS_REGION}" >&2; exit 1; }
else
  : "${BUILD_NUMBER:?}" "${DEPLOY_TARGET:?}"
  case "$DEPLOY_TARGET" in dev|develop) branch=develop ;; *) branch=$DEPLOY_TARGET ;; esac
  LEADS_REPO="$DST_PREFIX/leads-api"
  LEADS_TAG="${LEADS_VERSION}-${branch}.${BUILD_NUMBER}"
  LEADS_DIGEST=$(ensure_image "$LEADS_REPO" "$LEADS_TAG" "$AWS_REGION" "$ECR_REPO" "$IMMUTABLE_TAG")
fi
args=(
  --set-string "image.repository=$(registry "$DST_REGION")/${LEADS_REPO}"
  --set-string "image.tag=${LEADS_TAG}"
  --set-string "image.digest=${LEADS_DIGEST}"
)
echo "leads-api: ${LEADS_REPO}:${LEADS_TAG}@${LEADS_DIGEST}"

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
  awk -v img="$DST_PREFIX/$1" '
    $1=="repository:" && $2==img {f=1; next}
    f && $1=="tag:" {gsub(/"/,"",$2); print $2; exit}' "$CHART_TEL_VALUES"
}

args+=(--set telephony.enabled=true)
for pair in leadService:lead-service eventPublisher:event-publisher freeswitch:freeswitch; do
  key=${pair%%:*}; image=${pair#*:}
  tag="${TELEPHONY_TAG:-$(chart_tag "$image")}"
  [ -n "$tag" ] || { echo "no tag for $image in $CHART_TEL_VALUES" >&2; exit 1; }
  build=${tag##*.}                                   # 0.1.0-develop.23 -> 23
  [[ "$build" =~ ^[0-9]+$ ]] || { echo "cannot derive a build number from tag $tag" >&2; exit 1; }
  d=$(ensure_image "$DST_PREFIX/$image" "$tag" "$TEL_SRC_REGION" "${TEL_SRC_PREFIX}${image}" "$build")
  # Always pass tag + the digest that exists in ap-south-1 (overrides the chart's pin).
  args+=(--set-string "telephony.${key}.image.tag=${tag}"
         --set-string "telephony.${key}.image.digest=${d}")
  echo "telephony ${image}: ${tag}@${d}"
done

printf '%s\n' "${args[@]}" > "$out"
