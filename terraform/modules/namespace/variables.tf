variable "name" {
  type        = string
  description = "Namespace name (dev, stage, prod)"
}

variable "labels" {
  type        = map(string)
  description = "Additional labels to apply to the namespace"
  default     = {}
}
