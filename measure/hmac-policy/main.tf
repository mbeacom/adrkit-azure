# Measurement 5 (ADR-0056 action item 5; Context fact 5; clause 9).
#
# Question: can an APIM policy verify GitHub's X-Hub-Signature-256 HMAC over
# the raw body, with the secret held as a secret named value? measure.sh sends
# correctly signed, wrongly signed, unsigned, tampered, non-ASCII, empty, and
# large bodies and asserts 200 only for the correct signatures.
#
# Two outcomes are results, not harness failures:
#   - apply fails on azurerm_api_management_api_policy.webhook: APIM will not
#     accept the expression, so clause 9 is dropped.
#   - apply succeeds but the sends do not separate good from bad signatures.
#
# Public instance, no VNet, no backend, no subscription key (GitHub cannot
# send one). The webhook in clause 9 would call ARM jobs/start; that half is
# not measured here, only the verification.

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  location = coalesce(var.location, data.azurerm_resource_group.this.location)
  tags = {
    "adrkit-measure" = var.run_id
    "measurement"    = "hmac-policy"
  }
}

resource "random_string" "apim_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_api_management" "this" {
  name                = "${var.name_prefix}-hmac-${random_string.apim_suffix.result}"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  publisher_name      = "adrkit rung-1 measurement"
  publisher_email     = var.publisher_email
  sku_name            = "StandardV2_1"
  tags                = local.tags
}

# A plain secret named value, not a Key Vault reference: Key Vault would add a
# second soft-deleted resource to a throwaway run. The value is in this root's
# local state, which run.sh deletes at teardown.
resource "azurerm_api_management_named_value" "secret" {
  name                = "github-webhook-secret"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  display_name        = "github-webhook-secret"
  secret              = true
  value               = var.webhook_secret
}

resource "azurerm_api_management_api" "webhook" {
  name                  = "webhook"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = data.azurerm_resource_group.this.name
  revision              = "1"
  display_name          = "adrkit measurement webhook"
  path                  = "hmac-measure"
  protocols             = ["https"]
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "github" {
  operation_id        = "github"
  api_name            = azurerm_api_management_api.webhook.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  display_name        = "GitHub webhook delivery"
  method              = "POST"
  url_template        = "/github"

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "webhook" {
  api_name            = azurerm_api_management_api.webhook.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  xml_content         = file("${path.module}/webhook-policy.xml")

  depends_on = [azurerm_api_management_named_value.secret]
}
