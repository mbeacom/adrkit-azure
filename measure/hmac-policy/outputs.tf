output "apim_id" {
  description = "APIM service resource ID."
  value       = azurerm_api_management.this.id
}

output "gateway_url" {
  description = "Default gateway URL."
  value       = azurerm_api_management.this.gateway_url
}

output "webhook_url" {
  description = "URL measure.sh posts signed bodies to."
  value       = "${azurerm_api_management.this.gateway_url}/hmac-measure/github"
}
