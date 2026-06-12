output "service_name" {
  value       = kubernetes_service_v1.this.metadata[0].name
  description = "Kubernetes service name"
}

output "deployment_name" {
  value       = kubernetes_deployment_v1.this.metadata[0].name
  description = "Kubernetes deployment name"
}
