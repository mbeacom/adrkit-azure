# Throwaway measurement root. The subscription comes from ARM_SUBSCRIPTION_ID,
# which measure/run.sh exports; nothing here names a credential.
provider "azurerm" {
  features {
    api_management {
      # A destroyed APIM v2 instance is otherwise soft-deleted and keeps its
      # global name reserved, which breaks a rerun and keeps billing questions
      # open. Purge it on destroy; never resurrect an old one on create.
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = false
    }
  }
}

provider "azapi" {}
