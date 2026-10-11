# container_apps

Compute (ADR-0056 clauses 2, 3, 4): an internal Container Apps environment (AVM
`avm-res-app-managedenvironment`), the adrkit server app with the corpus share
mounted read-only, and the corpus sync job (AVM `avm-res-app-job`), plus the
environment's private DNS zone.

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

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_environment"></a> [environment](#module\_environment) | Azure/avm-res-app-managedenvironment/azurerm | 0.5.1 |
| <a name="module_sync_job"></a> [sync\_job](#module\_sync\_job) | Azure/avm-res-app-job/azurerm | 0.2.2 |

### Resources

| Name | Type |
| ---- | ---- |
| [azurerm_container_app.server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app) | resource |
| [azurerm_private_dns_a_record.environment_wildcard](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_a_record) | resource |
| [azurerm_private_dns_zone.environment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.environment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_ingress_cidr"></a> [allowed\_ingress\_cidr](#input\_allowed\_ingress\_cidr) | CIDR allowed through the server app's ingress IP restriction (the APIM integration subnet). | `string` | n/a | yes |
| <a name="input_github_app_private_key_secret_name"></a> [github\_app\_private\_key\_secret\_name](#input\_github\_app\_private\_key\_secret\_name) | Key Vault secret name of the GitHub App private key. | `string` | n/a | yes |
| <a name="input_infrastructure_subnet_id"></a> [infrastructure\_subnet\_id](#input\_infrastructure\_subnet\_id) | Subnet delegated to Microsoft.App/environments. | `string` | n/a | yes |
| <a name="input_key_vault_uri"></a> [key\_vault\_uri](#input\_key\_vault\_uri) | Key Vault URI the sync job reads the GitHub App key from. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics workspace for environment logs. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names. | `string` | n/a | yes |
| <a name="input_repos"></a> [repos](#input\_repos) | Repositories to sync (see the root variable). | <pre>list(object({<br/>    key     = string<br/>    url     = string<br/>    ref     = string<br/>    private = bool<br/>  }))</pre> | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group to create resources in. | `string` | n/a | yes |
| <a name="input_server_image"></a> [server\_image](#input\_server\_image) | Full image reference for the adrkit server (repository:tag[@digest]). | `string` | n/a | yes |
| <a name="input_share_name"></a> [share\_name](#input\_share\_name) | Azure Files share name. | `string` | n/a | yes |
| <a name="input_storage_account_access_key"></a> [storage\_account\_access\_key](#input\_storage\_account\_access\_key) | Storage account key for the environment storage definitions. | `string` | n/a | yes |
| <a name="input_storage_account_name"></a> [storage\_account\_name](#input\_storage\_account\_name) | Storage account holding the corpora share. | `string` | n/a | yes |
| <a name="input_sync_cron"></a> [sync\_cron](#input\_sync\_cron) | Cron expression for the sync job. | `string` | n/a | yes |
| <a name="input_sync_identity_client_id"></a> [sync\_identity\_client\_id](#input\_sync\_identity\_client\_id) | Client ID of the sync job's identity. | `string` | n/a | yes |
| <a name="input_sync_identity_id"></a> [sync\_identity\_id](#input\_sync\_identity\_id) | User-assigned identity resource ID for the sync job. | `string` | n/a | yes |
| <a name="input_sync_image"></a> [sync\_image](#input\_sync\_image) | TODO(sync-image): placeholder image for the sync job. | `string` | n/a | yes |
| <a name="input_virtual_network_id"></a> [virtual\_network\_id](#input\_virtual\_network\_id) | VNet to link the environment's private DNS zone to. | `string` | n/a | yes |
| <a name="input_server_max_replicas"></a> [server\_max\_replicas](#input\_server\_max\_replicas) | Maximum server replicas. | `number` | `3` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for every resource. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_environment_id"></a> [environment\_id](#output\_environment\_id) | Container Apps environment resource ID. |
| <a name="output_server_fqdn"></a> [server\_fqdn](#output\_server\_fqdn) | Internal FQDN of the server app. |
| <a name="output_server_url"></a> [server\_url](#output\_server\_url) | HTTPS URL APIM uses as the backend. Depends on the private DNS link so APIM never points at a name it cannot resolve. |
| <a name="output_sync_job_id"></a> [sync\_job\_id](#output\_sync\_job\_id) | Sync job resource ID. |
<!-- END_TF_DOCS -->