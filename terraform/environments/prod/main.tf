terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

locals {
  # Production uses full resource allocation
  resources = {
    requests_cpu    = "250m"
    requests_memory = "512Mi"
    limits_cpu      = "1000m"
    limits_memory   = "1Gi"
  }
}

module "namespace" {
  source = "../../modules/namespace"
  name   = "prod"
}

module "infrastructure" {
  source    = "../../modules/infrastructure"
  namespace = module.namespace.name

  postgres_password   = var.db_password
  neo4j_password      = var.neo4j_password
  ldap_admin_password = var.ldap_password
}

module "auth_service" {
  source         = "../../modules/microservice"
  name           = "auth-service"
  namespace      = module.namespace.name
  image          = "simongarcia01/auth-service:${var.image_tag}"
  container_port = 8180
  replicas       = var.replicas
  service_type   = "NodePort"
  node_port      = 32081
  resources      = local.resources

  env_vars = {
    SPRING_DATASOURCE_URL      = "jdbc:postgresql://postgres-service:5432/auth_db"
    SPRING_DATASOURCE_USERNAME = "admin"
    SPRING_DATASOURCE_PASSWORD = var.db_password
    SPRING_LDAP_URLS           = "ldap://ldap-service:389"
    SPRING_LDAP_BASE           = "dc=circleguard,dc=edu"
    SPRING_LDAP_USERNAME       = "cn=admin,dc=circleguard,dc=edu"
    SPRING_LDAP_PASSWORD       = var.ldap_password
    JWT_SECRET                 = var.jwt_secret
    JWT_EXPIRATION             = "3600000"
    QR_SECRET                  = var.qr_secret
    QR_EXPIRATION              = "300"
  }

  depends_on = [module.infrastructure]
}

module "identity_service" {
  source         = "../../modules/microservice"
  name           = "identity-service"
  namespace      = module.namespace.name
  image          = "simongarcia01/identity-service:${var.image_tag}"
  container_port = 8083
  replicas       = var.replicas
  service_type   = "NodePort"
  node_port      = 32083
  resources      = local.resources

  env_vars = {
    SPRING_DATASOURCE_URL      = "jdbc:postgresql://postgres-service:5432/identity_db"
    SPRING_DATASOURCE_USERNAME = "admin"
    SPRING_DATASOURCE_PASSWORD = var.db_password
    KAFKA_BOOTSTRAP_SERVERS    = "kafka-service:9092"
    VAULT_SECRET               = "746573742d7365637265742d33322d63686172732d6c6f6e672d313233343536"
    VAULT_SALT                 = "deadbeef"
    VAULT_HASH_SALT            = "12345678"
    JWT_SECRET                 = "1234567890123456789012345678901234567890123456789012345678901234"
  }

  depends_on = [module.infrastructure]
}

module "gateway_service" {
  source         = "../../modules/microservice"
  name           = "gateway-service"
  namespace      = module.namespace.name
  image          = "simongarcia01/gateway-service:${var.image_tag}"
  container_port = 8087
  replicas       = var.replicas
  service_type   = "NodePort"
  node_port      = 32087
  resources      = local.resources

  env_vars = {
    REDIS_HOST     = "redis-service"
    REDIS_PORT     = "6379"
    JWT_SECRET     = var.jwt_secret
    JWT_EXPIRATION = "3600000"
  }

  depends_on = [module.infrastructure]
}

module "notification_service" {
  source         = "../../modules/microservice"
  name           = "notification-service"
  namespace      = module.namespace.name
  image          = "simongarcia01/notification-service:${var.image_tag}"
  container_port = 8082
  replicas       = var.replicas
  service_type   = "NodePort"
  node_port      = 32082
  resources      = local.resources

  env_vars = {
    AUTH_API_URL             = "http://auth-service:8180"
    KAFKA_BOOTSTRAP_SERVERS  = "kafka-service:9092"
    MAIL_HOST                = "dummy"
    MAIL_PORT                = "0"
    JWT_SECRET               = var.jwt_secret
    JWT_EXPIRATION           = "3600000"
    QR_SECRET                = var.qr_secret
    QR_EXPIRATION            = "300"
  }

  depends_on = [module.infrastructure]
}

module "promotion_service" {
  source         = "../../modules/microservice"
  name           = "promotion-service"
  namespace      = module.namespace.name
  image          = "simongarcia01/promotion-service:${var.image_tag}"
  container_port = 8088
  replicas       = var.replicas
  service_type   = "ClusterIP"
  resources      = local.resources

  env_vars = {
    SPRING_DATASOURCE_URL                = "jdbc:postgresql://postgres-service:5432/promotion_db"
    SPRING_DATASOURCE_USERNAME           = "admin"
    SPRING_DATASOURCE_PASSWORD           = var.db_password
    SPRING_NEO4J_URI                     = "bolt://neo4j-service:7687"
    SPRING_NEO4J_AUTHENTICATION_USERNAME = "neo4j"
    SPRING_NEO4J_AUTHENTICATION_PASSWORD = var.neo4j_password
    SPRING_KAFKA_BOOTSTRAP_SERVERS       = "kafka-service:9092"
    SPRING_DATA_REDIS_HOST               = "redis-service"
    SPRING_DATA_REDIS_PORT               = "6379"
    JWT_SECRET                           = var.jwt_secret
    JWT_EXPIRATION                       = "3600000"
  }

  depends_on = [module.infrastructure]
}

module "dashboard_service" {
  source         = "../../modules/microservice"
  name           = "dashboard-service"
  namespace      = module.namespace.name
  image          = "simongarcia01/dashboard-service:${var.image_tag}"
  container_port = 8084
  replicas       = var.replicas
  service_type   = "NodePort"
  node_port      = 32084
  resources      = local.resources

  env_vars = {
    SPRING_DATASOURCE_URL             = "jdbc:postgresql://postgres-service:5432/dashboard_db"
    SPRING_DATASOURCE_USERNAME        = "admin"
    SPRING_DATASOURCE_PASSWORD        = var.db_password
    CIRCLEGUARD_PROMOTION_SERVICE_URL = "http://promotion-service:8088"
  }

  depends_on = [module.infrastructure, module.promotion_service]
}

module "form_service" {
  source         = "../../modules/microservice"
  name           = "form-service"
  namespace      = module.namespace.name
  image          = "simongarcia01/form-service:${var.image_tag}"
  container_port = 8086
  replicas       = var.replicas
  service_type   = "NodePort"
  node_port      = 32086
  resources      = local.resources

  env_vars = {
    SPRING_DATASOURCE_URL          = "jdbc:postgresql://postgres-service:5432/form_db"
    SPRING_DATASOURCE_USERNAME     = "admin"
    SPRING_DATASOURCE_PASSWORD     = var.db_password
    SPRING_KAFKA_BOOTSTRAP_SERVERS = "kafka-service:9092"
  }

  depends_on = [module.infrastructure]
}
