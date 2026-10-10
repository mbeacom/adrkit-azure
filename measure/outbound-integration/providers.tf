# Plan-only measurement root: it creates nothing. The subscription comes from
# ARM_SUBSCRIPTION_ID, which measure/run.sh exports.
provider "azurerm" {
  features {}
}
