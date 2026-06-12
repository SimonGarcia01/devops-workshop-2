output "namespace" {
  value = module.namespace.name
}

output "auth_service" {
  value = module.auth_service.service_name
}

output "gateway_service" {
  value = module.gateway_service.service_name
}

output "promotion_service" {
  value = module.promotion_service.service_name
}

output "dashboard_service" {
  value = module.dashboard_service.service_name
}

output "form_service" {
  value = module.form_service.service_name
}
