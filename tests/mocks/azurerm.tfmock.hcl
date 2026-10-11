# Mock values for azurerm in `terraform test`. The provider's own validation
# still runs on planned values, so anything it parses must look real.
mock_data "azurerm_client_config" {
  defaults = {
    tenant_id       = "00000000-0000-0000-0000-000000000001"
    object_id       = "00000000-0000-0000-0000-000000000002"
    client_id       = "00000000-0000-0000-0000-000000000003"
    subscription_id = "00000000-0000-0000-0000-000000000000"
  }
}
