output "apim_id" {
  description = "APIM service resource ID."
  value       = azurerm_api_management.this.id
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
  value       = azapi_update_resource.public_network_access.body.properties.publicNetworkAccess
}

output "mcp_path" {
  description = "Path of the MCP server API."
  value       = local.mcp_api_path
}

output "principal_id" {
  description = "APIM system-assigned identity principal ID."
  value       = azurerm_api_management.this.identity[0].principal_id
}
