# apim

APIM Standard v2 gateway (ADR-0056 clauses 6, 7, 8, 10): the service, v2
outbound VNet integration and the two-step `publicNetworkAccess` change
(azapi), the inbound private endpoint, the REST API (GET only, with catch-all
operations that answer 405), the MCP API and its tools (azapi), policies, and
diagnostics that log no bodies. Read the header comment of `main.tf` before
changing any `depends_on`.

Internal submodule of [adrkit-azure](../../README.md), called by the root
module. It is not designed to be used on its own, and its inputs and outputs
may change in any release.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.13 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.73.0, < 5.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.9 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | ~> 2.13 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.73.0, < 5.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.9 |

### Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.mcp](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.mcp_policy](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.mcp_product](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.mcp_tool](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_update_resource.disable_public_access](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/update_resource) | resource |
| [azapi_update_resource.enable_public_access](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/update_resource) | resource |
| [azapi_update_resource.outbound](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/update_resource) | resource |
| [azurerm_api_management.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management) | resource |
| [azurerm_api_management_api.portal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api.rest](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api_operation.method_guard](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation) | resource |
| [azurerm_api_management_api_operation.portal_files](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation) | resource |
| [azurerm_api_management_api_operation.portal_method_guard](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation) | resource |
| [azurerm_api_management_api_operation.portal_root](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_operation) | resource |
| [azurerm_api_management_api_policy.portal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_api_policy.rest](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_backend.server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_backend) | resource |
| [azurerm_api_management_diagnostic.service](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_diagnostic) | resource |
| [azurerm_api_management_logger.appinsights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_logger) | resource |
| [azurerm_api_management_product.adrkit](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product) | resource |
| [azurerm_api_management_product_api.rest](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_private_endpoint.gateway](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [random_string.apim_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apim_dns_zone_id"></a> [apim\_dns\_zone\_id](#input\_apim\_dns\_zone\_id) | privatelink.azure-api.net zone ID. | `string` | n/a | yes |
| <a name="input_application_insights_id"></a> [application\_insights\_id](#input\_application\_insights\_id) | Application Insights resource ID for the APIM logger. | `string` | n/a | yes |
| <a name="input_application_insights_key"></a> [application\_insights\_key](#input\_application\_insights\_key) | Application Insights instrumentation key. | `string` | n/a | yes |
| <a name="input_backend_url"></a> [backend\_url](#input\_backend\_url) | HTTPS URL of the internal adrkit server. | `string` | n/a | yes |
| <a name="input_integration_subnet_id"></a> [integration\_subnet\_id](#input\_integration\_subnet\_id) | Subnet delegated to Microsoft.Web/serverFarms for outbound integration. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names. | `string` | n/a | yes |
| <a name="input_private_endpoint_subnet_id"></a> [private\_endpoint\_subnet\_id](#input\_private\_endpoint\_subnet\_id) | Subnet for the inbound private endpoint. | `string` | n/a | yes |
| <a name="input_public_access"></a> [public\_access](#input\_public\_access) | false: publicNetworkAccess Disabled after the private endpoint exists. true: public, with token validation and rate limiting. | `bool` | n/a | yes |
| <a name="input_publisher_email"></a> [publisher\_email](#input\_publisher\_email) | Publisher email. | `string` | n/a | yes |
| <a name="input_publisher_name"></a> [publisher\_name](#input\_publisher\_name) | Publisher name. | `string` | n/a | yes |
| <a name="input_rate_limit_calls"></a> [rate\_limit\_calls](#input\_rate\_limit\_calls) | rate-limit-by-key calls per period (public mode). | `number` | n/a | yes |
| <a name="input_rate_limit_period_seconds"></a> [rate\_limit\_period\_seconds](#input\_rate\_limit\_period\_seconds) | rate-limit-by-key renewal period, an integer from 1 to 300 seconds (public-mode APIs and the private-mode portal). | `number` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group to create resources in. | `string` | n/a | yes |
| <a name="input_sku"></a> [sku](#input\_sku) | StandardV2 or PremiumV2. | `string` | n/a | yes |
| <a name="input_apim_name"></a> [apim\_name](#input\_apim\_name) | Explicit, globally unique APIM name. Null derives "<name\_prefix>-adrkit-apim-<random 6>". | `string` | `null` | no |
| <a name="input_capacity"></a> [capacity](#input\_capacity) | Scale units. | `number` | `1` | no |
| <a name="input_enable_portal"></a> [enable\_portal](#input\_enable\_portal) | Create the private-mode portal API. Must be false when public\_access = true (never created in public mode). | `bool` | `true` | no |
| <a name="input_entra_audience"></a> [entra\_audience](#input\_entra\_audience) | Audience for validate-azure-ad-token (public mode). | `string` | `null` | no |
| <a name="input_entra_tenant_id"></a> [entra\_tenant\_id](#input\_entra\_tenant\_id) | Tenant for validate-azure-ad-token (public mode). | `string` | `null` | no |
| <a name="input_portal_rate_limit_calls"></a> [portal\_rate\_limit\_calls](#input\_portal\_rate\_limit\_calls) | Portal requests allowed per client IP per renewal period (private mode). | `number` | `300` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for every resource. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apim_id"></a> [apim\_id](#output\_apim\_id) | APIM service resource ID. |
| <a name="output_apim_name"></a> [apim\_name](#output\_apim\_name) | APIM service name (global; includes the random suffix unless apim\_name was set). |
| <a name="output_gateway_hostname"></a> [gateway\_hostname](#output\_gateway\_hostname) | Default gateway host name. |
| <a name="output_gateway_url"></a> [gateway\_url](#output\_gateway\_url) | Default gateway URL. |
| <a name="output_mcp_path"></a> [mcp\_path](#output\_mcp\_path) | Path of the MCP server API. |
| <a name="output_portal_path"></a> [portal\_path](#output\_portal\_path) | Path of the private-mode decision portal API; null when it is not created (public mode, or enable\_portal = false). |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | APIM system-assigned identity principal ID. |
| <a name="output_public_network_access"></a> [public\_network\_access](#output\_public\_network\_access) | Value set by the second step. |
<!-- END_TF_DOCS -->
