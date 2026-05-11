pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                sh '''
                    chmod +x gradlew

                    ./gradlew \
                    :services:circleguard-auth-service:build \
                    :services:circleguard-identity-service:build \
                    :services:circleguard-promotion-service:build \
                    :services:circleguard-gateway-service:build \
                    :services:circleguard-notification-service:build
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    chmod +x gradlew

                    ./gradlew \
                    :services:circleguard-auth-service:test \
                    :services:circleguard-identity-service:test \
                    :services:circleguard-promotion-service:test \
                    :services:circleguard-gateway-service:test \
                    :services:circleguard-notification-service:test
                '''
            }
        }
        
        stage('Frontend Build') {
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

        stage('Docker Build') {
            steps {
                sh '''
                    docker build -t simongarcia01/auth-service:latest -f docker/auth/Dockerfile .
                    docker push simongarcia01/auth-service:latest
                    docker build -t simongarcia01/identity-service:latest -f docker/identity/Dockerfile .
                    docker push simongarcia01/identity-service:latest
                    docker build -t simongarcia01/promotion-service:latest -f docker/promotion/Dockerfile .
                    docker push simongarcia01/promotion-service:latest
                    docker build -t simongarcia01/gateway-service:latest -f docker/gateway/Dockerfile .
                    docker push simongarcia01/gateway-service:latest
                    docker build -t simongarcia01/notification-service:latest -f docker/notification/Dockerfile .
                    docker push simongarcia01/notification-service:latest
                    docker build -t simongarcia01/mobile-web:latest -f docker/mobile/Dockerfile .
                    docker push simongarcia01/mobile-web:latest
                '''
            }
        }

    stage('Deploy Infra') {
        steps {
            sh '''
                kubectl apply -f k8s/dev/postgres/postgres.yaml
                kubectl apply -f k8s/dev/neo4j/neo4j.yaml
                kubectl apply -f k8s/dev/zookeeper/zookeeper.yaml
                kubectl apply -f k8s/dev/kafka/kafka.yaml
                kubectl apply -f k8s/dev/redis/redis.yaml
                kubectl apply -f k8s/dev/ldap/ldap.yaml
            '''

            sh '''
                kubectl rollout status deployment/postgres -n dev
                kubectl rollout status deployment/neo4j -n dev
                kubectl rollout status deployment/zookeeper -n dev
                kubectl rollout status deployment/kafka -n dev
                kubectl rollout status deployment/redis -n dev
                kubectl rollout status deployment/ldap -n dev
            '''
        }
    }

        stage('Deploy to Dev') {
            steps {
                sh '''
                    kubectl apply -f k8s/dev/auth/deployment.yaml
                    kubectl apply -f k8s/dev/auth/service.yaml

                    kubectl apply -f k8s/dev/identity/deployment.yaml
                    kubectl apply -f k8s/dev/identity/service.yaml

                    kubectl apply -f k8s/dev/promotion/deployment.yaml
                    kubectl apply -f k8s/dev/promotion/service.yaml

                    kubectl apply -f k8s/dev/gateway/deployment.yaml
                    kubectl apply -f k8s/dev/gateway/service.yaml

                    kubectl apply -f k8s/dev/notification/deployment.yaml
                    kubectl apply -f k8s/dev/notification/service.yaml

                    kubectl apply -f k8s/dev/mobile/deployment.yaml
                    kubectl apply -f k8s/dev/mobile/service.yaml

                    kubectl rollout restart deployment -n dev
                '''
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully!'
        }

        failure {
            echo 'Pipeline failed!'
        }
    }
}