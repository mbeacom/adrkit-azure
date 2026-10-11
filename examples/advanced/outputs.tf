output "frontdoor_endpoint_hostname" {
  description = "Front Door endpoint hostname: the public entry point."
  value       = module.adrkit.frontdoor_endpoint_hostname
}

output "apim_gateway_url" {
  description = "APIM gateway URL."
  value       = module.adrkit.apim_gateway_url
}

output "mcp_endpoint_path" {
  description = "Path of the MCP server under the gateway URL."
  value       = module.adrkit.mcp_endpoint_path
}

output "key_vault_uri" {
  description = "Key Vault URI. Store the GitHub App private key here, out of band, under github_app_private_key_secret_name."
  value       = module.adrkit.key_vault_uri
}
