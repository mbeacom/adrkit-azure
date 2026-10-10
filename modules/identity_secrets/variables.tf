variable "name_prefix" {
  description = "Prefix for resource names (at most 10 characters so the vault name fits 24)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create resources in."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the Key Vault private endpoint."
  type        = string
}

variable "key_vault_dns_zone_id" {
  description = "privatelink.vaultcore.azure.net zone ID."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
