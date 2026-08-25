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

    // staging -> the cluster's ECR (oan/leads-api, ap-south-1). buildx --push exports the
    // image straight to ECR (no local load) so there is NOTHING in `docker images` to
    // `docker rmi` afterwards. Auth = the agent's ambient AWS identity, same as
    // oan_a2c/registries. (If the buildkit CACHE grows on the shared agent, prune it with a
    // scoped `docker buildx prune -f` — never `docker system prune`, which wipes other jobs.)
    stage('Build & Push (staging → oan ECR)') {
      when { branch 'staging' }
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
      when { not { branch 'staging' } }
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
