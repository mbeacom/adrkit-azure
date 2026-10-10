terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  # Same constraints as the repository root.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.73.0, < 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
