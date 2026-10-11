variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "eastus2"
}

variable "name_prefix" {
  description = "Short prefix for resource names (3 to 10 lowercase letters or digits)."
  type        = string
  default     = "adrkitb"
}

variable "apim_publisher_email" {
  description = "APIM publisher email (required by the service)."
  type        = string
}

variable "image_tag" {
  description = "Immutable adrkit image tag (vX.Y.Z, optionally @sha256:<digest>), v0.20.0 or later: the first release with the `server` selector."
  type        = string
}
