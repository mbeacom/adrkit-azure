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

variable "sku" {
  description = "StandardV2 or PremiumV2."
  type        = string

  validation {
    condition     = contains(["StandardV2", "PremiumV2"], var.sku)
    error_message = "sku must be StandardV2 or PremiumV2."
  }
}

variable "capacity" {
  description = "Scale units."
  type        = number
  default     = 1
}

variable "publisher_name" {
  description = "Publisher name."
  type        = string
}

variable "publisher_email" {
  description = "Publisher email."
  type        = string
}

variable "public_access" {
  description = "false: publicNetworkAccess Disabled after the private endpoint exists. true: public, with token validation and rate limiting."
  type        = bool
}

variable "integration_subnet_id" {
  description = "Subnet delegated to Microsoft.Web/serverFarms for outbound integration."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the inbound private endpoint."
  type        = string
}

variable "apim_dns_zone_id" {
  description = "privatelink.azure-api.net zone ID."
  type        = string
}

variable "application_insights_id" {
  description = "Application Insights resource ID for the APIM logger."
  type        = string
}

variable "application_insights_key" {
  description = "Application Insights instrumentation key."
  type        = string
  sensitive   = true
}

variable "backend_url" {
  description = "HTTPS URL of the internal adrkit server."
  type        = string
}

variable "entra_tenant_id" {
  description = "Tenant for validate-azure-ad-token (public mode)."
  type        = string
  default     = null
}

variable "entra_audience" {
  description = "Audience for validate-azure-ad-token (public mode)."
  type        = string
  default     = null
}

variable "rate_limit_calls" {
  description = "rate-limit-by-key calls per period (public mode)."
  type        = number
}

variable "rate_limit_period_seconds" {
  description = "rate-limit-by-key renewal period (public mode)."
  type        = number
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
