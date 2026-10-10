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

variable "retention_in_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
