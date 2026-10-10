output "writer_job_name" {
  description = "Writer job (performs the swaps, plus a same-client reader)."
  value       = azurerm_container_app_job.role["writer"].name
}

output "reader_job_name" {
  description = "Cross-client reader job."
  value       = azurerm_container_app_job.role["reader"].name
}

output "storage_account_name" {
  description = "Storage account holding the share; results are read back from it."
  value       = azurerm_storage_account.this.name
}

output "share_name" {
  description = "Azure Files share."
  value       = azurerm_storage_share.this.name
}

output "resource_group_name" {
  description = "Resource group (for az containerapp job commands)."
  value       = data.azurerm_resource_group.this.name
}
