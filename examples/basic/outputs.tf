output "apim_gateway_url" {
  description = "APIM gateway URL; resolves to the private endpoint only from networks linked to the privatelink.azure-api.net zone."
  value       = module.adrkit.apim_gateway_url
}

output "mcp_endpoint_path" {
  description = "Path of the MCP server under the gateway URL."
  value       = module.adrkit.mcp_endpoint_path
}

output "key_vault_uri" {
  description = "Key Vault URI (store the GitHub App private key here, out of band, if you add private repositories)."
  value       = module.adrkit.key_vault_uri
}
