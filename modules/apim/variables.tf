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

variable "apim_name" {
  description = "Explicit, globally unique APIM name. Null derives \"<name_prefix>-adrkit-apim-<random 6>\"."
  type        = string
  default     = null
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

  validation {
    condition     = var.rate_limit_calls >= 1 && floor(var.rate_limit_calls) == var.rate_limit_calls
    error_message = "rate_limit_calls must be a positive integer (APIM rate-limit-by-key calls)."
  }
}

variable "rate_limit_period_seconds" {
  description = "rate-limit-by-key renewal period, an integer from 1 to 300 seconds (public-mode APIs and the private-mode portal)."
  type        = number

  validation {
    condition     = var.rate_limit_period_seconds >= 1 && var.rate_limit_period_seconds <= 300 && floor(var.rate_limit_period_seconds) == var.rate_limit_period_seconds
    error_message = "rate_limit_period_seconds must be an integer from 1 to 300 (APIM rate-limit-by-key renewal-period)."
  }
}

variable "enable_portal" {
  description = "Create the private-mode portal API. Must be false when public_access = true."
  type        = bool
  default     = true

  # A false -> true flip with the keyless portal on would destroy the portal
  # and open the gateway in one apply, in no enforced order (see README).
  # Refusing the combination forces two applies: enable_portal = false while
  # still private (portal destroyed), then public_access = true.
  validation {
    condition     = !(var.public_access && var.enable_portal)
    error_message = "enable_portal must be false when public_access = true. To go public, first apply enable_portal = false with public_access = false (the keyless portal is destroyed while the gateway is still private), then apply public_access = true."
  }
}

variable "portal_rate_limit_calls" {
  description = "Portal requests allowed per client IP per renewal period (private mode)."
  type        = number
  default     = 300

  validation {
    condition     = var.portal_rate_limit_calls >= 1 && floor(var.portal_rate_limit_calls) == var.portal_rate_limit_calls
    error_message = "portal_rate_limit_calls must be a positive integer (APIM rate-limit-by-key calls)."
  }
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
