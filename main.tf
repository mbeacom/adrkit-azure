# Composition root for the adrkit Azure deployment (ADR-0056).
#
# Order of the one apply, as Terraform derives it from references:
#   network -> observability -> identity_secrets, storage
#   -> container_apps (internal environment, server app, sync job)
#   -> apim (service, private endpoint, outbound integration,
#            publicNetworkAccess second step, then APIs and policies)
#   -> frontdoor (only when public_access && enable_waf)

locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.name_prefix}-adrkit-rg")

  tags = merge(
    {
      "managed-by" = "terraform"
      "workload"   = "adrkit"
      "source"     = "github.com/mbeacom/adrkit-azure"
    },
    var.tags,
  )
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "./modules/network"

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.address_space
  tags                = local.tags
}

module "observability" {
  source = "./modules/observability"

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "identity_secrets" {
  source = "./modules/identity_secrets"

  name_prefix                = var.name_prefix
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  key_vault_dns_zone_id      = module.network.private_dns_zone_ids["key_vault"]
  tags                       = local.tags
}

module "storage" {
  source = "./modules/storage"

  name_prefix                = var.name_prefix
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  file_dns_zone_id           = module.network.private_dns_zone_ids["file"]
  tags                       = local.tags
}

module "container_apps" {
  source = "./modules/container_apps"

  name_prefix                = var.name_prefix
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  infrastructure_subnet_id   = module.network.container_apps_subnet_id
  virtual_network_id         = module.network.virtual_network_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  server_image = "${var.image_repository}:${var.image_tag}"
  sync_image   = var.sync_image
  sync_cron    = var.sync_cron
  repos        = var.repos

  storage_account_name       = module.storage.storage_account_name
  storage_account_access_key = module.storage.primary_access_key
  share_name                 = module.storage.share_name

  sync_identity_id                   = module.identity_secrets.sync_identity_id
  sync_identity_client_id            = module.identity_secrets.sync_identity_client_id
  key_vault_uri                      = module.identity_secrets.key_vault_uri
  github_app_private_key_secret_name = var.github_app_private_key_secret_name

  tags = local.tags
}

module "apim" {
  source = "./modules/apim"

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = var.apim_sku
  capacity            = var.apim_capacity
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email

  public_access              = var.public_access
  integration_subnet_id      = module.network.apim_integration_subnet_id
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  apim_dns_zone_id           = module.network.private_dns_zone_ids["apim"]
  application_insights_id    = module.observability.application_insights_id
  application_insights_key   = module.observability.application_insights_instrumentation_key

  backend_url = module.container_apps.server_url

  entra_tenant_id           = var.entra_tenant_id
  entra_audience            = var.entra_audience
  rate_limit_calls          = var.rate_limit_calls
  rate_limit_period_seconds = var.rate_limit_period_seconds

  tags = local.tags
}

module "frontdoor" {
  source = "./modules/frontdoor"
  count  = var.public_access && var.enable_waf ? 1 : 0

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  apim_id             = module.apim.apim_id
  apim_gateway_host   = module.apim.gateway_hostname
  tags                = local.tags
}
