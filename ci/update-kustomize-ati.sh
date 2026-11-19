#!/usr/bin/env bash
# =============================================================================
#  update-kustomize.sh — GitOps write-back (called by Jenkins on the staging branch).
#  Points an oan-kustomize overlay at a new image, commits, and pushes to main.
#  ArgoCD on node 41 then syncs apps/*/overlays/staging.
#
#  Usage: ci/update-kustomize.sh <overlay> <kustomize-image-name> <new-image-ref>
#     <overlay>              overlay dir under apps/leads-api/overlays/   (e.g. staging)
#     <kustomize-image-name> the image 'name' key in the base deployment (match key)
#     <new-image-ref>        full ECR URI:tag to deploy
#
#  Auth: MUST run inside withCredentials(gitUsernamePassword(credentialsId:'oan-deployer')).
#        The git-client plugin injects a short-lived installation token (contents:write
#        on oan-kustomize only) over HTTPS — no token in the URL or logs.
#  Agent prereqs: git, curl, sha256sum, tar (kustomize is fetched if not installed).
# =============================================================================
set -euo pipefail

OVERLAY="${1:?usage: update-kustomize.sh <overlay> <image-name> <image-ref>}"
IMG_NAME="${2:?missing kustomize image match-name}"
NEW_REF="${3:?missing new image ref}"

REPO_URL="https://github.com/Centre-for-Open-Societal-Systems/oan-kustomize.git"
OVERLAY_PATH="apps/leads-api/overlays/${OVERLAY}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# kustomize: use the agent's copy if present, else fetch a pinned, checksum-verified
# release into $WORK (the shared agent doesn't ship it; no root/install needed).
KUSTOMIZE_VERSION="v5.4.3"
if ! command -v kustomize >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64|amd64)  K_ARCH=amd64; K_SHA=3669470b454d865c8184d6bce78df05e977c9aea31c30df3c669317d43bcc7a7 ;;
    aarch64|arm64) K_ARCH=arm64; K_SHA=1b515578b0af12c15d9856720066ce2fe66756d63785b2cbccaf2885beb2381c ;;
    *) echo "unsupported arch $(uname -m) for kustomize bootstrap" >&2; exit 1 ;;
  esac
  K_TGZ="kustomize_${KUSTOMIZE_VERSION}_linux_${K_ARCH}.tar.gz"
  echo ">> kustomize not on PATH — fetching ${KUSTOMIZE_VERSION} (${K_ARCH})"
  mkdir -p "$WORK/bin"
  curl -fsSL --retry 3 -o "$WORK/$K_TGZ" \
    "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/${K_TGZ}"
  echo "${K_SHA}  $WORK/$K_TGZ" | sha256sum -c -
  tar -xzf "$WORK/$K_TGZ" -C "$WORK/bin" kustomize
  export PATH="$WORK/bin:$PATH"
fi
kustomize version

echo ">> clone oan-kustomize (main)"
git clone --depth 1 --branch main "$REPO_URL" "$WORK/repo"

echo ">> kustomize set image ${IMG_NAME}=${NEW_REF}  (${OVERLAY_PATH})"
( cd "$WORK/repo/${OVERLAY_PATH}" && kustomize edit set image "${IMG_NAME}=${NEW_REF}" )

cd "$WORK/repo"
git config user.name  "oan-deployer[bot]"
git config user.email "oan-deployer[bot]@users.noreply.github.com"
git add -A
if git diff --cached --quiet; then
  echo ">> no change (${NEW_REF} already current) — nothing to push"
  exit 0
fi
git commit -m "ci(leads-api): ${OVERLAY} image -> ${NEW_REF##*/}"
git push origin main
echo ">> pushed: ${OVERLAY} now on ${NEW_REF}"
