# Compute (ADR-0056 clauses 2, 3, 4).
#
# One Container Apps environment on workload profiles, INTERNAL in both modes,
# so flipping public_access never recreates the backend. It runs:
#   - the adrkit server: the `server` selector of ghcr.io/mbeacom/adrkit
#     (ADR-0055). NOT RELEASED YET (adrkit issue #296); var.server_image must
#     name a tag that contains it before an apply can succeed.
#   - the corpus sync job: Schedule trigger, writes the share. Its image is a
#     TODO placeholder; no sync image exists yet.
#
# The share is defined on the environment twice: once ReadOnly (mounted by the
# server) and once ReadWrite (mounted by the sync job). The ReadOnly storage
# definition is what makes the server's corpus mount read-only.

locals {
  storage_ro = "corpora-ro"
  storage_rw = "corpora-rw"
  mount_path = "/corpora"

  # Job names: lowercase, at most 32 characters.
  sync_job_name = substr("${var.name_prefix}-adrkit-sync", 0, 32)
}

module "environment" {
  source  = "Azure/avm-res-app-managedenvironment/azurerm"
  version = "0.5.1"

  name                = "${var.name_prefix}-adrkit-cae"
  location            = var.location
  resource_group_name = var.resource_group_name
  enable_telemetry    = false
  tags                = var.tags

  log_analytics_workspace = {
    resource_id = var.log_analytics_workspace_id
  }

  vnet_configuration = {
    infrastructure_subnet_id = var.infrastructure_subnet_id
    # Internal in BOTH modes (ADR-0056 clause 3). Only APIM, through its
    # outbound VNet integration, is meant to reach the server.
    internal = true
  }

  # A Consumption-only workload-profiles environment. Add a Dedicated profile
  # here if the server needs one.
  workload_profiles = [
    {
      name                  = "Consumption"
      workload_profile_type = "Consumption"
    }
  ]

  # Zone redundancy changes subnet sizing and cost; off for the skeleton.
  zone_redundant = false

  storages = {
    ro = {
      name                = local.storage_ro
      account_key         = var.storage_account_access_key
      account_key_version = 1
      azure_file = {
        access_mode  = "ReadOnly"
        account_name = var.storage_account_name
        share_name   = var.share_name
      }
    }
    rw = {
      name                = local.storage_rw
      account_key         = var.storage_account_access_key
      account_key_version = 1
      azure_file = {
        access_mode  = "ReadWrite"
        account_name = var.storage_account_name
        share_name   = var.share_name
      }
    }
  }
}

# The environment's default domain resolves only through a private DNS zone
# named after it, with a wildcard record to the environment's static IP. APIM's
# outbound integration needs this to resolve the server's FQDN.
resource "azurerm_private_dns_zone" "environment" {
  name                = module.environment.default_domain
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "environment_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.environment.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [module.environment.static_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "environment" {
  name                  = "cae-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.environment.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_container_app" "server" {
  name                         = "${var.name_prefix}-adrkit-server"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = module.environment.resource_id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  template {
    # Always one warm replica: no cold start for MCP clients (clause 3).
    min_replicas = 1
    max_replicas = var.server_max_replicas

    container {
      name   = "server"
      image  = var.server_image
      cpu    = 0.5
      memory = "1Gi"

      # The entrypoint's selector (ADR-0055 clause 12). Not in any released
      # image yet (adrkit issue #296).
      args = ["server"]

      # ADR-0055 clause 14: the operator's assertion that an authenticating
      # gateway is in front. True here because the environment is internal and
      # the only route in is APIM (ADR-0056 clause 2).
      env {
        name  = "ADRKIT_SERVER_HOST"
        value = "0.0.0.0"
      }

      # TODO(server-config): ADR-0055 clause 6 says a read-only JSON config
      # maps each corpus key to a directory, but defines no environment
      # variable or path for it yet. Wire it here (expected: one entry per
      # var.repos key, pointing at ${local.mount_path}/<key>) once the server
      # (adrkit issue #296) fixes the name.

      volume_mounts {
        name = "corpora"
        path = local.mount_path
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"
      }
    }

    volume {
      name         = "corpora"
      storage_type = "AzureFile"
      storage_name = local.storage_ro
    }
  }

  ingress {
    # In an INTERNAL environment, "external" ingress means reachable from the
    # VNet (where APIM's integration subnet is), not from the internet.
    # external_enabled = false would limit callers to apps inside the
    # environment, which would shut APIM out.
    external_enabled = true
    target_port      = 8080
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # The environment storage definitions (corpora-ro) live in a child module of
  # the environment; a reference to its resource_id alone would not wait for
  # them. This also defers the app's plan-time values to apply.
  depends_on = [module.environment]

  # Not expressible in Container Apps: a read-only root file system and the
  # "no outbound connection" posture of ADR-0055 clause 13. The server itself
  # makes no outbound call; restricting egress at the network layer is a
  # TODO(egress) in modules/network.
}

module "sync_job" {
  source  = "Azure/avm-res-app-job/azurerm"
  version = "0.2.2"

  name                                  = local.sync_job_name
  location                              = var.location
  resource_group_name                   = var.resource_group_name
  container_app_environment_resource_id = module.environment.resource_id
  workload_profile_name                 = "Consumption"
  enable_telemetry                      = false
  tags                                  = var.tags

  managed_identities = {
    user_assigned_resource_ids = [var.sync_identity_id]
  }

  trigger_config = {
    schedule_trigger_config = {
      cron_expression          = var.sync_cron
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  # Wait for the corpora-rw storage definition (see the server app above).
  depends_on = [module.environment]

  replica_timeout_in_seconds = 1800
  replica_retry_limit        = 1

  template = {
    container = {
      name = "sync"
      # TODO(sync-image): placeholder. No sync image exists yet. The real one
      # implements ADR-0056 clause 4 for each repo: shallow-clone docs/adr into
      # <key>.next/, write .adrkit-corpus.json ({"commit": "<40 hex>"}) LAST,
      # move <key>/ aside, move <key>.next/ into place.
      image  = var.sync_image
      cpu    = 0.5
      memory = "1Gi"

      # TODO(sync-contract): these variable names are a proposal for the
      # not-yet-written sync image, not an existing contract.
      env = [
        { name = "ADRKIT_SYNC_ROOT", value = local.mount_path },
        { name = "ADRKIT_SYNC_REPOS", value = jsonencode(var.repos) },
        { name = "AZURE_CLIENT_ID", value = var.sync_identity_client_id },
        { name = "ADRKIT_SYNC_KEY_VAULT_URI", value = var.key_vault_uri },
        { name = "ADRKIT_SYNC_GITHUB_APP_KEY_SECRET", value = var.github_app_private_key_secret_name },
        # TODO(github-app): GitHub App ID and installation ID for private
        # repositories (ADR-0056 clause 5) are not wired yet.
      ]

      volume_mounts = [
        { name = "corpora", path = local.mount_path }
      ]
    }

    volume = [
      {
        name         = "corpora"
        storage_type = "AzureFile"
        storage_name = local.storage_rw
      }
    ]
  }
}
