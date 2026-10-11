# Basic example: private mode

The default deployment: fully private. APIM's gateway is reachable only
through its inbound private endpoint, and the Container Apps environment, Key
Vault, and storage are private from the start. One public repository is
served.

Nothing here has been applied (see the root README, "Status"). `image_tag`
must be v0.20.0 or later, the first adrkit release with the `server`
selector.

## Use

Run from a machine that can reach the deployment's VNet once it exists, with
a state backend of your own added to `versions.tf`:

```bash
terraform init
terraform plan \
  -var 'apim_publisher_email=platform@example.com' \
  -var 'image_tag=v0.20.0'
```

`providers.tf` is part of the example on purpose: the module configures no
providers, and its `azurerm` feature settings are required (root README, "Use
as a module").

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
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Immutable adrkit image tag (vX.Y.Z, optionally @sha256:<digest>), v0.20.0 or later: the first release with the `server` selector. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region for every resource. | `string` | `"eastus2"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Short prefix for resource names (3 to 10 lowercase letters or digits). | `string` | `"adrkitb"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apim_gateway_url"></a> [apim\_gateway\_url](#output\_apim\_gateway\_url) | APIM gateway URL; resolves to the private endpoint only from networks linked to the privatelink.azure-api.net zone. |
| <a name="output_key_vault_uri"></a> [key\_vault\_uri](#output\_key\_vault\_uri) | Key Vault URI (store the GitHub App private key here, out of band, if you add private repositories). |
| <a name="output_mcp_endpoint_path"></a> [mcp\_endpoint\_path](#output\_mcp\_endpoint\_path) | Path of the MCP server under the gateway URL. |
<!-- END_TF_DOCS -->
