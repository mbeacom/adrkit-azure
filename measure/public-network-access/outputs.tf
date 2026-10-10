output "apim_id" {
  description = "APIM service resource ID (read with az rest at the same API version the flip uses)."
  value       = azurerm_api_management.this.id
}

output "apim_name" {
  description = "APIM service name."
  value       = azurerm_api_management.this.name
}

output "gateway_hostname" {
  description = "Default gateway host name, probed from outside the VNet."
  value       = trimprefix(azurerm_api_management.this.gateway_url, "https://")
}

output "service_api_version" {
  description = "API version of the azapi flip (mirrors modules/apim)."
  value       = local.service_api_version
}

output "location" {
  description = "Region the instance was created in."
  value       = local.location
}

output "publisher_email" {
  description = "Publisher email, passed on to the outbound-integration plan so it does not show a spurious diff."
  value       = azurerm_api_management.this.publisher_email
}

output "publisher_name" {
  description = "Publisher name, passed on to the outbound-integration plan."
  value       = azurerm_api_management.this.publisher_name
}

output "integration_subnet_id" {
  description = "Delegated subnet the outbound integration points at."
  value       = module.network.apim_integration_subnet_id
}

output "expected_public_network_access" {
  description = "What the flip in this apply set."
  value       = var.public_access ? "Enabled" : "Disabled"
}
