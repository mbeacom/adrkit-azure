# Plan-only: nothing here contacts Azure. See tests/README.md for why azapi is
# a real provider configured so it cannot authenticate, and why
# module.container_apps is overridden in root-level runs.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

mock_provider "random" {}

provider "azapi" {
  subscription_id            = "00000000-0000-0000-0000-000000000000"
  tenant_id                  = "00000000-0000-0000-0000-000000000001"
  client_id                  = "00000000-0000-0000-0000-000000000003"
  client_secret              = "not-a-secret"
  use_cli                    = false
  use_msi                    = false
  use_oidc                   = false
  use_aks_workload_identity  = false
  skip_provider_registration = true
  enable_preflight           = false
}

# These runs plan modules/apim on its own, so its resources can be asserted
# directly. Inputs are plausible stand-ins for the other modules' outputs.
variables {
  name_prefix                = "test"
  location                   = "eastus2"
  resource_group_name        = "test-adrkit-rg"
  apim_name                  = null
  sku                        = "StandardV2"
  capacity                   = 1
  publisher_name             = "adrkit"
  publisher_email            = "platform@example.com"
  public_access              = false
  integration_subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-adrkit-rg/providers/Microsoft.Network/virtualNetworks/test-adrkit-vnet/subnets/snet-apim-integration"
  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-adrkit-rg/providers/Microsoft.Network/virtualNetworks/test-adrkit-vnet/subnets/snet-private-endpoints"
  apim_dns_zone_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-adrkit-rg/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
  application_insights_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-adrkit-rg/providers/Microsoft.Insights/components/test-adrkit-appi"
  application_insights_key   = "00000000-0000-0000-0000-000000000004"
  backend_url                = "https://test-adrkit-server.internal.example.eastus2.azurecontainerapps.io"
  entra_tenant_id            = null
  entra_audience             = null
  rate_limit_calls           = 120
  rate_limit_period_seconds  = 60
  enable_portal              = true
  portal_rate_limit_calls    = 300
  tags                       = {}
}

