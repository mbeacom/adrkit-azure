# Measurement 3 (ADR-0056 action item 3; clause 4; ADR-0055 clauses 4 and 5).
#
# Question: on an Azure Files (SMB) share mounted into Container Apps, does
# the sync job's populate-aside-then-two-moves swap
#
#   write <key>.next/ (files, then .adrkit-corpus.json LAST)
#   mv <key> <key>.old ; mv <key>.next <key> ; rm -rf <key>.old
#
# ever let a reader that follows ADR-0055 clause 5's reload rule (read the
# sidecar, load the tree, read the sidecar again, keep the load only if the
# commit did not move) accept a half-written or mixed tree? And do the moves
# themselves fail on SMB while a reader has files open?
#
# Two separate jobs, so the writer and the cross-client reader are separate
# replicas with separate SMB mounts, as the sync job and the server are. The
# writer job also runs a same-client reader in the background.
#
# Divergence from the skeleton, on purpose: the storage account here allows
# public network access and shared-key auth and has no private endpoint, and
# the environment has no VNet. modules/storage puts the share behind a private
# endpoint, which a non-VNet environment cannot reach. SMB rename semantics do
# not depend on which endpoint carries the traffic. The environment storage
# definition is ReadWrite for both jobs because the reader writes its results
# file to the share; the server's real mount is ReadOnly.

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  location = coalesce(var.location, data.azurerm_resource_group.this.location)
  tags = {
    "adrkit-measure" = var.run_id
    "measurement"    = "azure-files-swap"
  }
  mount_path = "/mnt/swap"
  script     = file("${path.module}/swap.sh")

  common_env = {
    RUN_ID                 = var.run_id
    MOUNT                  = local.mount_path
    SWAPS                  = tostring(var.swaps)
    FILES_PER_TREE         = tostring(var.files_per_tree)
    READER_TIMEOUT_SECONDS = tostring(var.reader_timeout_seconds)
  }

  jobs = {
    writer = "writer"
    reader = "reader"
  }
}

module "observability" {
  source = "../../modules/observability"

  name_prefix         = var.name_prefix
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags
}

resource "random_string" "storage_suffix" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_storage_account" "this" {
  name                     = "${var.name_prefix}sw${random_string.storage_suffix.result}"
  location                 = local.location
  resource_group_name      = data.azurerm_resource_group.this.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  # Container Apps mounts Azure Files with the account key.
  shared_access_key_enabled = true

  tags = local.tags
}

resource "azurerm_storage_share" "this" {
  name               = "swap"
  storage_account_id = azurerm_storage_account.this.id
  quota              = 5
  enabled_protocol   = "SMB"
}

resource "azurerm_container_app_environment" "this" {
  name                       = "${var.name_prefix}-swap-env"
  location                   = local.location
  resource_group_name        = data.azurerm_resource_group.this.name
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id
  tags                       = local.tags
}

resource "azurerm_container_app_environment_storage" "share" {
  name                         = "swap"
  container_app_environment_id = azurerm_container_app_environment.this.id
  account_name                 = azurerm_storage_account.this.name
  share_name                   = azurerm_storage_share.this.name
  access_key                   = azurerm_storage_account.this.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_job" "role" {
  for_each = local.jobs

  name                         = "${var.name_prefix}-swap-${each.key}"
  location                     = local.location
  resource_group_name          = data.azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  replica_timeout_in_seconds   = var.reader_timeout_seconds + 300
  replica_retry_limit          = 0
  tags                         = local.tags

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name    = each.key
      image   = var.image
      cpu     = 0.5
      memory  = "1Gi"
      command = ["/bin/bash", "-c"]
      args    = [local.script]

      dynamic "env" {
        for_each = merge(local.common_env, { ROLE = each.value })
        content {
          name  = env.key
          value = env.value
        }
      }

      volume_mounts {
        name = "share"
        path = local.mount_path
      }
    }

    volume {
      name         = "share"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.share.name
    }
  }
}
