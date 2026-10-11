output "resource_group_name" {
  description = "Resource group that holds the deployment."
  value       = azurerm_resource_group.this.name
}

output "apim_gateway_url" {
  description = "APIM default gateway URL. In private mode it resolves to the private endpoint only from networks linked to the privatelink.azure-api.net zone (ADR-0056 clause 10: no private custom domain in the first version)."
  value       = module.apim.gateway_url
}

output "apim_public_network_access" {
  description = "The publicNetworkAccess value the second step sets: Disabled when public_access = false."
  value       = module.apim.public_network_access
}

output "mcp_endpoint_path" {
  description = "Path, under the gateway URL, of the REST-API-as-MCP server (tools only)."
  value       = module.apim.mcp_path
}

output "portal_url" {
  description = "Private mode: URL of the decision portal (no subscription key; reachable from the private network). Null in public mode or when enable_portal = false."
  value       = module.apim.portal_path == null ? null : "${module.apim.gateway_url}/${module.apim.portal_path}/"
}

output "server_internal_fqdn" {
  description = "Internal FQDN of the adrkit server app. Reachable only inside the VNet; APIM is the only intended caller."
  value       = module.container_apps.server_fqdn
}

output "sync_job_id" {
  description = "Resource ID of the corpus sync job (Schedule trigger; can also be started on demand via ARM jobs/start)."
  value       = module.container_apps.sync_job_id
}

output "key_vault_uri" {
  description = "Key Vault URI. Store the GitHub App private key here, out of band, under github_app_private_key_secret_name."
  value       = module.identity_secrets.key_vault_uri
}

output "frontdoor_endpoint_hostname" {
  description = "Front Door endpoint hostname when public_access && enable_waf, otherwise null."
  value       = try(module.frontdoor[0].endpoint_hostname, null)
}

output "apim_name" {
  description = "APIM service name (globally unique; random suffix unless apim_name was set)."
  value       = module.apim.apim_name
}
