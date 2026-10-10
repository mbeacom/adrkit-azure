# Throwaway measurement root. The subscription comes from ARM_SUBSCRIPTION_ID,
# which measure/run.sh exports; nothing here names a credential.
provider "azurerm" {
  features {}
}
