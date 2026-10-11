# Plan-only: nothing here contacts Azure (see tests/README.md). The network
# module uses azurerm only, so no azapi provider is configured here.

mock_provider "azurerm" {
  source = "./tests/mocks"
}

# The NSG on the Container Apps subnet is one of three layers that keep APIM
# the only route to the server, which authenticates no one (SECURITY.md).
variables {
  name_prefix         = "test"
  location            = "eastus2"
  resource_group_name = "test-adrkit-rg"
  address_space       = "10.60.0.0/16"
  tags                = {}
}

run "network_subnet_carve" {
  command = plan

  module {
    source = "./modules/network"
  }

  assert {
    condition     = azurerm_subnet.aca.address_prefixes[0] == "10.60.0.0/23"
    error_message = "The Container Apps subnet must be the first /23."
  }

  assert {
    condition     = output.apim_integration_subnet_prefix == "10.60.2.0/24"
    error_message = "The APIM integration subnet must be 10.60.2.0/24 for a 10.60.0.0/16."
  }

  assert {
    condition     = azurerm_subnet.pe.address_prefixes[0] == "10.60.3.0/24"
    error_message = "The private endpoint subnet must be 10.60.3.0/24."
  }
}

run "network_server_reachable_only_from_apim" {
  command = plan

  module {
    source = "./modules/network"
  }

  # Every inbound Allow comes from the APIM subnet, the Container Apps subnet
  # itself, or Azure Load Balancer probes; nothing else.
  assert {
    condition = alltrue([
      for r in azurerm_network_security_group.aca.security_rule :
      contains(["10.60.2.0/24", "10.60.0.0/23", "AzureLoadBalancer"], r.source_address_prefix)
      if r.direction == "Inbound" && r.access == "Allow"
    ])
    error_message = "Inbound Allow rules on the Container Apps subnet must admit only APIM, the subnet itself, and load balancer probes."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.aca.security_rule :
      r.direction == "Inbound" && r.access == "Deny" && r.source_address_prefix == "VirtualNetwork" && r.destination_port_range == "*"
    ])
    error_message = "The Container Apps NSG must deny the rest of the VNet."
  }

  assert {
    condition = alltrue([
      for r in azurerm_network_security_group.aca.security_rule :
      r.priority < [for d in azurerm_network_security_group.aca.security_rule : d.priority if d.access == "Deny"][0]
      if r.access == "Allow" && r.direction == "Inbound"
    ])
    error_message = "Every inbound Allow must take priority over the VNet deny."
  }
}
