# Remote state en Terraform Cloud (gratis).
# Pasos para configurar:
#   1. Crea cuenta en https://app.terraform.io
#   2. Crea una organización llamada "circleguard" (o ajusta el nombre abajo)
#   3. Crea el workspace "circleguard-dev" en modo CLI-driven
#   4. Ejecuta: terraform login
#   5. Luego: terraform init

terraform {
  cloud {
    organization = "circleguard"
    workspaces {
      name = "circleguard-dev"
    }
  }
}
