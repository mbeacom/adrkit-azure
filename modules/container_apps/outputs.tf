output "environment_id" {
  description = "Container Apps environment resource ID."
  value       = module.environment.resource_id
}

output "server_fqdn" {
  description = "Internal FQDN of the server app."
  value       = azurerm_container_app.server.ingress[0].fqdn
}

output "server_url" {
  description = "HTTPS URL APIM uses as the backend. Depends on the private DNS link so APIM never points at a name it cannot resolve."
  value       = "https://${azurerm_container_app.server.ingress[0].fqdn}"
  depends_on  = [azurerm_private_dns_a_record.environment_wildcard, azurerm_private_dns_zone_virtual_network_link.environment]
}

output "sync_job_id" {
  description = "Sync job resource ID."
  value       = module.sync_job.resource_id
}
