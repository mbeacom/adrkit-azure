# network

Network (ADR-0056 clause 12): the VNet, three subnets (Container Apps, APIM
integration, private endpoints), their NSGs, and Private DNS zones. The NSG on
the Container Apps subnet admits only the APIM integration subnet; it is one of
the three layers that keep APIM the only route to the server (SECURITY.md).

Internal submodule of [adrkit-azure](../../README.md), called by the root
module. It is not designed to be used on its own, and its inputs and outputs
may change in any release.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.73.0, < 5.0.0 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.73.0, < 5.0.0 |

### Resources

| Name | Type |
| ---- | ---- |
| [azurerm_network_security_group.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_group.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_private_dns_zone.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_subnet.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.pe](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.aca](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_network_security_group_association.apim](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | VNet address space, at least a /16 so the fixed subnet carve fits. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group to create resources in. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for every resource. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apim_integration_subnet_id"></a> [apim\_integration\_subnet\_id](#output\_apim\_integration\_subnet\_id) | Delegated subnet for APIM v2 outbound integration. The NSG association is a dependency of this output, so APIM never integrates into a subnet without its NSG. |
| <a name="output_apim_integration_subnet_prefix"></a> [apim\_integration\_subnet\_prefix](#output\_apim\_integration\_subnet\_prefix) | Address prefix of the APIM integration subnet: the only VNet source allowed to reach the server. |
| <a name="output_container_apps_subnet_id"></a> [container\_apps\_subnet\_id](#output\_container\_apps\_subnet\_id) | Subnet for the Container Apps environment. Depends on its NSG association, so the environment never lands in the subnet before the inbound restriction exists. |
| <a name="output_private_dns_zone_ids"></a> [private\_dns\_zone\_ids](#output\_private\_dns\_zone\_ids) | Private DNS zone IDs keyed apim, file, key\_vault. Each depends on its VNet link, so a private endpoint registered in it resolves inside the VNet. |
| <a name="output_private_endpoint_subnet_id"></a> [private\_endpoint\_subnet\_id](#output\_private\_endpoint\_subnet\_id) | Subnet for private endpoints. |
| <a name="output_virtual_network_id"></a> [virtual\_network\_id](#output\_virtual\_network\_id) | VNet resource ID. |
<!-- END_TF_DOCS -->
