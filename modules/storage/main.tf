# Corpus storage (ADR-0056 clause 4): one Azure Files share that the sync job
# writes and the server mounts read-only, behind a private endpoint.
#
# shared_access_key_enabled stays true: Container Apps Azure Files (SMB)
# storage on the environment authenticates with the account key. The key is
# passed to the environment storage definition and never to a container.
#
# The share is created through the management plane (storage_account_id), so
# Terraform does not need data-plane reach to the account once public network
# access is off.

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# The share holds only a cache synced from git (ADR-0056 clause 4) and is
# rebuilt by the next sync run; prevent_destroy cannot be made conditional, so
# it would also block callers from ever destroying the module.
# Queue-service logging (checkov CKV_AZURE_33, trivy AZU-0057) does not
# apply: the account serves one Files share and no queues, and its data plane
# is private, so azurerm cannot set queue properties
# (data_plane_available = false in the caller's provider block). Geo-redundant
# replication (trivy AZU-0058, checkov CKV_AZURE_206) is declined on
# purpose: see replication_type.
# trivy:ignore:AZU-0057
# trivy:ignore:AZU-0058
resource "azurerm_storage_account" "this" { # tflint-ignore: azurerm_resources_missing_prevent_destroy
  #checkov:skip=CKV_AZURE_33:No queues; the data plane is private (see the comment above).
  #checkov:skip=CKV_AZURE_206:LRS is deliberate (replication_type); the share is a cache of git, rebuilt by the next sync.
  #checkov:skip=CKV2_AZURE_40:Container Apps mounts Azure Files (SMB) with the account key; see the header comment.
  #checkov:skip=CKV2_AZURE_41:No SAS is issued; the only data-plane access is the SMB mount with the account key.
  #checkov:skip=CKV2_AZURE_38:Soft delete adds nothing to a cache of git that the next sync rebuilds.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys plus infrastructure encryption; the corpus is decision records already held in git.
  # Storage account names are global, 3-24 lowercase letters and digits.
  name                       = "${var.name_prefix}adrkit${random_string.suffix.result}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  account_kind               = "StorageV2"
  account_tier               = "Standard"
  account_replication_type   = var.replication_type
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true
  # Double encryption at rest. Settable only at creation, on general-purpose
  # v2 among others (verified, Microsoft Learn "Enable infrastructure
  # encryption for double encryption of data", 2026-10-10).
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = false
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = true
  tags                              = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Same reasoning as the storage account: the corpus is re-derived from git.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_share" "corpora" {
  name               = "corpora"
  storage_account_id = azurerm_storage_account.this.id
  quota              = var.share_quota_gb
  enabled_protocol   = "SMB"
}

resource "azurerm_private_endpoint" "file" {
  name                = "${var.name_prefix}-adrkit-file-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "file"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "file"
    private_dns_zone_ids = [var.file_dns_zone_id]
  }
}

# TODO(rung-1): ADR-0056 action item 3. Measure the `<key>.next/` two-move
# swap on this SMB share against ADR-0055's reload under concurrent reads
# before treating the sync as safe.
