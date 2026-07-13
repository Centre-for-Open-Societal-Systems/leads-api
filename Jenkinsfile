pipeline {
    agent any

    environment {
        ECR_REGISTRY   = '379220350808.dkr.ecr.us-west-2.amazonaws.com'
        ECR_REPOSITORY = 'leads-a2c'
        AWS_REGION     = 'us-west-2'
        DEPLOY_ENV     = "${env.DEPLOY_ENV ?: 'dev'}"
        FLOATING_TAG   = "${DEPLOY_ENV}-latest"
        IMAGE_TAG      = "${DEPLOY_ENV}-${env.GIT_COMMIT?.take(7) ?: 'latest'}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Login to ECR') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials']]) {
                    sh '''
                        aws ecr get-login-password --region $AWS_REGION | \
                        docker login --username AWS --password-stdin $ECR_REGISTRY
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh """
                    docker build -t ${ECR_REGISTRY}/${ECR_REPOSITORY}:${FLOATING_TAG} .
                    docker tag ${ECR_REGISTRY}/${ECR_REPOSITORY}:${FLOATING_TAG} \
                               ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                """
            }
        }

        stage('Push to ECR') {
            steps {
                sh """
                    docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${FLOATING_TAG}
                    docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                """
            }
        }
    }

    post {
        always {
            sh "docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:${FLOATING_TAG} || true"
            sh "docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG} || true"
        }
        success {
            echo '✅ Image pushed to ECR successfully!'
        }
        failure {
            echo '❌ Pipeline failed!'
        }
    }
}
