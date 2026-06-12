variable "kube_context" {
  type        = string
  description = "kubectl context to use (minikube for local, default for k3s/GCP)"
  default     = "default"
}

variable "image_tag" {
  type        = string
  description = "Docker image tag to deploy (use release candidates, e.g. v1.0.0-rc1)"
}

variable "replicas" {
  type        = number
  description = "Number of replicas per microservice"
  default     = 1
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "neo4j_password" {
  type      = string
  sensitive = true
}

variable "ldap_password" {
  type      = string
  sensitive = true
}

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "qr_secret" {
  type      = string
  sensitive = true
}