run "apim_private_mode" {
  command = plan

  module {
    source = "./modules/apim"
  }

  assert {
    condition     = azurerm_api_management.this.sku_name == "StandardV2_1"
    error_message = "sku_name must be <sku>_<capacity>."
  }

  assert {
    condition     = length(azapi_update_resource.disable_public_access) == 1 && length(azapi_update_resource.enable_public_access) == 0
    error_message = "Private mode must use the disable_public_access step only."
  }

  assert {
    condition     = azapi_update_resource.disable_public_access[0].body.properties.publicNetworkAccess == "Disabled"
    error_message = "The private-mode second step must set publicNetworkAccess to Disabled."
  }

  assert {
    condition     = !strcontains(azurerm_api_management_api_policy.rest.xml_content, "validate-azure-ad-token")
    error_message = "Private mode must not add Entra token validation."
  }

  assert {
    condition     = strcontains(azurerm_api_management_api_policy.rest.xml_content, "code=\"405\"")
    error_message = "The REST policy must keep the 405 method guard (read-only invariant)."
  }

  # The portal is its own keyless API, in private mode only, and GET only.
  assert {
    condition     = length(azurerm_api_management_api.portal) == 1 && azurerm_api_management_api.portal[0].subscription_required == false
    error_message = "Private mode with enable_portal must publish the keyless portal API."
  }

  assert {
    condition     = azurerm_api_management_api_operation.portal_root[0].method == "GET" && azurerm_api_management_api_operation.portal_files[0].method == "GET"
    error_message = "The portal's content operations must be GET."
  }

  assert {
    condition     = toset(keys(azurerm_api_management_api_operation.portal_method_guard)) == toset(["POST", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE"])
    error_message = "The portal API needs the same catch-all method guard as the REST API."
  }

  assert {
    condition     = strcontains(azurerm_api_management_api_policy.portal[0].xml_content, "code=\"405\"")
    error_message = "The portal policy must keep the 405 method guard (read-only invariant)."
  }
}

run "apim_public_mode" {
  command = plan

  module {
    source = "./modules/apim"
  }

  variables {
    public_access   = true
    enable_portal   = false
    entra_tenant_id = "11111111-1111-1111-1111-111111111111"
    entra_audience  = "api://adrkit"
  }

  assert {
    condition     = length(azapi_update_resource.disable_public_access) == 0 && length(azapi_update_resource.enable_public_access) == 1
    error_message = "Public mode must use the enable_public_access step only."
  }

  assert {
    condition     = strcontains(azurerm_api_management_api_policy.rest.xml_content, "validate-azure-ad-token") && strcontains(azurerm_api_management_api_policy.rest.xml_content, "rate-limit-by-key")
    error_message = "Public mode must validate Entra tokens and rate-limit on the REST API."
  }

  assert {
    condition     = strcontains(azapi_resource.mcp_policy.body.properties.value, "validate-azure-ad-token") && strcontains(azapi_resource.mcp_policy.body.properties.value, "rate-limit-by-key")
    error_message = "Public mode must validate Entra tokens and rate-limit on the MCP API."
  }

  assert {
    condition     = strcontains(azurerm_api_management_api_policy.rest.xml_content, "11111111-1111-1111-1111-111111111111")
    error_message = "The token policy must name the configured tenant."
  }

  assert {
    condition     = length(azurerm_api_management_api.portal) == 0 && length(azurerm_api_management_api_operation.portal_method_guard) == 0
    error_message = "Public mode must never create the keyless portal (ADR-0056 clause 8)."
  }
}

# Read-only invariant (SECURITY.md): only GET is published and forwarded.
run "apim_read_only_surface" {
  command = plan

  module {
    source = "./modules/apim"
  }

  assert {
    condition = alltrue(flatten([
      for p, ops in jsondecode(azurerm_api_management_api.rest.import[0].content_value).paths : [
        for m, _ in ops : contains(["get", "parameters", "summary", "description"], lower(m))
      ]
    ]))
    error_message = "The imported OpenAPI document must publish GET operations only."
  }

  assert {
    condition     = toset(keys(azurerm_api_management_api_operation.method_guard)) == toset(["POST", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE"])
    error_message = "Every non-GET method needs a catch-all operation so the policy can answer 405."
  }

  assert {
    condition     = alltrue([for k, op in azurerm_api_management_api_operation.method_guard : op.url_template == "/*"])
    error_message = "Method-guard operations must be catch-alls."
  }

  # Each MCP tool must name a GET operation of the imported document.
  assert {
    condition = alltrue([
      for name, _ in azapi_resource.mcp_tool : contains(flatten([
        for p, ops in jsondecode(azurerm_api_management_api.rest.import[0].content_value).paths : [
          for m, op in ops : op.operationId if lower(m) == "get"
        ]
      ]), name)
    ])
    error_message = "Every MCP tool must map to a GET operation."
  }

  assert {
    condition     = length(setintersection(toset(keys(azapi_resource.mcp_tool)), toset(["getPortal", "getOpenApi", "getHealth"]))) == 0
    error_message = "The portal, /openapi.json, and /healthz are not MCP tools."
  }

  # The keyed REST API never imports /healthz or the portal routes.
  assert {
    condition = alltrue([
      for p in keys(jsondecode(azurerm_api_management_api.rest.import[0].content_value).paths) :
      p != "/healthz" && p != "/" && !startswith(p, "/portal/")
    ])
    error_message = "The REST API must not import /healthz or the portal routes."
  }
}

# No body reads: diagnostics must log 0 bytes of every body (streaming).
run "apim_diagnostics_log_no_bodies" {
  command = plan

  module {
    source = "./modules/apim"
  }

  assert {
    condition = (
      azurerm_api_management_diagnostic.service.frontend_request[0].body_bytes == 0 &&
      azurerm_api_management_diagnostic.service.frontend_response[0].body_bytes == 0 &&
      azurerm_api_management_diagnostic.service.backend_request[0].body_bytes == 0 &&
      azurerm_api_management_diagnostic.service.backend_response[0].body_bytes == 0
    )
    error_message = "Diagnostics must log 0 body bytes."
  }

  assert {
    # XML comments are stripped first: the template's own comment names the
    # property it promises not to read.
    condition     = !strcontains(replace(azurerm_api_management_api_policy.rest.xml_content, "/(?s)<!--.*?-->/", ""), "Response.Body") && !strcontains(replace(azapi_resource.mcp_policy.body.properties.value, "/(?s)<!--.*?-->/", ""), "Response.Body")
    error_message = "No policy may read the response body."
  }
}

run "apim_backend_url_rejects_http" {
  command = plan

  module {
    source = "./modules/apim"
  }

  variables {
    backend_url = "http://test-adrkit-server.internal.example.eastus2.azurecontainerapps.io"
  }

  expect_failures = [var.backend_url]
}
