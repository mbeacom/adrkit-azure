# The module configures no providers; its caller does. These settings are not
# optional for this module: copy them into your own root configuration.
# Authentication comes from the environment (Azure CLI, OIDC, or a managed
# identity); nothing here names a credential.
provider "azurerm" {
  features {
    key_vault {
      # A Key Vault with purge protection cannot be purged anyway; do not try.
      purge_soft_delete_on_destroy = false
    }
    storage {
      # The storage account has public network access off from creation.
      # Keep azurerm from making data-plane calls (service properties) that
      # would fail from outside the VNet; the share is managed through ARM.
      data_plane_available = false
    }
  }
  storage_use_azuread = true
}

provider "azapi" {}
