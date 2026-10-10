# Log Analytics for the Container Apps environment and Application Insights
# for APIM's logger. Retention is the minimum the workspace allows by default
# for PerGB2018; raise it if your policy requires.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-adrkit-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name_prefix}-adrkit-appi"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}
