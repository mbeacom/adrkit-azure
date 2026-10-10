# Gateway: APIM Standard v2 (ADR-0056 clauses 6, 7, 8, 10).
#
# Order inside one `terraform apply`, enforced with references and depends_on:
#   1. azurerm_api_management.this        created with public access ENABLED
#                                         (Azure requires it at creation).
#   2. azapi_update_resource.outbound     v2 outbound VNet integration.
#   3. azurerm_private_endpoint.gateway   inbound private endpoint + DNS.
#   4. The publicNetworkAccess second step, as ONE of two resources, so the
#      order relative to the policies follows the direction of the change:
#        public_access = false: disable_public_access runs BEFORE the APIs,
#          policies, and product bindings (they depend on it). A first apply
#          never has an API attached during the public window of steps 1-3,
#          and a true -> false flip closes the gateway before the public-mode
#          policies are relaxed.
#        public_access = true: enable_public_access runs AFTER the policies,
#          catch-all operations, diagnostics, and product bindings (it
#          depends on them). A false -> true flip applies Entra validation
#          and rate limiting to the already-attached APIs before the gateway
#          opens.
#      Only one of the two exists at a time (count). Removing the other is a
#      no-op: destroying an azapi_update_resource does not revert anything.
#   5. Product bindings depend on the policies in both modes, so product
#      subscribers never reach an API before its policy is in place.
#
# Residual window (public_access = true, FIRST apply only): the instance is
# public from creation, so between an API's creation and its policy's, the
# API exists without its policy. Every API requires a subscription key and is
# bound to the product only after its policy, so in that window it answers
# only to APIM's built-in all-access subscription key (an administrator
# credential). Unmeasured; see README.
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

# APIM names are global (they become <name>.azure-api.net). A stable random
# suffix avoids collisions; var.apim_name overrides it.
resource "random_string" "apim_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_api_management" "this" {
  name                = coalesce(var.apim_name, "${var.name_prefix}-adrkit-apim-${random_string.apim_suffix.result}")
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

# Step 4, private mode: close the gateway BEFORE anything is attached or
# relaxed. Everything below that is attached to the instance depends on it.
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

# Step 4, public mode: open the gateway only AFTER the public-mode policies,
# the catch-all method guard, diagnostics, and product bindings exist.
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
    azurerm_api_management_api_policy.rest,
    azurerm_api_management_api_operation.method_guard,
    azapi_resource.mcp_policy,
    azurerm_api_management_product_api.rest,
    azapi_resource.mcp_product,
    azurerm_api_management_diagnostic.service,
  ]
}

# ---------------------------------------------------------------------------
# Everything below waits for disable_public_access in private mode (that
# resource has count = 0 in public mode, so the dependency is then empty).
# ---------------------------------------------------------------------------

resource "azurerm_api_management_logger" "appinsights" {
  name                = "appinsights"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  resource_id         = var.application_insights_id

  application_insights {
    instrumentation_key = var.application_insights_key
  }

  depends_on = [azapi_update_resource.disable_public_access, azurerm_private_endpoint.gateway]
}

# The logger alone sends nothing; this service-wide diagnostic binds it.
# Body logging is OFF (0 bytes) for every API, the MCP API included: logging
# bodies would buffer streamed responses (ADR-0056 clause 6). No API-level
# diagnostic overrides it.
resource "azurerm_api_management_diagnostic" "service" {
  identifier               = "applicationinsights"
  api_management_name      = azurerm_api_management.this.name
  resource_group_name      = var.resource_group_name
  api_management_logger_id = azurerm_api_management_logger.appinsights.id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = false
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes = 0
  }

  frontend_response {
    body_bytes = 0
  }

  backend_request {
    body_bytes = 0
  }

  backend_response {
    body_bytes = 0
  }
}

resource "azurerm_api_management_backend" "server" {
  name                = local.policy_vars.backend_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  protocol            = "http"
  url                 = var.backend_url
  description         = "adrkit server (ADR-0055 `server` selector) in the internal Container Apps environment."

  depends_on = [azapi_update_resource.disable_public_access, azurerm_private_endpoint.gateway]
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

  depends_on = [azapi_update_resource.disable_public_access, azurerm_private_endpoint.gateway]
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

  depends_on = [azapi_update_resource.disable_public_access, azurerm_private_endpoint.gateway]
}

resource "azurerm_api_management_api_policy" "rest" {
  api_name            = azurerm_api_management_api.rest.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  xml_content         = templatefile("${path.module}/policies/rest-api.xml.tftpl", local.policy_vars)

  depends_on = [
    azurerm_api_management_backend.server,
    azapi_update_resource.disable_public_access,
  ]
}

# Method guard, part 1. APIM matches a request to an operation before any
# API-scope policy runs, and an unmatched method fails as 404
# (OperationNotFound), so the API policy's 405 branch alone never fires.
# These wildcard ("/*", documented on Microsoft Learn) operations match every
# non-GET method so the request reaches the API policy, whose guard answers
# 405 with "Allow: GET, HEAD". HEAD is not listed: it stays a read.
# None of these is ever forwarded to the backend, and none is an MCP tool.
resource "azurerm_api_management_api_operation" "method_guard" {
  for_each = toset(["POST", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE"])

  operation_id        = "method-guard-${lower(each.key)}"
  api_name            = azurerm_api_management_api.rest.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "Reject ${each.key} (read-only API)"
  method              = each.key
  url_template        = "/*"
  description         = "Catch-all so the API policy can answer 405; never forwarded."

  response {
    status_code = 405
  }
}

resource "azurerm_api_management_product_api" "rest" {
  product_id          = azurerm_api_management_product.adrkit.product_id
  api_name            = azurerm_api_management_api.rest.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  # Subscribers reach the API only once its policy and method guard exist.
  depends_on = [
    azurerm_api_management_api_policy.rest,
    azurerm_api_management_api_operation.method_guard,
  ]
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

  depends_on = [azapi_update_resource.disable_public_access, azurerm_private_endpoint.gateway]
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

  depends_on = [azapi_update_resource.disable_public_access]
}

resource "azapi_resource" "mcp_product" {
  type      = "Microsoft.ApiManagement/service/products/apis@${local.mcp_api_version}"
  name      = local.mcp_api_name
  parent_id = azurerm_api_management_product.adrkit.id
  body      = {}

  depends_on = [azapi_resource.mcp, azapi_resource.mcp_policy]
}

# TODO(webhook): ADR-0056 clause 9's public-mode GitHub webhook (one POST that
# verifies X-Hub-Signature-256 in policy and calls ARM jobs/start on the sync
# job, using APIM's managed identity with only
# Microsoft.App/jobs/start/action on that job) is deliberately NOT built.
# ADR-0056 action item 5: measure HMAC verification in APIM policy first, and
# drop the webhook rather than weaken it if it cannot be verified. Until then
# the schedule is the only trigger in both modes.
