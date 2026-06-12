// Branch: develop / feature/*
// Triggered on every push. Deploys to 'dev' namespace.

pipeline {
    agent any

    environment {
        DOCKER_USER     = 'simongarcia01'
        NAMESPACE       = 'dev'
        SONAR_PROJECT   = 'circleguard'
        NOTIFY_EMAIL    = 'claudiaoponia@gmail.com'
    }

    stages {

        // ─────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // ─────────────────────────────────────────────
        stage('Semantic Version') {
            steps {
                script {
                    def latestTag = sh(
                        script: "git tag --sort=-v:refname | grep '^v' | head -1 || echo 'v0.0.0'",
                        returnStdout: true
                    ).trim()
                    def parts  = latestTag.replaceAll('^v', '').split('\\.')
                    def major  = parts[0]
                    def minor  = parts[1]
                    def patch  = (parts[2] ?: '0').replaceAll('-.*', '')
                    def commit = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()

                    env.IMAGE_TAG    = "v${major}.${minor}.${patch}-dev.${env.BUILD_NUMBER}"
                    env.DISPLAY_VER  = env.IMAGE_TAG
                    echo "Building version: ${env.IMAGE_TAG}"
                }
            }
        }

        // ─────────────────────────────────────────────
        stage('Build') {
            steps {
                sh '''
                    chmod +x gradlew
                    ./gradlew clean \
                        :services:circleguard-auth-service:build \
                        :services:circleguard-identity-service:build \
                        :services:circleguard-promotion-service:build \
                        :services:circleguard-gateway-service:build \
                        :services:circleguard-notification-service:build \
                        :services:circleguard-dashboard-service:build \
                        :services:circleguard-form-service:build \
                        -x test
                '''
            }
        }

        // ─────────────────────────────────────────────
        stage('Test') {
            steps {
                sh '''
                    ./gradlew \
                        :services:circleguard-auth-service:test \
                        :services:circleguard-identity-service:test \
                        :services:circleguard-promotion-service:test \
                        :services:circleguard-gateway-service:test \
                        :services:circleguard-notification-service:test \
                        :services:circleguard-dashboard-service:test \
                        :services:circleguard-form-service:test
                '''
            }
            post {
                always {
                    junit '**/build/test-results/test/*.xml'
                }
            }
        }

        // ─────────────────────────────────────────────
        stage('Frontend Build & Test') {
            steps {
                dir('mobile') {
                    sh '''
                        npm install
                        npm run test:ci
                        npm run build:web
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh """
                        ./gradlew sonar \
                            -Dsonar.projectKey=${SONAR_PROJECT} \
                            -Dsonar.projectVersion=${IMAGE_TAG} \
                            -Dsonar.branch.name=${env.BRANCH_NAME ?: 'develop'}
                    """
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ─────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                sh """
                    docker build -t ${DOCKER_USER}/auth-service:${IMAGE_TAG}         -f docker/auth/Dockerfile .
                    docker build -t ${DOCKER_USER}/identity-service:${IMAGE_TAG}     -f docker/identity/Dockerfile .
                    docker build -t ${DOCKER_USER}/promotion-service:${IMAGE_TAG}    -f docker/promotion/Dockerfile .
                    docker build -t ${DOCKER_USER}/gateway-service:${IMAGE_TAG}      -f docker/gateway/Dockerfile .
                    docker build -t ${DOCKER_USER}/notification-service:${IMAGE_TAG} -f docker/notification/Dockerfile .
                    docker build -t ${DOCKER_USER}/dashboard-service:${IMAGE_TAG}    -f docker/dashboard/Dockerfile .
                    docker build -t ${DOCKER_USER}/form-service:${IMAGE_TAG}         -f docker/form/Dockerfile .
                    docker build -t ${DOCKER_USER}/mobile-web:${IMAGE_TAG}           -f docker/mobile/Dockerfile .
                """
            }
        }

        // ─────────────────────────────────────────────
        stage('Trivy Security Scan') {
            steps {
                script {
                    def images = [
                        'auth-service', 'identity-service', 'promotion-service',
                        'gateway-service', 'notification-service',
                        'dashboard-service', 'form-service', 'mobile-web'
                    ]
                    images.each { svc ->
                        // Dev: warn on HIGH, do not fail pipeline
                        sh """
                            trivy image \
                                --exit-code 0 \
                                --severity HIGH,CRITICAL \
                                --format table \
                                --output trivy-${svc}-dev.txt \
                                ${DOCKER_USER}/${svc}:${IMAGE_TAG} || true
                        """
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-*-dev.txt', allowEmptyArchive: true
                }
            }
        }

        // ─────────────────────────────────────────────
        stage('Docker Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_CRED_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh """
                        echo \$DOCKER_PASS | docker login -u \$DOCKER_CRED_USER --password-stdin

                        docker push ${DOCKER_USER}/auth-service:${IMAGE_TAG}
                        docker push ${DOCKER_USER}/identity-service:${IMAGE_TAG}
                        docker push ${DOCKER_USER}/promotion-service:${IMAGE_TAG}
                        docker push ${DOCKER_USER}/gateway-service:${IMAGE_TAG}
                        docker push ${DOCKER_USER}/notification-service:${IMAGE_TAG}
                        docker push ${DOCKER_USER}/dashboard-service:${IMAGE_TAG}
                        docker push ${DOCKER_USER}/form-service:${IMAGE_TAG}
                        docker push ${DOCKER_USER}/mobile-web:${IMAGE_TAG}

                        docker tag ${DOCKER_USER}/auth-service:${IMAGE_TAG} ${DOCKER_USER}/auth-service:latest
                        docker push ${DOCKER_USER}/auth-service:latest
                    """
                }
            }
        }

        // ─────────────────────────────────────────────
        stage('Deploy Infra (Dev)') {
            steps {
                sh """
                    kubectl apply -f k8s/dev/postgres/postgres.yaml
                    kubectl apply -f k8s/dev/redis/redis.yaml
                    kubectl apply -f k8s/dev/zookeeper/zookeeper.yaml
                    kubectl apply -f k8s/dev/kafka/kafka.yaml
                    kubectl apply -f k8s/dev/neo4j/neo4j.yaml
                    kubectl apply -f k8s/dev/ldap/ldap.yaml

                    kubectl rollout status deployment/postgres   -n ${NAMESPACE} --timeout=90s
                    kubectl rollout status deployment/redis       -n ${NAMESPACE} --timeout=60s
                    kubectl rollout status deployment/zookeeper   -n ${NAMESPACE} --timeout=60s
                    kubectl rollout status deployment/kafka       -n ${NAMESPACE} --timeout=90s
                """
            }
        }

        stage('Deploy Services (Dev)') {
            steps {
                sh """
                    kubectl apply -f k8s/dev/auth/
                    kubectl apply -f k8s/dev/identity/
                    kubectl apply -f k8s/dev/promotion/
                    kubectl apply -f k8s/dev/gateway/
                    kubectl apply -f k8s/dev/notification/
                    kubectl apply -f k8s/dev/dashboard/
                    kubectl apply -f k8s/dev/form/
                    kubectl apply -f k8s/dev/mobile/

                    kubectl rollout status deployment/auth-service         -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/identity-service     -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/gateway-service      -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/promotion-service    -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/notification-service -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/dashboard-service    -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/form-service         -n ${NAMESPACE} --timeout=120s
                """
            }
        }

        // ─────────────────────────────────────────────
        stage('Smoke Tests (Dev)') {
            steps {
                sh '''
                    sleep 10
                    curl --fail --retry 3 --retry-delay 5 http://localhost:30081/actuator/health
                    curl --fail --retry 3 --retry-delay 5 http://localhost:30083/actuator/health
                    curl --fail --retry 3 --retry-delay 5 http://localhost:30087/actuator/health
                '''
            }
        }
    }

    // ─────────────────────────────────────────────
    post {
        success {
            echo "Dev pipeline completed successfully — version ${env.IMAGE_TAG}"
        }
        failure {
            emailext(
                subject: "❌ FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.IMAGE_TAG})",
                body: """
Pipeline falló en el ambiente DEV.

Job:    ${env.JOB_NAME}
Build:  #${env.BUILD_NUMBER}
Rama:   ${env.BRANCH_NAME ?: 'develop'}
Versión: ${env.IMAGE_TAG}

Consola: ${env.BUILD_URL}console
                """.stripIndent(),
                to: "${env.NOTIFY_EMAIL}"
            )
        }
        always {
            cleanWs()
        }
    }
}
