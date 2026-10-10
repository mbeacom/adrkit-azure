# Gateway: APIM Standard v2 (ADR-0056 clauses 6, 7, 8, 10).
#
# Order inside one `terraform apply`, enforced with references and depends_on:
#   1. azurerm_api_management.this        created with public access ENABLED
#                                         (Azure requires it at creation).
#   2. azapi_update_resource.outbound     v2 outbound VNet integration.
#   3. azurerm_private_endpoint.gateway   inbound private endpoint + DNS.
#   4. azapi_update_resource.public_network_access
#                                         the second step: publicNetworkAccess
#                                         = Disabled (public_access = false)
#                                         or Enabled (true).
#   5. APIs, tools, policies, product     only after step 4 succeeds, so the
#                                         public window in steps 1-3 never has
#                                         an API attached.
#
# Provider facts (see README "Verified vs unverified"):
#   - Verified (Microsoft Learn, 2026-10-10): public network access can be
#     disabled only after a private endpoint exists and only on an existing
#     instance; Standard v2 supports an inbound private endpoint combined with
#     outbound VNet integration.
#   - Stated by the maintainer, unmeasured here: an ARM update of
#     publicNetworkAccess works on Standard v2. Microsoft Learn still shows
#     only the portal for Standard v2 (REST for classic tiers and Premium v2).
#     ADR-0056 action item 2 is the measurement.
#   - azurerm's public_network_access_enabled is documented as management
#     plane only and required true at creation, so azapi owns the flip and
#     azurerm ignores the attribute afterwards.
#   - Unverified: whether azurerm's virtual_network_type /
#     virtual_network_configuration express v2 outbound integration (their
#     docs describe classic injection). azapi owns integration too.

locals {
  # GA API version used for the two service-level updates. The MCP API and its
  # tools need 2025-09-01-preview or later (verified, Microsoft Learn).
  service_api_version = "2024-05-01"
  mcp_api_version     = "2025-09-01-preview"

  rest_api_name = "adrkit-rest"
  rest_api_path = "adrkit"
  mcp_api_name  = "adrkit-mcp"
  mcp_api_path  = "adrkit-mcp"

  # The portal at "/" is published in private mode only (ADR-0056 clause 8):
  # a browser carries no bearer token, so the public-mode token policy would
  # make it unreachable anyway.
  openapi_source = jsondecode(file("${path.module}/openapi/adrkit-server.placeholder.json"))
  openapi_paths = {
    for p, v in local.openapi_source.paths : p => v if !(var.public_access && p == "/")
  }
  openapi_document = jsonencode(merge(local.openapi_source, { paths = local.openapi_paths }))

  # Operations exposed as MCP tools: the data routes only. Not the portal, not
  # /openapi.json. Each tool names its backing GET operation.
  # TODO(openapi): confirm APIM names imported operations after operationId;
  # if it normalises them, these references must follow.
  mcp_tools = {
    listCorpora  = "List the configured decision corpora and the commit each is served at."
    listRecords  = "List the architecture decision records of one corpus."
    getRecord    = "Get one architecture decision record by id."
    getGraph     = "Get the decision relationship graph of one corpus."
    getQueue     = "Get the architecture review queue of one corpus."
    getIssues    = "Get the corpus findings (lint view) of one corpus."
    getGoverning = "Get the decisions that govern a repository path."
  }

  policy_vars = {
    public_access     = var.public_access
    tenant_id         = coalesce(var.entra_tenant_id, "unused-in-private-mode")
    audience          = coalesce(var.entra_audience, "unused-in-private-mode")
    rate_limit_calls  = var.rate_limit_calls
    rate_limit_period = var.rate_limit_period_seconds
    backend_id        = "adrkit-server"
  }
}

resource "azurerm_api_management" "this" {
  name                = "${var.name_prefix}-adrkit-apim"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "${var.sku}_${var.capacity}"
  tags                = var.tags

  # Must be true at creation. The real switch is step 4 below.
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    # azapi owns these after creation; without this, a plan would try to
    # revert the second step (ADR-0056 clause 7, "a plan that reverts the
    # flip" is listed as a sign the design is wrong).
    ignore_changes = [
      public_network_access_enabled,
      virtual_network_type,
      virtual_network_configuration,
    ]
  }
}

# Step 2: outbound virtual network integration into the delegated subnet.
resource "azapi_update_resource" "outbound" {
  type        = "Microsoft.ApiManagement/service@${local.service_api_version}"
  resource_id = azurerm_api_management.this.id

  body = {
    properties = {
      virtualNetworkType = "External"
      virtualNetworkConfiguration = {
        subnetResourceId = var.integration_subnet_id
      }
    }
  }
}

# Step 3: inbound private endpoint.
resource "azurerm_private_endpoint" "gateway" {
  name                = "${var.name_prefix}-adrkit-apim-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "apim-gateway"
    private_connection_resource_id = azurerm_api_management.this.id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "apim"
    private_dns_zone_ids = [var.apim_dns_zone_id]
  }

  depends_on = [azapi_update_resource.outbound]
}

