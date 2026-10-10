output "storage_account_id" {
  description = "Storage account resource ID."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.this.name
}

output "primary_access_key" {
  description = "Account key, for the Container Apps environment storage definitions only."
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "share_name" {
  description = "Name of the corpora share. Depends on the private endpoint so nothing mounts it before the endpoint exists."
  value       = azurerm_storage_share.corpora.name
  depends_on  = [azurerm_private_endpoint.file]
}
