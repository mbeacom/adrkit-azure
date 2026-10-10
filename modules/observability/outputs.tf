output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_id" {
  description = "Application Insights resource ID."
  value       = azurerm_application_insights.this.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for APIM's logger."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}