# Step 4: the second step. Runs on every apply, so changing public_access
# later updates the instance in place; the backend is never recreated.
# Destroying this resource does not revert the property.
resource "azapi_update_resource" "public_network_access" {
  type        = "Microsoft.ApiManagement/service@${local.service_api_version}"
  resource_id = azurerm_api_management.this.id

  body = {
    properties = {
      publicNetworkAccess = var.public_access ? "Enabled" : "Disabled"
    }
  }

  depends_on = [
    azurerm_private_endpoint.gateway,
    azapi_update_resource.outbound,
  ]
}

# ---------------------------------------------------------------------------
# Everything below waits for step 4.
# ---------------------------------------------------------------------------

resource "azurerm_api_management_logger" "appinsights" {
  name                = "appinsights"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  resource_id         = var.application_insights_id

  application_insights {
    instrumentation_key = var.application_insights_key
  }

  depends_on = [azapi_update_resource.public_network_access]
}

resource "azurerm_api_management_backend" "server" {
  name                = local.policy_vars.backend_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  protocol            = "http"
  url                 = var.backend_url
  description         = "adrkit server (ADR-0055 `server` selector) in the internal Container Apps environment."

  depends_on = [azapi_update_resource.public_network_access]
}

resource "azurerm_api_management_product" "adrkit" {
  product_id            = "adrkit"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = var.resource_group_name
  display_name          = "adrkit decisions (read-only)"
  description           = "Read-only access to architecture decision corpora."
  subscription_required = true
  approval_required     = true
  subscriptions_limit   = 1
  published             = true

  depends_on = [azapi_update_resource.public_network_access]
}

resource "azurerm_api_management_api" "rest" {
  name                = local.rest_api_name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  revision            = "1"
  display_name        = "adrkit REST (read-only)"
  # TODO(portal-path): the portal is served under /adrkit/ through APIM, not
  # at the gateway root. Confirm the portal bundle uses relative asset paths,
  # and add a wildcard GET operation for its static assets.
  path                  = local.rest_api_path
  protocols             = ["https"]
  service_url           = var.backend_url
  subscription_required = true

  import {
    content_format = "openapi+json"
    content_value  = local.openapi_document
  }

  depends_on = [azapi_update_resource.public_network_access]
}

resource "azurerm_api_management_api_policy" "rest" {
  api_name            = azurerm_api_management_api.rest.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  xml_content         = templatefile("${path.module}/policies/rest-api.xml.tftpl", local.policy_vars)

  depends_on = [azurerm_api_management_backend.server]
}

resource "azurerm_api_management_product_api" "rest" {
  product_id          = azurerm_api_management_product.adrkit.product_id
  api_name            = azurerm_api_management_api.rest.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
}

# The MCP server: an API of type "mcp" (azurerm has no native resource;
# Microsoft documents azapi_resource). Verified on Microsoft Learn,
# 2026-10-10, at API version 2025-09-01-preview.
resource "azapi_resource" "mcp" {
  type      = "Microsoft.ApiManagement/service/apis@${local.mcp_api_version}"
  name      = local.mcp_api_name
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      type                 = "mcp"
      displayName          = "adrkit decisions (MCP, read-only tools)"
      description          = "REST API as MCP server over the adrkit read-only routes. Tools only."
      path                 = local.mcp_api_path
      protocols            = ["https"]
      subscriptionRequired = true
    }
  }

  depends_on = [azapi_update_resource.public_network_access]
}

resource "azapi_resource" "mcp_tool" {
  for_each = local.mcp_tools

  type      = "Microsoft.ApiManagement/service/apis/tools@${local.mcp_api_version}"
  name      = each.key
  parent_id = azapi_resource.mcp.id

  body = {
    properties = {
      displayName = each.key
      description = each.value
      # Full ARM ID of the backing operation, built from the SERVICE id: the
      # azurerm API resource id carries ";rev=N" and would be malformed here.
      operationId = "${azurerm_api_management.this.id}/apis/${local.rest_api_name}/operations/${each.key}"
    }
  }

  # Tools must be deleted before the operations they reference.
  depends_on = [azurerm_api_management_api.rest]
}

resource "azapi_resource" "mcp_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@${local.mcp_api_version}"
  name      = "policy"
  parent_id = azapi_resource.mcp.id

  body = {
    properties = {
      format = "rawxml"
      value  = templatefile("${path.module}/policies/mcp-api.xml.tftpl", local.policy_vars)
    }
  }
}

resource "azapi_resource" "mcp_product" {
  type      = "Microsoft.ApiManagement/service/products/apis@${local.mcp_api_version}"
  name      = local.mcp_api_name
  parent_id = azurerm_api_management_product.adrkit.id
  body      = {}

  depends_on = [azapi_resource.mcp]
}

# TODO(webhook): ADR-0056 clause 9's public-mode GitHub webhook (one POST that
# verifies X-Hub-Signature-256 in policy and calls ARM jobs/start on the sync
# job, using APIM's managed identity with only
# Microsoft.App/jobs/start/action on that job) is deliberately NOT built.
# ADR-0056 action item 5: measure HMAC verification in APIM policy first, and
# drop the webhook rather than weaken it if it cannot be verified. Until then
# the schedule is the only trigger in both modes.
