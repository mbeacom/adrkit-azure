variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "eastus2"
}

variable "name_prefix" {
  description = "Short prefix for resource names (3 to 10 lowercase letters or digits)."
  type        = string
  default     = "adrkita"
}

variable "apim_name" {
  description = "Explicit, globally unique APIM name, or null for a derived name with a random suffix."
  type        = string
  default     = null
}

variable "apim_publisher_email" {
  description = "APIM publisher email (required by the service)."
  type        = string
}

variable "image_tag" {
  description = "Immutable adrkit image tag (vX.Y.Z, optionally @sha256:<digest>), v0.20.0 or later: the first release with the `server` selector."
  type        = string
}

variable "entra_tenant_id" {
  description = "Entra ID tenant (GUID) that issues the tokens APIM accepts."
  type        = string
}

variable "entra_audience" {
  description = "Audience (application ID URI or client ID) required on those tokens."
  type        = string
}

variable "frontdoor_endpoint_name" {
  description = "Explicit, globally unique Front Door endpoint name, or null for a derived name with a random suffix."
  type        = string
  default     = null
}
