terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  # Same constraints as the repository root, so a measurement exercises the
  # provider versions the skeleton is validated with.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.73.0, < 5.0.0"
    }
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
