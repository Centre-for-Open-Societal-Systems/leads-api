// =============================================================================
//  Jenkinsfile — leads-api (Spring Boot / verg).
//
//  This repo uses per-env STANDALONE "Pipeline from SCM" jobs (e.g. oan-leads-staging
//  checks out */staging and runs this file). Such jobs do NOT set env.BRANCH_NAME —
//  that only exists for multibranch jobs — so the target env is driven by the
//  DEPLOY_ENV build parameter the job supplies (default 'staging'). BRANCH_NAME is
//  honoured too, so the same file still works if ever run as a multibranch job.
//
//  Per env (DEPLOY_ENV):
//    staging -> build + push to ECR (oan/leads-api, ap-south-1) + ci/update-kustomize-ati.sh
//               (GitOps: bump the oan-kustomize `staging` overlay; ArgoCD on node 41 syncs)
//    other   -> build + push to the LEGACY ECR (leads-a2c, us-west-2) — previous behaviour,
//               no deploy step.
//
//  Tags:  <env>-<build>   immutable, pinned by oan-kustomize
//         <env>-latest    moving alias (convenience)
//
//  Agent needs: docker(+buildx), aws cli v2, git, kustomize.
//  Credentials: AWS_ACCOUNT_ID (string), aws-credentials (legacy path), oan-deployer
//               (GitHub App, contents:write on oan-kustomize). Staging ECR push uses the
//               agent's ambient AWS identity (must have ECR push on oan/*).
// =============================================================================
pipeline {
  agent any

  parameters {
    string(name: 'DEPLOY_ENV', defaultValue: 'staging',
           description: 'Target env: staging (oan ECR + GitOps) or dev/main (legacy ECR, no deploy)')
  }

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
          // Effective env: the DEPLOY_ENV parameter (how these standalone jobs are wired),
          // falling back to BRANCH_NAME for a multibranch job, else 'dev'.
          def envName = (params.DEPLOY_ENV?.trim()) ?: (env.BRANCH_NAME?.trim()) ?: 'dev'
          env.DEPLOY_TARGET = envName
          env.IS_STAGING = (envName == 'staging') ? 'true' : 'false'

          // staging -> the cluster's ECR (ap-south-1, oan/*). Everything else keeps the
          // legacy target so existing dev/main builds are unchanged.
          if (env.IS_STAGING == 'true') {
            env.AWS_REGION = 'ap-south-1'
            env.ECR_REPO   = 'oan/leads-api'
          } else {
            env.AWS_REGION = 'us-west-2'
            env.ECR_REPO   = 'leads-a2c'
          }
          env.IMMUTABLE_TAG = "${envName}-${env.BUILD_NUMBER}"
          env.MOVING_TAG    = "${envName}-latest"
          echo "env=${envName} staging=${env.IS_STAGING} region=${env.AWS_REGION} repo=${env.ECR_REPO} tag=${env.IMMUTABLE_TAG}"
        }
      }
    }

    // staging -> the cluster's ECR (oan/leads-api, ap-south-1). buildx --push exports the
    // image straight to ECR (no local load) so there is NOTHING in `docker images` to
    // `docker rmi` afterwards. Auth = the agent's ambient AWS identity, same as
    // oan_a2c/registries. (If the buildkit CACHE grows on the shared agent, prune it with a
    // scoped `docker buildx prune -f` — never `docker system prune`, which wipes other jobs.)
    stage('Build & Push (staging → oan ECR)') {
      when { expression { env.IS_STAGING == 'true' } }
      steps {
        withCredentials([string(credentialsId: 'AWS_ACCOUNT_ID', variable: 'AWS_ACCOUNT_ID')]) {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            IMAGE_URI="${REGISTRY}/${ECR_REPO}"

            aws ecr get-login-password --region "${AWS_REGION}" \
              | docker login --username AWS --password-stdin "${REGISTRY}"

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

    // dev / main -> UNCHANGED legacy behaviour: `docker build` + push to the legacy ECR
    // (leads-a2c, us-west-2) using the existing `aws-credentials`. `docker build` loads the
    // image into the local store, so it IS removed afterwards (docker rmi). AWS_ACCOUNT_ID
    // only builds the registry URL (same account as staging); the push auth comes from the
    // aws-credentials binding.
    stage('Build & Push (legacy → leads-a2c)') {
      when { expression { env.IS_STAGING != 'true' } }
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCOUNT_ID', variable: 'AWS_ACCOUNT_ID'),
          [$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']
        ]) {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            IMAGE_URI="${REGISTRY}/${ECR_REPO}"

            aws ecr get-login-password --region "${AWS_REGION}" \
              | docker login --username AWS --password-stdin "${REGISTRY}"

            docker build -t "${IMAGE_URI}:${IMMUTABLE_TAG}" -t "${IMAGE_URI}:${MOVING_TAG}" -f Dockerfile .
            docker push "${IMAGE_URI}:${IMMUTABLE_TAG}"
            docker push "${IMAGE_URI}:${MOVING_TAG}"
            # docker build loaded these into the local store -> scoped cleanup only.
            docker rmi "${IMAGE_URI}:${IMMUTABLE_TAG}" "${IMAGE_URI}:${MOVING_TAG}" || true
            echo "Pushed ${IMAGE_URI}:${IMMUTABLE_TAG} (+ ${MOVING_TAG})"
          '''
        }
      }
    }

    // staging -> GitOps: bump the oan-kustomize `staging` overlay to the new image.
    // Auth is the `oan-deployer` GitHub App (contents:write on oan-kustomize only);
    // gitUsernamePassword mints a short-lived installation token. All kustomize logic
    // lives in ci/update-kustomize-ati.sh.
    stage('staging → GitOps (ArgoCD@41)') {
      when { expression { env.IS_STAGING == 'true' } }
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCOUNT_ID', variable: 'AWS_ACCOUNT_ID'),
          gitUsernamePassword(credentialsId: 'oan-deployer', gitToolName: 'Default')
        ]) {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            chmod +x ci/update-kustomize-ati.sh
            # args: <overlay> <kustomize image match-name> <new image ref>
            ci/update-kustomize-ati.sh staging leads-api \
              "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMMUTABLE_TAG}"
          '''
        }
      }
    }
  }

  post {
    success { echo "OK  ${env.DEPLOY_TARGET} #${env.BUILD_NUMBER} -> ${env.IMMUTABLE_TAG}" }
    failure { echo "FAIL ${env.DEPLOY_TARGET} #${env.BUILD_NUMBER}" }
  }
}
