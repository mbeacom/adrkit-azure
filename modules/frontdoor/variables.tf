variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "location" {
  description = "Region of the APIM instance (for the Private Link origin)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create resources in."
  type        = string
}

variable "apim_id" {
  description = "APIM service resource ID (Private Link target)."
  type        = string
}

variable "apim_gateway_host" {
  description = "APIM default gateway host name."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
