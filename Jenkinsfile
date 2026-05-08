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

        stage('Docker Build') {
            steps {
                sh '''
                    docker build -t auth-service -f docker/auth/Dockerfile .

                    docker build -t identity-service -f docker/identity/Dockerfile .

                    docker build -t promotion-service -f docker/promotion/Dockerfile .

                    docker build -t gateway-service -f docker/gateway/Dockerfile .

                    docker build -t notification-service -f docker/notification/Dockerfile .
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