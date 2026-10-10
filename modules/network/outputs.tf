output "virtual_network_id" {
  description = "VNet resource ID."
  value       = azurerm_virtual_network.this.id
}

output "container_apps_subnet_id" {
  description = "Subnet for the Container Apps environment."
  value       = azurerm_subnet.aca.id
}

output "apim_integration_subnet_id" {
  description = "Delegated subnet for APIM v2 outbound integration. The NSG association is a dependency of this output, so APIM never integrates into a subnet without its NSG."
  value       = azurerm_subnet.apim.id
  depends_on  = [azurerm_subnet_network_security_group_association.apim]
}

output "private_endpoint_subnet_id" {
  description = "Subnet for private endpoints."
  value       = azurerm_subnet.pe.id
}

output "private_dns_zone_ids" {
  description = "Private DNS zone IDs keyed apim, file, key_vault. Each depends on its VNet link, so a private endpoint registered in it resolves inside the VNet."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
  depends_on  = [azurerm_private_dns_zone_virtual_network_link.this]
}
