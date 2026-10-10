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

variable "webhook_secret" {
  description = "Shared secret for the HMAC, generated per run by measure.sh. It lands in this root's local, throwaway state and tfvars file, which run.sh deletes at teardown."
  type        = string
  sensitive   = true

  validation {
    # Hex only, so the value can sit inside a C# string literal in the policy
    # expression without escaping.
    condition     = can(regex("^[0-9a-f]{32,128}$", var.webhook_secret))
    error_message = "webhook_secret must be 32-128 lowercase hex characters."
  }
}
