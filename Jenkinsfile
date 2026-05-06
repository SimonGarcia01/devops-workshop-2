pipeline {
    agent any

    environment {
        IMAGE_NAME = "auth-service"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                sh './gradlew :services:circleguard-auth-service:build'
            }
        }

        stage('Test') {
            steps {
                sh './gradlew :services:circleguard-auth-service:test'
            }
        }

        stage('Docker Build') {
            steps {
                sh 'docker build -t auth-service -f docker/auth/Dockerfile .'
            }
        }

        stage('Deploy to Dev') {
            steps {
                sh 'kubectl apply -f k8s/dev/auth/deployment.yaml'
                sh 'kubectl apply -f k8s/dev/auth/service.yaml'
            }
        }
    }
}