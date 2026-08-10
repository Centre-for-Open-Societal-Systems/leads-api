// =============================================================================
//  Jenkinsfile — leads-api (Spring Boot / verg). Multibranch.
//
//  Per branch:
//    staging -> build + push to ECR (oan/leads-api, ap-south-1) + ci/update-kustomize.sh
//               (GitOps: bump the oan-kustomize `staging` overlay; ArgoCD on node 41 syncs)
//    other   -> build + push to the LEGACY ECR (leads-a2c, us-west-2) — previous behaviour,
//               no deploy step.
//
//  Tags:  <branch>-<build>   immutable, pinned by oan-kustomize
//         <branch>-latest    moving alias (convenience)
//
//  Agent needs: docker(+buildx), aws cli v2, git, kustomize.
//  Credentials: AWS_ACCOUNT_ID (string), oan-deployer (GitHub App, contents:write on
//               oan-kustomize). ECR push uses the agent's ambient AWS identity, which must
//               have ECR push on both oan/* (ap-south-1) and leads-a2c (us-west-2).
// =============================================================================
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 40, unit: 'MINUTES')
  }

  stages {
    stage('Resolve') {
      steps {
        script {
          // staging -> the cluster's ECR (ap-south-1, oan/*). Everything else keeps the
          // legacy target so existing dev/main builds are unchanged.
          if (env.BRANCH_NAME == 'staging') {
            env.AWS_REGION = 'ap-south-1'
            env.ECR_REPO   = 'oan/leads-api'
          } else {
            env.AWS_REGION = 'us-west-2'
            env.ECR_REPO   = 'leads-a2c'
          }
          env.IMMUTABLE_TAG = "${env.BRANCH_NAME}-${env.BUILD_NUMBER}"
          env.MOVING_TAG    = "${env.BRANCH_NAME}-latest"
          echo "branch=${env.BRANCH_NAME} region=${env.AWS_REGION} repo=${env.ECR_REPO} tag=${env.IMMUTABLE_TAG}"
        }
      }
    }

    stage('Build & Push') {
      steps {
        withCredentials([string(credentialsId: 'AWS_ACCOUNT_ID', variable: 'AWS_ACCOUNT_ID')]) {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            IMAGE_URI="${REGISTRY}/${ECR_REPO}"

            aws ecr get-login-password --region "${AWS_REGION}" \
              | docker login --username AWS --password-stdin "${REGISTRY}"

            # Plain multi-stage Dockerfile build (Maven -> JRE). Push straight to ECR
            # (buildx --push: no local load of the image, no separate push step).
            # No `docker rmi` cleanup needed: --push exports the image directly to the
            # registry and never populates the local image store, so there is nothing in
            # `docker images` to remove. (If the buildkit CACHE grows on the shared agent,
            # prune it with a scoped `docker buildx prune -f` — never `docker system prune`,
            # which would wipe other jobs' caches.)
            DOCKER_BUILDKIT=1 docker buildx build \
              --tag "${IMAGE_URI}:${IMMUTABLE_TAG}" \
              --tag "${IMAGE_URI}:${MOVING_TAG}" \
              --file Dockerfile \
              --push .
            echo "Pushed ${IMAGE_URI}:${IMMUTABLE_TAG} (+ ${MOVING_TAG})"
          '''
        }
      }
    }

    // staging -> GitOps: bump the oan-kustomize `staging` overlay to the new image.
    // Auth is the `oan-deployer` GitHub App (contents:write on oan-kustomize only);
    // gitUsernamePassword mints a short-lived installation token. All kustomize logic
    // lives in ci/update-kustomize.sh.
    stage('staging → GitOps (ArgoCD@41)') {
      when { branch 'staging' }
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCOUNT_ID', variable: 'AWS_ACCOUNT_ID'),
          gitUsernamePassword(credentialsId: 'oan-deployer', gitToolName: 'Default')
        ]) {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            chmod +x ci/update-kustomize.sh
            # args: <overlay> <kustomize image match-name> <new image ref>
            ci/update-kustomize.sh staging leads-api \
              "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMMUTABLE_TAG}"
          '''
        }
      }
    }
  }

  post {
    success { echo "OK  ${env.BRANCH_NAME} #${env.BUILD_NUMBER} -> ${env.IMMUTABLE_TAG}" }
    failure { echo "FAIL ${env.BRANCH_NAME} #${env.BUILD_NUMBER}" }
  }
}
