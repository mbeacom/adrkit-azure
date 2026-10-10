output "endpoint_hostname" {
  description = "Front Door endpoint host name."
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}
