variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy infrastructure into"
}

variable "databases" {
  type        = list(string)
  description = "List of PostgreSQL databases to create on init"
  default     = ["auth_db", "identity_db", "promotion_db", "dashboard_db", "form_db"]
}

variable "postgres_user" {
  type        = string
  description = "PostgreSQL admin username"
  default     = "admin"
}

variable "postgres_password" {
  type        = string
  description = "PostgreSQL admin password"
  sensitive   = true
}

variable "neo4j_password" {
  type        = string
  description = "Neo4j admin password"
  sensitive   = true
}

variable "ldap_admin_password" {
  type        = string
  description = "OpenLDAP admin password"
  sensitive   = true
}
