variable "name" {
  type        = string
  description = "Service name (e.g. auth-service)"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy into"
}

variable "image" {
  type        = string
  description = "Full Docker image reference (e.g. simongarcia01/auth-service:latest)"
}

variable "container_port" {
  type        = number
  description = "Port the container listens on"
}

variable "replicas" {
  type        = number
  description = "Number of pod replicas"
  default     = 1
}

variable "service_type" {
  type        = string
  description = "Kubernetes service type: ClusterIP or NodePort"
  default     = "ClusterIP"
}

variable "node_port" {
  type        = number
  description = "NodePort value (30000-32767), required when service_type = NodePort"
  default     = null
  nullable    = true
}

variable "env_vars" {
  type        = map(string)
  description = "Environment variables to inject into the container"
  default     = {}
}

variable "resources" {
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
  })
  description = "Container resource requests and limits"
  default = {
    requests_cpu    = "100m"
    requests_memory = "256Mi"
    limits_cpu      = "500m"
    limits_memory   = "512Mi"
  }
}
