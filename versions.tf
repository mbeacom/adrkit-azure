terraform {
  # 1.10 is the floor because avm-res-app-managedenvironment 0.5.1 uses an
  # ephemeral resource. Validated locally with 1.13.x; CI pins its version.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    # Upper bound < 5.0.0: both Azure Verified Modules used here require
    # azurerm 4.x (avm-res-app-job 0.2.2 needs >= 4.73.0, < 5.0.0;
    # avm-res-app-managedenvironment 0.5.1 needs ~> 4.0), although azurerm
    # 5.x is published.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.73.0, < 5.0.0"
    }
    # avm-res-app-managedenvironment 0.5.1 needs ~> 2.12.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
