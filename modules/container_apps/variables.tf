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

variable "infrastructure_subnet_id" {
  description = "Subnet delegated to Microsoft.App/environments."
  type        = string
}

variable "virtual_network_id" {
  description = "VNet to link the environment's private DNS zone to."
  type        = string
}

variable "allowed_ingress_cidr" {
  description = "CIDR allowed through the server app's ingress IP restriction (the APIM integration subnet)."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for environment logs."
  type        = string
}

variable "server_image" {
  description = "Full image reference for the adrkit server (repository:tag[@digest])."
  type        = string
}

variable "server_max_replicas" {
  description = "Maximum server replicas."
  type        = number
  default     = 3
}

variable "sync_image" {
  description = "TODO(sync-image): placeholder image for the sync job."
  type        = string
}

variable "sync_cron" {
  description = "Cron expression for the sync job."
  type        = string
}

variable "repos" {
  description = "Repositories to sync (see the root variable)."
  type = list(object({
    key     = string
    url     = string
    ref     = string
    private = bool
  }))
}

variable "storage_account_name" {
  description = "Storage account holding the corpora share."
  type        = string
}

variable "storage_account_access_key" {
  description = "Storage account key for the environment storage definitions."
  type        = string
  sensitive   = true
}

variable "share_name" {
  description = "Azure Files share name."
  type        = string
}

variable "sync_identity_id" {
  description = "User-assigned identity resource ID for the sync job."
  type        = string
}

variable "sync_identity_client_id" {
  description = "Client ID of the sync job's identity."
  type        = string
}

variable "key_vault_uri" {
  description = "Key Vault URI the sync job reads the GitHub App key from."
  type        = string
}

variable "github_app_private_key_secret_name" {
  description = "Key Vault secret name of the GitHub App private key."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
