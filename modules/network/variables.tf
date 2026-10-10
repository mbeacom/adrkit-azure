variable "name_prefix" {
  description = "Prefix for resource names."
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

variable "address_space" {
  description = "VNet address space, at least a /16 so the fixed subnet carve fits."
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && tonumber(split("/", var.address_space)[1]) <= 16
    error_message = "address_space must be a valid IPv4 CIDR of /16 or larger."
  }
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
