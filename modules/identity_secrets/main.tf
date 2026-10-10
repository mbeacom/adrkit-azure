# Identity and secrets (ADR-0056 clause 5).
#
# One user-assigned identity for the sync job. It reads the GitHub App private
# key from Key Vault (Key Vault Secrets User, scoped to the vault). The server
# app gets no identity and no secret: it holds no GitHub credential and makes
# no outbound call (ADR-0055 clause 4).
#
# The GitHub App private key itself is NOT managed here. Terraform state would
# hold it in plain text. Set it out of band, for example
#   az keyvault secret set --vault-name <vault> --name github-app-private-key --file key.pem
# from a network that can reach the vault's private endpoint.

data "azurerm_client_config" "current" {}

resource "random_string" "kv_suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_user_assigned_identity" "sync" {
  name                = "${var.name_prefix}-adrkit-sync-id"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_key_vault" "this" {
  # Key Vault names are global, 3-24 characters.
  name                          = "${var.name_prefix}adrkitkv${random_string.kv_suffix.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  tags                          = var.tags

  network_acls {
    bypass         = "None"
    default_action = "Deny"
  }
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "${var.name_prefix}-adrkit-kv-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "kv"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv"
    private_dns_zone_ids = [var.key_vault_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "sync_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.sync.principal_id
  principal_type       = "ServicePrincipal"
}
