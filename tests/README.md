# Tests

`terraform test` suites for the module. They run with **no cloud
credentials** and create nothing: every run is `command = plan`.

```bash
terraform init -backend=false -lockfile=readonly
terraform test
```

| File | What it checks |
| --- | --- |
| `validation.tftest.hcl` | Each root input validator accepts what it should and rejects what it should (`expect_failures`), including `enable_portal` refused in public mode |
| `root.tftest.hcl` | Composition: default names, tag merge order, Front Door only when `public_access && enable_waf`, the `publicNetworkAccess` value per mode |
| `apim.tftest.hcl` | `modules/apim` on its own: GET-only OpenAPI with no `/healthz` or portal routes, the six catch-all method-guard operations, every MCP tool backed by a GET operation, the keyless portal API (private mode only, GET only, its own method guard), public-mode token validation and rate limiting, no body reads, 0-byte body logging |
| `network.tftest.hcl` | `modules/network` on its own: the subnet carve, and that the Container Apps NSG admits only APIM, the subnet itself, and load balancer probes, ahead of a VNet-wide deny |

## How the providers are faked

- `azurerm` and `random` are `mock_provider`s. `mocks/azurerm.tfmock.hcl`
  gives `azurerm_client_config` real-looking GUIDs, because the provider still
  validates planned values.
- `azapi` is **not** mocked. `avm-res-app-managedenvironment` opens an
  ephemeral `azapi` resource, and Terraform's provider mocking does not
  support ephemeral resources yet. The real provider is configured so it
  cannot authenticate: a dummy client ID and secret, and CLI, managed
  identity, OIDC, and workload identity all off. The suites are plan-only, so
  it is never asked to call Azure.
- In root-level runs, `module.container_apps` is replaced with fixed outputs
  (`override_module`) for the same ephemeral-resource reason. Its internals
  (read-only mount, ingress IP restriction, sync job) are therefore **not**
  covered here.

## What this does not prove

This is still evidence rung 0 (README, "Status"). A mocked plan checks this
module's own logic and the values it hands to providers. It does not check
that Azure accepts them, that `depends_on` ordering holds during a real
apply, or anything about APIM's runtime behaviour. Those are what `measure/`
and a real apply are for.
