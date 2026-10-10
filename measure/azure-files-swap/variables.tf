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

variable "image" {
  description = "Image for both jobs. Needs bash, GNU coreutils (date +%s%N, mv, rm), and sed. Pin a tag you trust."
  type        = string
  default     = "mcr.microsoft.com/azurelinux/base/core:3.0"
}

variable "swaps" {
  description = "Number of two-move swaps the writer performs."
  type        = number
  default     = 300
}

variable "files_per_tree" {
  description = "Files written into each <key>.next/ tree before the sidecar."
  type        = number
  default     = 40
}

variable "reader_timeout_seconds" {
  description = "Upper bound on how long a reader runs if the writer never finishes."
  type        = number
  default     = 1500
}
