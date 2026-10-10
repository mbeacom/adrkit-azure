output "apim_id" {
  description = "APIM service resource ID."
  value       = azurerm_api_management.this.id
}

output "apim_name" {
  description = "APIM service name (global; includes the random suffix unless apim_name was set)."
  value       = azurerm_api_management.this.name
}

output "gateway_url" {
  description = "Default gateway URL."
  value       = azurerm_api_management.this.gateway_url
}

output "gateway_hostname" {
  description = "Default gateway host name."
  value       = trimprefix(azurerm_api_management.this.gateway_url, "https://")
}

output "public_network_access" {
  description = "Value set by the second step."
  value       = var.public_access ? azapi_update_resource.enable_public_access[0].body.properties.publicNetworkAccess : azapi_update_resource.disable_public_access[0].body.properties.publicNetworkAccess
}

output "mcp_path" {
  description = "Path of the MCP server API."
  value       = local.mcp_api_path
}

output "principal_id" {
  description = "APIM system-assigned identity principal ID."
  value       = azurerm_api_management.this.identity[0].principal_id
}
