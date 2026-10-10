# Measurement 2 (ADR-0056 action item 2, second half; Context fact 5; clause 12).
#
# Question: can azurerm's own attributes, virtual_network_type and
# virtual_network_configuration, express APIM Standard v2 OUTBOUND VNet
# integration, which modules/apim sets through azapi instead? Their
# documentation describes classic injection.
#
# Method: plan only. This root imports the instance measurement 1 created
# (outbound integration already set by azapi) into an azurerm resource that
# declares the integration in azurerm's terms, and plans. Nothing is applied;
# run.sh never runs apply here, and there is nothing to destroy.
#
#   - Import with no update to virtual_network_* : azurerm READS v2 outbound
#     integration as External + this subnet, so it can at least represent it.
#   - An update to virtual_network_* : azurerm cannot read it back; azapi
#     stays required.
#   - A plan error naming these attributes for this SKU : azurerm refuses it.
#
# What plan cannot show: whether azurerm's CREATE or UPDATE call would be
# accepted by ARM for a v2 SKU. That needs an apply against a second instance
# with its own dedicated subnet, which is not scripted (see measure/README.md).

import {
  to = azurerm_api_management.probe
  id = var.apim_id
}

resource "azurerm_api_management" "probe" {
  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "StandardV2_1"

  # The attributes under test.
  virtual_network_type = "External"
  virtual_network_configuration {
    subnet_id = var.integration_subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  # Ignore only what measurement 1 owns and this question is not about, so the
  # plan's diff (if any) is the integration attributes alone. Never add
  # virtual_network_* here: that would hide the answer.
  lifecycle {
    ignore_changes = [
      tags,
      public_network_access_enabled,
    ]
  }
}
