output "apim_id" {
  description = "APIM service resource ID."
  value       = azurerm_api_management.this.id
}

output "gateway_url" {
  description = "Default gateway URL."
  value       = azurerm_api_management.this.gateway_url
}

output "mcp_base_url" {
  description = "Base URL of the MCP API. measure.sh tries <base>/mcp first (the documented streamable HTTP path), then the base itself, and records which answered."
  value       = "${azurerm_api_management.this.gateway_url}/${local.mcp_api_path}"
}

output "stub_url" {
  description = "Plain REST URL of the stub operation, to check the policy answers outside MCP."
  value       = "${azurerm_api_management.this.gateway_url}/${local.stub_api_path}/hello"
}

output "mcp_api_version" {
  description = "API version used for the MCP resources (mirrors modules/apim)."
  value       = local.mcp_api_version
}

output "subscription_key" {
  description = "Primary key of the measurement subscription (throwaway)."
  value       = azurerm_api_management_subscription.caller.primary_key
  sensitive   = true
}
