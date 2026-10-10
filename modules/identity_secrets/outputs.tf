output "sync_identity_id" {
  description = "Resource ID of the sync job's user-assigned identity."
  value       = azurerm_user_assigned_identity.sync.id
}

output "sync_identity_client_id" {
  description = "Client ID of the sync job's identity."
  value       = azurerm_user_assigned_identity.sync.client_id
}

output "key_vault_id" {
  description = "Key Vault resource ID."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.this.vault_uri
}
