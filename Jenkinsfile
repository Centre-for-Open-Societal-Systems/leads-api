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
//  dev branch -> leads namespace ONLY, whatever DEPLOY_ENV says: build + push to ap-south-1
//    eoan/leads-api/leads-api:0.1.0-develop.<build>, then Helm-install helm/leads-api (leads-api +
//    telephony unless TELEPHONY is unticked) into namespace `leads` (leads node 10.0.1.131). No
//    staging ECR push, no oan-kustomize/ArgoCD change, no legacy push.
//  Other branches with DEPLOY_LEADS_NS=true: the env's push/GitOps above, then the same install;
//    a legacy us-west-2 image is copied to eoan/leads-api/leads-api (same digest). Digests on this
//    agent (ci/resolve-leads-images.sh), Helm on oan-ci-deploy (ci/deploy-leads-helm.sh).
//
//  Tags:  <env>-<build>   immutable, pinned by oan-kustomize (staging uses a `staging-ati-`
//                         prefix -> staging-ati-<build>, uniform with the other repos)
//         <env>-latest    moving alias (convenience)
//
//  Agent needs: docker(+buildx), aws cli v2, git, curl (kustomize auto-fetched by the CI script).
//  Credentials: AWS_ACCOUNT_ID (string), aws-credentials (legacy path), oan-deployer
//               (GitHub App, contents:write on oan-kustomize). Staging ECR push uses the
//               agent's ambient AWS identity (must have ECR push on oan/*).
// =============================================================================
pipeline {
  agent any

  parameters {
    string(name: 'DEPLOY_ENV', defaultValue: 'staging',
           description: 'Target env: staging (oan ECR + GitOps) or dev/main (legacy ECR, no deploy)')
    // Helm install of helm/leads-api (leads-api + telephony) into namespace `leads`: always on
    // builds of the `dev` branch; other branches only with this ticked.
    // The existing push / GitOps stages run first and are never changed by it.
    booleanParam(name: 'DEPLOY_LEADS_NS', defaultValue: false,
           description: 'Install helm/leads-api (leads-api + telephony) into namespace leads. Always on for the dev branch; tick it to deploy from another branch')
    booleanParam(name: 'TELEPHONY', defaultValue: true,
           description: 'Install telephony in the same release, in namespace leads (never a separate namespace)')
    string(name: 'TELEPHONY_TAG', defaultValue: '',
           description: 'Telephony image tag in ap-south-1 eoan/leads-api/* (e.g. 0.1.0-develop.24); empty = the build pinned in the chart')
    // Telephony-Service pushes every build to ap-south-1 eoan/leads-api/* itself, so the images
    // are normally read there with this agent's AWS identity and no extra credential. Name an
    // AWS credential here only to copy an image that is still missing from ap-northeast-1.
    string(name: 'TELEPHONY_AWS_CRED', defaultValue: '',
           description: 'Optional Jenkins AWS credential (e.g. aws-credentials) for copying a telephony image missing from ap-south-1 out of ap-northeast-1; empty = this agent\'s identity, ap-south-1 only')
    string(name: 'LEADS_KUBECONFIG_CRED', defaultValue: 'oan-dev-kubeconfig',
           description: 'Jenkins secret-file credential: oan_dev deployer kubeconfig (jenkins-a2c-deployer, admin in leads via oan-helm environments/dev/values/oan-cluster-access.yaml)')
    string(name: 'LEADS_VALUES_CRED', defaultValue: 'dev-leads-secret-values',
           description: 'Jenkins secret-file credential: Elasticsearch host + usernames/passwords (template helm/leads-api/ci/deploy-values.example.yaml)')
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
          // The dev branch goes to the leads namespace ONLY: never the staging ECR/GitOps, whatever
          // DEPLOY_ENV says (its default is 'staging', which a multibranch dev job would inherit).
          env.LEADS_ONLY = (env.BRANCH_NAME == 'dev') ? 'true' : 'false'
          def envName = (env.LEADS_ONLY == 'true') ? 'dev'
                      : ((params.DEPLOY_ENV?.trim()) ?: (env.BRANCH_NAME?.trim()) ?: 'dev')
          env.DEPLOY_TARGET = envName
          env.IS_STAGING = (envName == 'staging') ? 'true' : 'false'
          // leads namespace install: automatic for the dev branch (pushes and merges included;
          // pull-request builds are PR-<n>, never dev), on request for any other branch.
          env.DEPLOY_LEADS = (env.LEADS_ONLY == 'true' || params.DEPLOY_LEADS_NS) ? 'true' : 'false'

          if (env.LEADS_ONLY == 'true') {
            // dev -> straight to the leads install's registry, ap-south-1 eoan/leads-api/leads-api
            // (immutable repo: one tag, no moving alias), the OAN naming standard.
            env.AWS_REGION    = 'ap-south-1'
            env.ECR_REPO      = 'eoan/leads-api/leads-api'
            env.IMMUTABLE_TAG = "0.1.0-develop.${env.BUILD_NUMBER}"
            env.MOVING_TAG    = ''
          } else {
            // staging -> the cluster's ECR (ap-south-1, oan/*). Everything else keeps the
            // legacy target so existing main builds are unchanged.
            if (env.IS_STAGING == 'true') {
              env.AWS_REGION = 'ap-south-1'
              env.ECR_REPO   = 'oan/leads-api'
            } else {
              env.AWS_REGION = 'us-west-2'
              env.ECR_REPO   = 'leads-a2c'
            }
            // staging (the ATI/GitOps path) publishes under a `staging-ati-` prefix so the
            // immutable tag reads staging-ati-<build>, uniform with the other repos. Non-staging
            // (legacy main) keeps its <env>- tag.
            def tagPrefix     = (envName == 'staging') ? 'staging-ati' : envName
            env.IMMUTABLE_TAG = "${tagPrefix}-${env.BUILD_NUMBER}"
            env.MOVING_TAG    = "${tagPrefix}-latest"
          }
          echo "env=${envName} leads-only=${env.LEADS_ONLY} staging=${env.IS_STAGING} region=${env.AWS_REGION} repo=${env.ECR_REPO} tag=${env.IMMUTABLE_TAG} leads-ns=${env.DEPLOY_LEADS} telephony=${params.TELEPHONY}"
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
    // dev branch -> ap-south-1 eoan/leads-api/leads-api only (agent identity, as for staging).
    // The repository is created with the eoan settings if missing, as resolve-leads-images.sh does.
    stage('Build & Push (dev → eoan ECR, leads only)') {
      when { expression { env.LEADS_ONLY == 'true' } }
      steps {
        withCredentials([string(credentialsId: 'AWS_ACCOUNT_ID', variable: 'AWS_ACCOUNT_ID')]) {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            IMAGE_URI="${REGISTRY}/${ECR_REPO}"

            aws ecr describe-repositories --region "${AWS_REGION}" --repository-names "${ECR_REPO}" >/dev/null 2>&1 \
              || aws ecr create-repository --region "${AWS_REGION}" --repository-name "${ECR_REPO}" \
                   --image-tag-mutability IMMUTABLE \
                   --image-scanning-configuration scanOnPush=true \
                   --encryption-configuration encryptionType=AES256 \
                   --tags Key=owner,Value=leads-api Key=naming,Value=eoan-standard >/dev/null

            aws ecr get-login-password --region "${AWS_REGION}" \
              | docker login --username AWS --password-stdin "${REGISTRY}"

            DOCKER_BUILDKIT=1 docker buildx build \
              --tag "${IMAGE_URI}:${IMMUTABLE_TAG}" \
              --file Dockerfile \
              --push .
            echo "Pushed ${IMAGE_URI}:${IMMUTABLE_TAG}"
          '''
        }
      }
    }

    stage('Build & Push (legacy → leads-a2c)') {
      when { expression { env.IS_STAGING != 'true' && env.LEADS_ONLY != 'true' } }
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

    // dev branch builds, or DEPLOY_LEADS_NS: install the image this build pushed, plus telephony, with
    // the helm/leads-api chart into namespace `leads`. Runs after the existing push/GitOps
    // stages and never changes them. A failure marks the build UNSTABLE, not green.
    // Two steps, as in the registries (oan-helm docs/release/environments.md §4):
    //   1. on this build agent (AWS identity): pin every image by digest;
    //   2. on the oan-ci-deploy agent (reaches the clusters): helm upgrade with the
    //      oan-dev-kubeconfig (admin in leads). Secrets come from LEADS_VALUES_CRED, never Git.
    stage('Resolve images (leads namespace)') {
      when { expression { env.DEPLOY_LEADS == 'true' } }
      steps {
        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
          script {
            def creds = [string(credentialsId: 'AWS_ACCOUNT_ID', variable: 'AWS_ACCOUNT_ID')]
            // leads-api is read (and, from the legacy us-west-2 push, copied to ap-south-1
            // eoan/leads-api/leads-api, same digest) with the identity that pushed it: the legacy
            // push authenticates with aws-credentials; staging uses the agent's identity.
            if (env.IS_STAGING != 'true' && env.LEADS_ONLY != 'true') {
              creds <<[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']
            }
            // Telephony images are read in ap-south-1 eoan/leads-api/* (pushed there by
            // Telephony-Service) with the identity in use above. Only when TELEPHONY_AWS_CRED names
            // a credential is it bound, under its own names, to copy a missing image from
            // ap-northeast-1. Missing telephony images are copied, never rebuilt.
            def telCred = params.TELEPHONY_AWS_CRED?.trim()
            if (params.TELEPHONY && telCred) {
              creds << [$class: 'AmazonWebServicesCredentialsBinding', credentialsId: telCred,
                        accessKeyVariable: 'TEL_AWS_ACCESS_KEY_ID', secretKeyVariable: 'TEL_AWS_SECRET_ACCESS_KEY']
            }
            withCredentials(creds) {
              withEnv(["TELEPHONY=${params.TELEPHONY}",
                       "TELEPHONY_TAG=${params.TELEPHONY_TAG?.trim() ?: ''}"]) {
                sh '''#!/usr/bin/env bash
                  set -euo pipefail
                  bash ci/resolve-leads-images.sh leads-images.args
                '''
              }
            }
            stash name: 'leads-images', includes: 'leads-images.args'
            env.LEADS_IMAGES_RESOLVED = 'true'
          }
        }
      }
    }

    stage('Deploy (Helm → leads namespace)') {
      when {
        beforeAgent true   // decide first; do not take the deploy agent for a skipped stage
        expression { env.DEPLOY_LEADS == 'true' && env.LEADS_IMAGES_RESOLVED == 'true' }
      }
      agent { label 'oan-ci-deploy' }
      steps {
        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
          unstash 'leads-images'
          withCredentials([
            file(credentialsId: params.LEADS_KUBECONFIG_CRED, variable: 'KUBECONFIG'),
            file(credentialsId: params.LEADS_VALUES_CRED, variable: 'LEADS_VALUES_FILE')
          ]) {
            sh '''#!/usr/bin/env bash
              set -euo pipefail
              bash ci/deploy-leads-helm.sh leads-images.args
            '''
          }
        }
      }
    }
  }

  post {
    // Bound the BuildKit cache so the shared agent's disk can't fill over many builds.
    // The staging path uses `buildx --push` (nothing lands in `docker images` to rmi), but
    // the build CACHE still accumulates in the separate BuildKit store. --max-used-space
    // caps it at ~20GB (buildx v0.34+). Scoped to the build cache only.
    always  { sh 'docker buildx prune -f --max-used-space=20GB 2>/dev/null || true' }
    success { echo "OK  ${env.DEPLOY_TARGET} #${env.BUILD_NUMBER} -> ${env.IMMUTABLE_TAG}" }
    failure { echo "FAIL ${env.DEPLOY_TARGET} #${env.BUILD_NUMBER}" }
  }
}
