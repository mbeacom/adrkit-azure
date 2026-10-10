variable "resource_group_name" {
  description = "Existing, throwaway resource group. The measurement creates everything inside it and never creates or deletes the group itself."
  type        = string
}

variable "location" {
  description = "Azure region. Null uses the resource group's region."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Short lowercase prefix for resource names (run.sh derives it from the run id)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.name_prefix))
    error_message = "name_prefix must be 3-12 lowercase letters or digits, starting with a letter."
  }
}

variable "run_id" {
  description = "Run identifier, applied as the adrkit-measure tag so leftovers can be found."
  type        = string
}

variable "publisher_email" {
  description = "APIM publisher email (required by Azure; receives APIM system notifications)."
  type        = string
}

variable "public_access" {
  description = "The switch under test. false sets publicNetworkAccess Disabled; true sets Enabled. run.sh applies false, then true, then false."
  type        = bool
  default     = false
}

variable "address_space" {
  description = "VNet address space for modules/network (a /16)."
  type        = string
  default     = "10.90.0.0/16"
}
