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

resource "azurerm_storage_account" "this" {
  # Storage account names are global, 3-24 lowercase letters and digits.
  name                            = "${var.name_prefix}adrkit${random_string.suffix.result}"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = var.replication_type
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  tags                            = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

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
