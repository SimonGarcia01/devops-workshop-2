# ─────────────────────────────────────────────
# PostgreSQL
# ─────────────────────────────────────────────
resource "kubernetes_config_map_v1" "postgres_init" {
  metadata {
    name      = "postgres-init-script"
    namespace = var.namespace
  }

  data = {
    "init-db.sql" = join("\n", [for db in var.databases : "CREATE DATABASE ${db};"])
  }
}

resource "kubernetes_deployment_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = var.namespace
    labels    = { app = "postgres" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "postgres" } }

    template {
      metadata { labels = { app = "postgres" } }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16"

          port { container_port = 5432 }

          env {
            name  = "POSTGRES_USER"
            value = var.postgres_user
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = var.postgres_password
          }
          env {
            name  = "POSTGRES_DB"
            value = "postgres"
          }

          volume_mount {
            name       = "init-script"
            mount_path = "/docker-entrypoint-initdb.d"
          }
        }

        volume {
          name = "init-script"
          config_map { name = kubernetes_config_map_v1.postgres_init.metadata[0].name }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "postgres-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# ─────────────────────────────────────────────
# Redis
# ─────────────────────────────────────────────
resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = var.namespace
    labels    = { app = "redis" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "redis" } }

    template {
      metadata { labels = { app = "redis" } }
      spec {
        container {
          name  = "redis"
          image = "redis:7.2"
          port { container_port = 6379 }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = "redis-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "redis" }
    port {
      port        = 6379
      target_port = 6379
    }
  }
}

# ─────────────────────────────────────────────
# Zookeeper
# ─────────────────────────────────────────────
resource "kubernetes_deployment_v1" "zookeeper" {
  metadata {
    name      = "zookeeper"
    namespace = var.namespace
    labels    = { app = "zookeeper" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "zookeeper" } }

    template {
      metadata { labels = { app = "zookeeper" } }
      spec {
        container {
          name  = "zookeeper"
          image = "confluentinc/cp-zookeeper:7.6.0"
          port { container_port = 2181 }
          env { name = "ZOOKEEPER_CLIENT_PORT"; value = "2181" }
          env { name = "ZOOKEEPER_TICK_TIME"; value = "2000" }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "zookeeper" {
  metadata {
    name      = "zookeeper-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "zookeeper" }
    port {
      port        = 2181
      target_port = 2181
    }
  }
}

# ─────────────────────────────────────────────
# Kafka
# ─────────────────────────────────────────────
resource "kubernetes_deployment_v1" "kafka" {
  metadata {
    name      = "kafka"
    namespace = var.namespace
    labels    = { app = "kafka" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "kafka" } }

    template {
      metadata { labels = { app = "kafka" } }
      spec {
        container {
          name  = "kafka"
          image = "confluentinc/cp-kafka:7.6.0"
          port { container_port = 9092 }

          env { name = "KAFKA_BROKER_ID";                         value = "1" }
          env { name = "KAFKA_ZOOKEEPER_CONNECT";                 value = "zookeeper-service:2181" }
          env { name = "KAFKA_ADVERTISED_LISTENERS";              value = "PLAINTEXT://kafka-service:9092" }
          env { name = "KAFKA_LISTENERS";                         value = "PLAINTEXT://0.0.0.0:9092" }
          env { name = "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR";  value = "1" }
          env { name = "KAFKA_INTER_BROKER_LISTENER_NAME";        value = "PLAINTEXT" }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment_v1.zookeeper]
}

resource "kubernetes_service_v1" "kafka" {
  metadata {
    name      = "kafka-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "kafka" }
    port {
      port        = 9092
      target_port = 9092
    }
  }
}

# ─────────────────────────────────────────────
# Neo4j
# ─────────────────────────────────────────────
resource "kubernetes_deployment_v1" "neo4j" {
  metadata {
    name      = "neo4j"
    namespace = var.namespace
    labels    = { app = "neo4j" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "neo4j" } }

    template {
      metadata { labels = { app = "neo4j" } }
      spec {
        container {
          name              = "neo4j"
          image             = "neo4j:5.26"
          image_pull_policy = "IfNotPresent"

          port { container_port = 7474 }
          port { container_port = 7687 }

          env { name = "NEO4J_AUTH";                                    value = "neo4j/${var.neo4j_password}" }
          env { name = "NEO4J_PLUGINS";                                 value = "[\"apoc\"]" }
          env { name = "NEO4J_server_config_strict__validation_enabled"; value = "false" }

          readiness_probe {
            http_get {
              path = "/"
              port = "7474"
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "7474"
            }
            initial_delay_seconds = 40
            period_seconds        = 20
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "neo4j" {
  metadata {
    name      = "neo4j-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "neo4j" }
    port {
      name        = "http"
      port        = 7474
      target_port = 7474
    }
    port {
      name        = "bolt"
      port        = 7687
      target_port = 7687
    }
  }
}

# ─────────────────────────────────────────────
# OpenLDAP
# ─────────────────────────────────────────────
resource "kubernetes_deployment_v1" "ldap" {
  metadata {
    name      = "ldap"
    namespace = var.namespace
    labels    = { app = "ldap" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "ldap" } }

    template {
      metadata { labels = { app = "ldap" } }
      spec {
        container {
          name              = "ldap"
          image             = "osixia/openldap:1.5.0"
          image_pull_policy = "IfNotPresent"

          port { container_port = 389 }
          port { container_port = 636 }

          env { name = "LDAP_ORGANISATION";    value = "CircleGuard" }
          env { name = "LDAP_DOMAIN";          value = "circleguard.edu" }
          env { name = "LDAP_ADMIN_PASSWORD";  value = var.ldap_admin_password }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "ldap" {
  metadata {
    name      = "ldap-service"
    namespace = var.namespace
  }
  spec {
    selector = { app = "ldap" }
    port {
      name        = "ldap"
      port        = 389
      target_port = 389
    }
    port {
      name        = "ldaps"
      port        = 636
      target_port = 636
    }
  }
}
