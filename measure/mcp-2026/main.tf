# Measurement 4 (ADR-0056 Context fact 5 and clause 6; ADR-0055 clause 15 and
# action item 8; ADR-0056 "Revisit if ... APIM is measured against a
# 2026-07-28 client").
#
# Question: which MCP protocol eras does APIM's "REST API as MCP server" serve?
# The official MCP Inspector CLI drives it with --protocol-era legacy (2025
# era, opened by initialize), modern (2026-07-28, opened by server/discover),
# and auto. See measure.sh.
#
# Shape mirrors modules/apim: a REST API imported from OpenAPI, an API of
# type "mcp" at 2025-09-01-preview created with azapi, and an apis/tools child
# whose operationId is the backing operation's full ARM ID built from the
# service ID. The stub has no backend: an API-level return-response policy
# answers every request, so the tool's result is a fixed JSON object.
#
# Side measurement: the tool references operation "getHello", the OpenAPI
# operationId. If APIM names imported operations differently, the tool's
# create fails (or the tool cannot resolve). That is the skeleton's
# operation-naming assumption (local.mcp_tools in modules/apim).
#
# Public instance, no VNet: the question is protocol, not network. Callers
# need a subscription key, as in the skeleton.

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  location = coalesce(var.location, data.azurerm_resource_group.this.location)
  tags = {
    "adrkit-measure" = var.run_id
    "measurement"    = "mcp-2026"
  }

  # Must equal modules/apim local.mcp_api_version.
  mcp_api_version = "2025-09-01-preview"

  stub_api_name = "stub"
  stub_api_path = "stub"
  mcp_api_name  = "stub-mcp"
  mcp_api_path  = "stub-mcp"
}

resource "random_string" "apim_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_api_management" "this" {
  name                = "${var.name_prefix}-mcp-${random_string.apim_suffix.result}"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  publisher_name      = "adrkit rung-1 measurement"
  publisher_email     = var.publisher_email
  sku_name            = "StandardV2_1"
  tags                = local.tags
}

resource "azurerm_api_management_api" "stub" {
  name                  = local.stub_api_name
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = data.azurerm_resource_group.this.name
  revision              = "1"
  display_name          = "adrkit measurement stub"
  path                  = local.stub_api_path
  protocols             = ["https"]
  subscription_required = true

  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/openapi.json")
  }
}

resource "azurerm_api_management_api_policy" "stub" {
  api_name            = azurerm_api_management_api.stub.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  xml_content         = file("${path.module}/stub-policy.xml")
}

resource "azapi_resource" "mcp" {
  type      = "Microsoft.ApiManagement/service/apis@${local.mcp_api_version}"
  name      = local.mcp_api_name
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      type                 = "mcp"
      displayName          = "adrkit measurement stub (MCP)"
      description          = "REST API as MCP server over the stub's one GET operation."
      path                 = local.mcp_api_path
      protocols            = ["https"]
      subscriptionRequired = true
    }
  }
}

resource "azapi_resource" "mcp_tool" {
  type      = "Microsoft.ApiManagement/service/apis/tools@${local.mcp_api_version}"
  name      = "getHello"
  parent_id = azapi_resource.mcp.id

  body = {
    properties = {
      displayName = "getHello"
      description = "Return a fixed JSON object from the measurement stub."
      operationId = "${azurerm_api_management.this.id}/apis/${local.stub_api_name}/operations/getHello"
    }
  }

  depends_on = [azurerm_api_management_api.stub, azurerm_api_management_api_policy.stub]
}

# All-APIs subscription for the measurement caller (no product_id or api_id).
resource "azurerm_api_management_subscription" "caller" {
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  display_name        = "adrkit measurement caller"
  state               = "active"
  allow_tracing       = false
}
