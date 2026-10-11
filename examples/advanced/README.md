# Advanced example: public mode with Front Door and a WAF

Public mode, deliberately exposed: every API validates an Entra ID token and
rate-limits by token subject; Azure Front Door Premium with a WAF policy sits
in front of APIM over Private Link. It also shows private repositories read
through a GitHub App, explicit global names, a non-default address space, a
slower sync schedule, and caller tags.

Read the root README sections "The two modes" and "Cost notes" first: Front
Door is the largest optional cost line, and the Private Link connection it
creates on APIM must be approved before traffic flows
(`TODO(frontdoor-approval)`).

Nothing here has been applied (see the root README, "Status"). `image_tag`
must be v0.20.0 or later, the first adrkit release with the `server`
selector.

## Use

```bash
terraform init
terraform plan \
  -var 'apim_publisher_email=platform@example.com' \
  -var 'image_tag=v0.20.0' \
  -var 'entra_tenant_id=<your tenant GUID>' \
  -var 'entra_audience=api://adrkit'
```

The repository `example-org/platform` is a placeholder; replace it with your
own. For private repositories, create the GitHub App (`contents: read` on
those repositories only) and put its private key in the Key Vault this
deployment creates, under `github-app-private-key`. Terraform never handles
the key.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.13 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.73.0, < 5.0.0 |

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_adrkit"></a> [adrkit](#module\_adrkit) | ../.. | n/a |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apim_publisher_email"></a> [apim\_publisher\_email](#input\_apim\_publisher\_email) | APIM publisher email (required by the service). | `string` | n/a | yes |
| <a name="input_entra_audience"></a> [entra\_audience](#input\_entra\_audience) | Audience (application ID URI or client ID) required on those tokens. | `string` | n/a | yes |
| <a name="input_entra_tenant_id"></a> [entra\_tenant\_id](#input\_entra\_tenant\_id) | Entra ID tenant (GUID) that issues the tokens APIM accepts. | `string` | n/a | yes |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Immutable adrkit image tag (vX.Y.Z, optionally @sha256:<digest>), v0.20.0 or later: the first release with the `server` selector. | `string` | n/a | yes |
| <a name="input_apim_name"></a> [apim\_name](#input\_apim\_name) | Explicit, globally unique APIM name, or null for a derived name with a random suffix. | `string` | `null` | no |
| <a name="input_frontdoor_endpoint_name"></a> [frontdoor\_endpoint\_name](#input\_frontdoor\_endpoint\_name) | Explicit, globally unique Front Door endpoint name, or null for a derived name with a random suffix. | `string` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for every resource. | `string` | `"eastus2"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Short prefix for resource names (3 to 10 lowercase letters or digits). | `string` | `"adrkita"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apim_gateway_url"></a> [apim\_gateway\_url](#output\_apim\_gateway\_url) | APIM gateway URL. |
| <a name="output_frontdoor_endpoint_hostname"></a> [frontdoor\_endpoint\_hostname](#output\_frontdoor\_endpoint\_hostname) | Front Door endpoint hostname: the public entry point. |
| <a name="output_key_vault_uri"></a> [key\_vault\_uri](#output\_key\_vault\_uri) | Key Vault URI. Store the GitHub App private key here, out of band, under github\_app\_private\_key\_secret\_name. |
| <a name="output_mcp_endpoint_path"></a> [mcp\_endpoint\_path](#output\_mcp\_endpoint\_path) | Path of the MCP server under the gateway URL. |
<!-- END_TF_DOCS -->
