# Network for the adrkit deployment (ADR-0056 clause 12).
#
# Three subnets, each with one job:
#   aca  - the Container Apps environment (workload profiles, internal).
#          Delegated to Microsoft.App/environments.
#   apim - APIM v2 outbound virtual network integration. Dedicated to one APIM
#          instance, delegated to Microsoft.Web/serverFarms, NSG required
#          (verified on Microsoft Learn, "Integrate ... for outbound
#          connections", 2026-10-10).
#   pe   - private endpoints for APIM (inbound), Azure Files, and Key Vault.
#
# Private DNS zones for the three privatelink names are created and linked
# here. The zone for the Container Apps environment's own default domain is
# created in modules/container_apps, because its name and IP only exist once
# the environment does.

locals {
  subnets = {
    aca  = cidrsubnet(var.address_space, 7, 0) # /23 from a /16
    apim = cidrsubnet(var.address_space, 8, 2) # /24, minimum /27
    pe   = cidrsubnet(var.address_space, 8, 3) # /24
  }

  private_dns_zones = {
    apim      = "privatelink.azure-api.net"
    file      = "privatelink.file.core.windows.net"
    key_vault = "privatelink.vaultcore.azure.net"
  }
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-adrkit-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnets.aca]

  delegation {
    name = "aca"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "apim" {
  name                 = "snet-apim-integration"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnets.apim]

  delegation {
    name = "apim-integration"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                              = "snet-private-endpoints"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [local.subnets.pe]
  private_endpoint_network_policies = "Disabled"
}

# NSG required on the APIM integration subnet. Inbound rules do not apply to a
# v2 integrated instance (Microsoft Learn); the outbound rule for Key Vault is
# the documented dependency. Backends are inside this VNet, so the default
# VirtualNetwork outbound allow covers APIM -> Container Apps.
resource "azurerm_network_security_group" "apim" {
  name                = "${var.name_prefix}-adrkit-apim-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-keyvault-outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  # TODO(egress): decide whether to deny Internet outbound from the
  # integration subnet. Not done yet because APIM's own dependencies beyond
  # Key Vault on a v2 integrated instance are not measured.
}

# NSG on the Container Apps subnet: the server authenticates no one
# (ADR-0055 clause 14), so the only VNet source allowed to reach the
# environment's ingress is APIM's integration subnet. Allow rules follow
# Microsoft Learn's inbound table for workload-profile environments
# ("Network security groups for configuring a virtual network in Azure
# Container Apps", read 2026-10-10): client -> subnet on 80/31080 and
# 443/31443, Azure Load Balancer -> 30000-32767. Traffic within the subnet
# is allowed explicitly, because the final rule denies the rest of the VNet
# (which the default AllowVnetInBound rule would otherwise admit, peerings
# included).
resource "azurerm_network_security_group" "aca" {
  name                = "${var.name_prefix}-adrkit-aca-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-apim-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "31080"]
    source_address_prefix      = local.subnets.apim
    destination_address_prefix = local.subnets.aca
  }

  security_rule {
    name                       = "allow-apim-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "31443"]
    source_address_prefix      = local.subnets.apim
    destination_address_prefix = local.subnets.aca
  }

  security_rule {
    name                       = "allow-azure-load-balancer-probes"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = local.subnets.aca
  }

  security_rule {
    name                       = "allow-intra-subnet"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.subnets.aca
    destination_address_prefix = local.subnets.aca
  }

  security_rule {
    name                       = "deny-other-vnet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aca" {
  subnet_id                 = azurerm_subnet.aca.id
  network_security_group_id = azurerm_network_security_group.aca.id
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = local.private_dns_zones
  name                  = "${each.key}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
