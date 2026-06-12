variable "kube_context" {
  type        = string
  description = "kubectl context to use (minikube for local, default for k3s/GCP)"
  default     = "default"
}

variable "image_tag" {
  type        = string
  description = "Docker image tag to deploy"
  default     = "latest"
}

variable "replicas" {
  type        = number
  description = "Number of replicas per microservice"
  default     = 1
}

variable "db_password" {
  type        = string
  description = "PostgreSQL password"
  sensitive   = true
  default     = "password"
}

variable "neo4j_password" {
  type        = string
  description = "Neo4j password"
  sensitive   = true
  default     = "password"
}

variable "ldap_password" {
  type        = string
  description = "LDAP admin password"
  sensitive   = true
  default     = "admin"
}

variable "jwt_secret" {
  type        = string
  description = "Shared JWT signing secret"
  sensitive   = true
  default     = "my-super-secret-dev-key-32-chars-long-12345678"
}

variable "qr_secret" {
  type        = string
  description = "QR token signing secret"
  sensitive   = true
  default     = "my-qr-secret-key-for-dev-1234567890"
}
