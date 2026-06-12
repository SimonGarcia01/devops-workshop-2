output "postgres_service" {
  value = kubernetes_service_v1.postgres.metadata[0].name
}

output "redis_service" {
  value = kubernetes_service_v1.redis.metadata[0].name
}

output "kafka_service" {
  value = kubernetes_service_v1.kafka.metadata[0].name
}

output "neo4j_service" {
  value = kubernetes_service_v1.neo4j.metadata[0].name
}

output "ldap_service" {
  value = kubernetes_service_v1.ldap.metadata[0].name
}
