# Measurement 1 (ADR-0056 action item 2, first half; clause 7).
#
# Question: does an ARM update of publicNetworkAccess, made through
# azapi_update_resource exactly as modules/apim makes it, take effect on an
# existing APIM Standard v2 instance that has an inbound private endpoint, in
# both directions (Disabled -> Enabled -> Disabled)? And does a plan after each
# apply stay empty (no "plan that reverts the flip")?
#
# The network comes from modules/network unchanged. The APIM resources below
# MIRROR modules/apim steps 1-4 (same resource types, API version, bodies,
# count-gated disable/enable pair, and lifecycle.ignore_changes). They are not
# a module call, because modules/apim also builds the MCP preview API, a
# backend, policies, and a logger, and a failure in any of those would
# confound this result. Keep the two in sync: if modules/apim changes its
# flip, change it here too, or this measurement stops measuring the skeleton.
#
# What this root does NOT measure: clause 7's ordering of API attachment
# around the flip (no API is attached here).

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  location = coalesce(var.location, data.azurerm_resource_group.this.location)
  tags = {
    "adrkit-measure" = var.run_id
    "measurement"    = "public-network-access"
  }

  # Must equal modules/apim local.service_api_version.
  service_api_version = "2024-05-01"
}

module "network" {
  source = "../../modules/network"

  name_prefix         = var.name_prefix
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = var.address_space
  tags                = local.tags
}

resource "random_string" "apim_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Mirrors modules/apim azurerm_api_management.this (step 1).
resource "azurerm_api_management" "this" {
  name                = "${var.name_prefix}-apim-${random_string.apim_suffix.result}"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  publisher_name      = "adrkit rung-1 measurement"
  publisher_email     = var.publisher_email
  sku_name            = "StandardV2_1"
  tags                = local.tags

  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      public_network_access_enabled,
      virtual_network_type,
      virtual_network_configuration,
    ]
  }
}

# Mirrors modules/apim azapi_update_resource.outbound (step 2).
resource "azapi_update_resource" "outbound" {
  type        = "Microsoft.ApiManagement/service@${local.service_api_version}"
  resource_id = azurerm_api_management.this.id

  body = {
    properties = {
      virtualNetworkType = "External"
      virtualNetworkConfiguration = {
        subnetResourceId = module.network.apim_integration_subnet_id
      }
    }
  }
}

# Mirrors modules/apim azurerm_private_endpoint.gateway (step 3).
resource "azurerm_private_endpoint" "gateway" {
  name                = "${var.name_prefix}-apim-pe"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = module.network.private_endpoint_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "apim-gateway"
    private_connection_resource_id = azurerm_api_management.this.id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "apim"
    private_dns_zone_ids = [module.network.private_dns_zone_ids["apim"]]
  }

  depends_on = [azapi_update_resource.outbound]
}

# Mirrors modules/apim azapi_update_resource.disable_public_access (step 4,
# private mode).
resource "azapi_update_resource" "disable_public_access" {
  count = var.public_access ? 0 : 1

  type        = "Microsoft.ApiManagement/service@${local.service_api_version}"
  resource_id = azurerm_api_management.this.id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }

  depends_on = [
    azurerm_private_endpoint.gateway,
    azapi_update_resource.outbound,
  ]
}

# Mirrors modules/apim azapi_update_resource.enable_public_access (step 4,
# public mode). modules/apim also depends on its policies here; there are none
# in this root.
resource "azapi_update_resource" "enable_public_access" {
  count = var.public_access ? 1 : 0

  type        = "Microsoft.ApiManagement/service@${local.service_api_version}"
  resource_id = azurerm_api_management.this.id

  body = {
    properties = {
      publicNetworkAccess = "Enabled"
    }
  }

  depends_on = [
    azurerm_private_endpoint.gateway,
    azapi_update_resource.outbound,
  ]
}
