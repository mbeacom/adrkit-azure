# storage

Corpus storage (ADR-0056 clause 4): one Azure Files share behind a private
endpoint, written by the sync job and mounted read-only by the server.

Internal submodule of [adrkit-azure](../../README.md), called by the root
module. It is not designed to be used on its own, and its inputs and outputs
may change in any release.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.73.0, < 5.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.9 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.73.0, < 5.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.9 |

### Resources

| Name | Type |
| ---- | ---- |
| [azurerm_private_endpoint.file](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_share.corpora](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_file_dns_zone_id"></a> [file\_dns\_zone\_id](#input\_file\_dns\_zone\_id) | privatelink.file.core.windows.net zone ID. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names (at most 10 characters so the account name fits 24). | `string` | n/a | yes |
| <a name="input_private_endpoint_subnet_id"></a> [private\_endpoint\_subnet\_id](#input\_private\_endpoint\_subnet\_id) | Subnet for the Files private endpoint. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group to create resources in. | `string` | n/a | yes |
| <a name="input_replication_type"></a> [replication\_type](#input\_replication\_type) | Storage replication. LRS is enough: the share is a cache of git, rebuilt by the next sync. | `string` | `"LRS"` | no |
| <a name="input_share_quota_gb"></a> [share\_quota\_gb](#input\_share\_quota\_gb) | Share quota in GiB. | `number` | `5` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for every resource. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_primary_access_key"></a> [primary\_access\_key](#output\_primary\_access\_key) | Account key, for the Container Apps environment storage definitions only. |
| <a name="output_share_name"></a> [share\_name](#output\_share\_name) | Name of the corpora share. Depends on the private endpoint so nothing mounts it before the endpoint exists. |
| <a name="output_storage_account_id"></a> [storage\_account\_id](#output\_storage\_account\_id) | Storage account resource ID. |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name) | Storage account name. |
<!-- END_TF_DOCS -->
