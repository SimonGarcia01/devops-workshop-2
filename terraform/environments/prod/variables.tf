variable "image_tag" {
  type        = string
  description = "Docker image tag to deploy (use stable semver, e.g. v1.0.0)"
}

variable "replicas" {
  type        = number
  description = "Number of replicas per microservice"
  default     = 2
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
