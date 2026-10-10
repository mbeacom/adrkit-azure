variable "name_prefix" {
  description = "Prefix for resource names (at most 10 characters so the account name fits 24)."
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
  description = "Subnet for the Files private endpoint."
  type        = string
}

variable "file_dns_zone_id" {
  description = "privatelink.file.core.windows.net zone ID."
  type        = string
}

variable "replication_type" {
  description = "Storage replication. LRS is enough: the share is a cache of git, rebuilt by the next sync."
  type        = string
  default     = "LRS"
}

variable "share_quota_gb" {
  description = "Share quota in GiB."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
