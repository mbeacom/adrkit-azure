# Every value comes from the public-network-access instance, which must exist
# when this plan runs. run.sh passes them; nothing here is created.

variable "apim_id" {
  description = "Resource ID of the existing Standard v2 instance whose outbound integration azapi set."
  type        = string
}

variable "apim_name" {
  description = "Its name."
  type        = string
}

variable "resource_group_name" {
  description = "Its resource group."
  type        = string
}

variable "location" {
  description = "Its region."
  type        = string
}

variable "publisher_name" {
  description = "Its publisher name (matched so the plan shows no unrelated diff)."
  type        = string
}

variable "publisher_email" {
  description = "Its publisher email (matched so the plan shows no unrelated diff)."
  type        = string
}

variable "integration_subnet_id" {
  description = "The delegated subnet azapi set as virtualNetworkConfiguration.subnetResourceId."
  type        = string
}
