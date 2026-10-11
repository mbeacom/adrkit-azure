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

# avm-res-app-managedenvironment opens an ephemeral azapi resource, which
# provider mocking does not support; stand in for the whole module.
override_module {
  target = module.container_apps
  outputs = {
    environment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-adrkit-rg/providers/Microsoft.App/managedEnvironments/test-adrkit-cae"
    server_fqdn    = "test-adrkit-server.internal.example.eastus2.azurecontainerapps.io"
    server_url     = "https://test-adrkit-server.internal.example.eastus2.azurecontainerapps.io"
    sync_job_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-adrkit-rg/providers/Microsoft.App/jobs/test-adrkit-sync"
  }
}

variables {
  location             = "eastus2"
  name_prefix          = "test"
  apim_publisher_email = "platform@example.com"
  image_tag            = "v1.2.3"
  repos                = [{ key = "adrkit", url = "https://github.com/mbeacom/adrkit" }]
}

run "private_mode_defaults" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "test-adrkit-rg"
    error_message = "The resource group name should default to <name_prefix>-adrkit-rg."
  }

  assert {
    condition     = output.apim_public_network_access == "Disabled"
    error_message = "Private mode must set APIM publicNetworkAccess to Disabled."
  }

  assert {
    condition     = length(module.frontdoor) == 0
    error_message = "Front Door must not exist in private mode."
  }

  assert {
    condition     = output.frontdoor_endpoint_hostname == null
    error_message = "frontdoor_endpoint_hostname must be null without Front Door."
  }

  assert {
    condition     = output.mcp_endpoint_path == "adrkit-mcp"
    error_message = "The MCP API path changed; update README and clients."
  }
}

run "tags_merge_caller_last" {
  command = plan

  variables {
    resource_group_name = "custom-rg"
    tags = {
      workload = "caller-override"
      owner    = "platform"
    }
  }

  assert {
    condition     = azurerm_resource_group.this.name == "custom-rg"
    error_message = "An explicit resource_group_name must be used as given."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["managed-by"] == "terraform"
    error_message = "Default tags must be applied."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["workload"] == "caller-override" && azurerm_resource_group.this.tags["owner"] == "platform"
    error_message = "Caller tags must be merged last, overriding defaults."
  }
}

run "public_mode_without_waf" {
  command = plan

  variables {
    public_access   = true
    enable_portal   = false
    entra_tenant_id = "11111111-1111-1111-1111-111111111111"
    entra_audience  = "api://adrkit"
  }

  assert {
    condition     = output.apim_public_network_access == "Enabled"
    error_message = "Public mode must leave APIM publicNetworkAccess Enabled."
  }

  assert {
    condition     = length(module.frontdoor) == 0
    error_message = "Front Door is opt-in (enable_waf)."
  }
}

run "public_mode_with_waf" {
  command = plan

  variables {
    public_access   = true
    enable_portal   = false
    enable_waf      = true
    entra_tenant_id = "11111111-1111-1111-1111-111111111111"
    entra_audience  = "api://adrkit"
  }

  assert {
    condition     = length(module.frontdoor) == 1
    error_message = "public_access && enable_waf must create Front Door."
  }
}
