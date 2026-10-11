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

run "image_tag_rejects_latest" {
  command = plan
  variables {
    image_tag = "latest"
  }
  expect_failures = [var.image_tag]
}

run "image_tag_rejects_moving_major" {
  command = plan
  variables {
    image_tag = "v0"
  }
  expect_failures = [var.image_tag]
}

run "image_tag_rejects_short_digest" {
  command = plan
  variables {
    image_tag = "v1.2.3@sha256:abc"
  }
  expect_failures = [var.image_tag]
}

run "image_tag_accepts_digest" {
  command = plan
  variables {
    image_tag = "v1.2.3@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
}

run "name_prefix_rejects_uppercase" {
  command = plan
  variables {
    name_prefix = "Acme"
  }
  expect_failures = [var.name_prefix]
}

run "name_prefix_rejects_too_long" {
  command = plan
  variables {
    name_prefix = "abcdefghijk"
  }
  expect_failures = [var.name_prefix]
}

run "location_rejects_empty" {
  command = plan
  variables {
    location = " "
  }
  expect_failures = [var.location]
}

run "resource_group_name_rejects_trailing_period" {
  command = plan
  variables {
    resource_group_name = "my-rg."
  }
  expect_failures = [var.resource_group_name]
}

run "apim_sku_rejects_basic_v2" {
  command = plan
  variables {
    apim_sku = "BasicV2"
  }
  expect_failures = [var.apim_sku]
}

run "apim_name_rejects_leading_digit" {
  command = plan
  variables {
    apim_name = "1apim"
  }
  expect_failures = [var.apim_name]
}

run "apim_capacity_rejects_zero" {
  command = plan
  variables {
    apim_capacity = 0
  }
  expect_failures = [var.apim_capacity]
}

run "apim_capacity_rejects_fraction" {
  command = plan
  variables {
    apim_capacity = 1.5
  }
  expect_failures = [var.apim_capacity]
}

run "apim_publisher_name_rejects_blank" {
  command = plan
  variables {
    apim_publisher_name = "  "
  }
  expect_failures = [var.apim_publisher_name]
}

run "apim_publisher_email_rejects_non_email" {
  command = plan
  variables {
    apim_publisher_email = "platform"
  }
  expect_failures = [var.apim_publisher_email]
}

run "image_repository_rejects_tag" {
  command = plan
  variables {
    image_repository = "ghcr.io/mbeacom/adrkit:latest"
  }
  expect_failures = [var.image_repository]
}

run "image_repository_accepts_registry_port" {
  command = plan
  variables {
    image_repository = "registry.example.com:5000/adrkit"
  }
}

run "sync_cron_rejects_six_fields" {
  command = plan
  variables {
    sync_cron = "0 */15 * * * *"
  }
  expect_failures = [var.sync_cron]
}

run "repos_reject_bad_key" {
  command = plan
  variables {
    repos = [{ key = "Platform", url = "https://github.com/example-org/platform" }]
  }
  expect_failures = [var.repos]
}

run "repos_reject_duplicate_key" {
  command = plan
  variables {
    repos = [
      { key = "platform", url = "https://github.com/example-org/platform" },
      { key = "platform", url = "https://github.com/example-org/other" },
    ]
  }
  expect_failures = [var.repos]
}

run "repos_reject_ssh_url" {
  command = plan
  variables {
    repos = [{ key = "platform", url = "git@github.com:example-org/platform.git" }]
  }
  expect_failures = [var.repos]
}

run "repos_reject_empty_ref" {
  command = plan
  variables {
    repos = [{ key = "platform", url = "https://github.com/example-org/platform", ref = "" }]
  }
  expect_failures = [var.repos]
}

run "secret_name_rejects_underscore" {
  command = plan
  variables {
    github_app_private_key_secret_name = "github_app_key"
  }
  expect_failures = [var.github_app_private_key_secret_name]
}

run "public_access_requires_entra" {
  command = plan
  variables {
    public_access = true
    enable_portal = false
  }
  expect_failures = [var.entra_tenant_id, var.entra_audience]
}

run "entra_tenant_id_rejects_non_guid" {
  command = plan
  variables {
    public_access   = true
    enable_portal   = false
    entra_tenant_id = "contoso.onmicrosoft.com"
    entra_audience  = "api://adrkit"
  }
  expect_failures = [var.entra_tenant_id]
}

run "rate_limit_calls_rejects_zero" {
  command = plan
  variables {
    rate_limit_calls = 0
  }
  expect_failures = [var.rate_limit_calls]
}

run "repos_reject_empty" {
  command = plan
  variables {
    repos = []
  }
  expect_failures = [var.repos]
}

run "public_access_rejects_portal" {
  command = plan
  variables {
    public_access   = true
    entra_tenant_id = "11111111-1111-1111-1111-111111111111"
    entra_audience  = "api://adrkit"
  }
  expect_failures = [var.enable_portal]
}

run "rate_limit_period_rejects_over_300" {
  command = plan
  variables {
    rate_limit_period_seconds = 301
  }
  expect_failures = [var.rate_limit_period_seconds]
}

run "rate_limit_period_rejects_zero" {
  command = plan
  variables {
    rate_limit_period_seconds = 0
  }
  expect_failures = [var.rate_limit_period_seconds]
}

run "enable_waf_requires_public_access" {
  command = plan
  variables {
    enable_waf = true
  }
  expect_failures = [var.enable_waf]
}

run "frontdoor_endpoint_name_rejects_trailing_hyphen" {
  command = plan
  variables {
    frontdoor_endpoint_name = "adrkit-"
  }
  expect_failures = [var.frontdoor_endpoint_name]
}

run "address_space_rejects_small_prefix" {
  command = plan
  variables {
    address_space = "10.60.0.0/24"
  }
  expect_failures = [var.address_space]
}

run "address_space_rejects_garbage" {
  command = plan
  variables {
    address_space = "not-a-cidr"
  }
  expect_failures = [var.address_space]
}
