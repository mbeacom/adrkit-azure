# adrkit-azure

Terraform for running the [adrkit](https://github.com/mbeacom/adrkit)
read-only decision server on Azure, behind API Management. It serves a team's
architecture decision records as a REST API, as remote MCP tools, and (in
private mode) as the decision portal, all from git and none of it writable.

This repository implements
[ADR-0056](https://github.com/mbeacom/adrkit/blob/main/docs/adr/0056-ship-the-azure-deployment-surface-as-terraform-in-a-separate-repository-behind-a.md).
It deploys the server of
[ADR-0055](https://github.com/mbeacom/adrkit/blob/main/docs/adr/0055-serve-a-read-only-rest-api-over-the-sdk-in-the-oci-image-and-reach-mcp-clients-t.md),
which also serves the portal of
[ADR-0054](https://github.com/mbeacom/adrkit/blob/main/docs/adr/0054-publish-a-static-decision-portal-for-github-pages-built-outside-the-cli-from-the.md).

## Status: skeleton, not deployable yet

- **The server is released; this deployment of it has not run.** The
  `server` selector of `ghcr.io/mbeacom/adrkit` (ADR-0055,
  [adrkit#314](https://github.com/mbeacom/adrkit/pull/314)) first shipped in
  v0.20.0 (tag commit `d94698c`). `image_tag` is required, has no default,
  and refuses tags below v0.20.0.
- **There is no sync image.** The corpus sync job runs a placeholder image
  (`sync_image`) that writes nothing.
- **Nothing here has been applied.** CI runs `terraform fmt`, `init
  -backend=false`, and `validate`, which check syntax, types, and provider
  schemas only. Under adrkit's evidence ladder
  ([ADR-0014](https://github.com/mbeacom/adrkit/blob/main/docs/adr/0014-stage-phase-landing-evidence-across-a-three-rung-validation-ladder.md))
  this is **rung 0**: no unit, reference, or external evidence.
- ADR-0056 is **proposed**, not ratified. The rung-1 measurements it needs
  first are scripted in [`measure/`](./measure/README.md) and have not been
  run; results go in [`measure/RESULTS.md`](./measure/RESULTS.md).

The `TODO(...)` comments in the code list every placeholder; the full list is
at the end of this file.

## Architecture

```text
                       public_access = false (default)          public_access = true
                       -------------------------------          --------------------
 client in a peered    ---> APIM private endpoint               Internet ---> [Front Door Premium + WAF]
 / linked network           (privatelink.azure-api.net)                        (optional, Private Link)
                                     |                                            |
                                     v                                            v
            +----------------------------------------------------------------------------+
            | APIM Standard v2                                                            |
            |   REST API  /adrkit/...       GET only (policy returns 405 otherwise)        |
            |   MCP API   /adrkit-mcp       type "mcp", tools -> the GET operations         |
            |   public mode adds: validate-azure-ad-token, rate-limit-by-key               |
            |   publicNetworkAccess: Disabled (private) / Enabled (public)  [second step]  |
            +----------------------------------------------------------------------------+
                                     | outbound VNet integration
                                     | (subnet delegated to Microsoft.Web/serverFarms)
                                     v
            +---------------------------------- VNet ------------------------------------+
            |  Container Apps environment (workload profiles, INTERNAL in both modes)   |
            |    server app   ghcr.io/mbeacom/adrkit:<image_tag>  args: ["server"]      |
            |                 ADRKIT_SERVER_HOST=0.0.0.0, port 8080, min replicas 1     |
            |                 ADRKIT_SERVER_ROOT=/corpora, CORPORA=<repos keys>         |
            |                 /corpora  <- Azure Files, mounted READ-ONLY               |
            |    sync job     Schedule trigger, writes /corpora/<key>/ (READ-WRITE)     |
            |                 TODO placeholder image                                    |
            |                                                                           |
            |  private endpoints: APIM gateway, Azure Files, Key Vault                  |
            |  private DNS: azure-api.net, file.core.windows.net, vaultcore.azure.net,  |
            |               and the environment's own default domain                    |
            +---------------------------------------------------------------------------+
                Log Analytics + Application Insights        Key Vault (GitHub App key)
```

### The network boundary around the server

The server binds `127.0.0.1` by default and authenticates no one (ADR-0055
clause 14). This deployment sets `ADRKIT_SERVER_HOST=0.0.0.0` only because
APIM is the only route in, and three layers make that true:

1. **Internal environment.** The Container Apps environment has no public
   endpoint in either mode.
2. **NSG on the Container Apps subnet.** Inbound from the VNet is limited to
   the APIM integration subnet on the ingress ports (80/31080, 443/31443),
   plus Azure Load Balancer probes (30000-32767) and traffic within the
   subnet, following Microsoft Learn's rule table for workload-profile
   environments. A final rule denies the rest of the VNet, so other subnets
   and peered networks cannot reach the app. (The server's ingress has to be
   "external" in Container Apps terms, which in an internal environment means
   VNet-reachable; "internal" ingress would shut APIM out.)
3. **Ingress IP restriction.** The server app's ingress allows only the APIM
   integration subnet's CIDR.

If you change the networking so that anything else can reach the app, remove
`ADRKIT_SERVER_HOST`.

### Modules

| Module | What it creates |
| --- | --- |
| `modules/network` | VNet; subnets for the environment (NSG admitting only APIM), APIM integration (with NSG), and private endpoints; Private DNS zones for APIM, Files, Key Vault |
| `modules/observability` | Log Analytics workspace, Application Insights |
| `modules/identity_secrets` | User-assigned identity for the sync job, Key Vault (RBAC, private endpoint, public access off), Key Vault Secrets User role |
| `modules/storage` | Storage account (public access off) with the `corpora` Files share and its private endpoint |
| `modules/container_apps` | Environment via AVM `avm-res-app-managedenvironment` 0.5.1; server app (native `azurerm_container_app`); sync job via AVM `avm-res-app-job` 0.2.2; the environment's private DNS zone |
| `modules/apim` | APIM v2 (globally unique name: random suffix or `apim_name`), outbound integration and the `publicNetworkAccess` step (azapi), private endpoint, backend, product, REST API imported from the server's vendored OpenAPI document, with catch-all method-guard operations and a private-mode portal wildcard, MCP API and tools (azapi), policies from XML templates, Application Insights logger and service diagnostic (no body logging) |
| `modules/frontdoor` | Optional Front Door Premium with WAF, Private Link origin to APIM (endpoint name: random suffix or `frontdoor_endpoint_name`); only when `public_access && enable_waf` |

## Prerequisites

- Terraform `>= 1.10` (the environment AVM module uses an ephemeral
  resource). CI uses 1.13.3.
- Providers, pinned in `versions.tf` and the committed lock file:
  `hashicorp/azurerm >= 4.73.0, < 5.0.0` (the AVM modules require 4.x;
  azurerm 5.x exists and is not used), `Azure/azapi ~> 2.12`,
  `hashicorp/random ~> 3.5`. The AVM modules also pull `Azure/modtm`; its
  telemetry is turned off (`enable_telemetry = false`).
- An Azure subscription and an identity that can create the resources above,
  assign `Key Vault Secrets User`, and join the delegated subnets. Resource
  providers `Microsoft.App`, `Microsoft.ApiManagement`, `Microsoft.Web` (for
  the APIM subnet delegation), `Microsoft.Network`, `Microsoft.Storage`,
  `Microsoft.KeyVault`, `Microsoft.OperationalInsights`, and `Microsoft.Cdn`
  (Front Door only) registered.
- An adrkit image that contains the `server` selector: v0.20.0, the first
  release with it, or later.
- A sync image (not yet available).
- For private repositories: a GitHub App with `contents: read` on those
  repositories only. Put its private key in Key Vault yourself; Terraform never
  handles it (it would land in state).
- A backend for state. None is configured here; add one in your fork.
- Something on the private network to apply from and to call the gateway from
  in private mode. Once `publicNetworkAccess` is `Disabled`, the gateway is
  reachable only through its private endpoint, and the Key Vault and storage
  data planes are private from the start.

This repository configures its providers in the root (`providers.tf`), so it
is meant to be forked or applied as a root configuration. Calling it as a
child module works but rules out `count`, `for_each`, and `depends_on` on the
module call.

## Usage

```hcl
# terraform.tfvars (example; not committed)
location             = "eastus2"
name_prefix          = "acme"
apim_publisher_email = "platform@example.com"
image_tag            = "v0.20.0" # required; v0.20.0 is the first release with the `server` selector

repos = [
  { key = "platform", url = "https://github.com/acme/platform", ref = "main" },
  { key = "payments", url = "https://github.com/acme/payments", private = true },
]
```

```bash
terraform init
terraform plan
terraform apply
```

`image_tag` must be an immutable `vX.Y.Z` tag, optionally with
`@sha256:<digest>`. `latest` and the moving major tag (`v0`) are refused by
validation (ADR-0056 clause 2). So is any tag below `v0.20.0`, the first
release with the `server` selector. Pinning a digest as well
(`v0.20.0@sha256:<digest>`) is accepted and makes the pin immutable even if
the tag were moved.

`repos` needs at least one entry: the server refuses to start with no corpus.

### How the server and the sync job meet

The server is configured from `repos` and the share's mount path (ADR-0055
clause 6, `packages/server/src/config.ts` in adrkit):

| Variable | Value |
| --- | --- |
| `ADRKIT_SERVER_ROOT` | `/corpora`, the read-only Azure Files mount |
| `ADRKIT_SERVER_CORPORA` | the `repos[].key` values joined with `,` (the server's `key[=dir],...` list form, bare keys) |
| `ADRKIT_SERVER_HOST` | `0.0.0.0` (see the network boundary above) |
| `ADRKIT_SERVER_PORT` | `8080` |

A bare key resolves to `<root>/<key>`, so the sync job must write, for each
repository:

```text
/corpora/<key>/docs/adr/...            the records, at their repository paths
/corpora/<key>/.adrkit-corpus.json     {"commit": "<40 hex>"}, written last
```

through ADR-0056 clause 4's `<key>.next/` two-move swap. A key cannot
contain `.`, so `<key>.next` never collides with a corpus. A corpus
directory that does not exist yet is accepted at start; a present directory
with a missing or invalid sidecar answers `503`.

## The two modes

`public_access` changes the gateway only. The Container Apps environment is
internal in both modes, so flipping it never recreates the backend, and the
routes and tools are identical.

### `public_access = false` (default): fully private

- APIM Standard v2 with an **inbound private endpoint** and **outbound VNet
  integration** into a dedicated delegated subnet. Microsoft documents that
  combination as end-to-end network isolation.
- After the private endpoint exists, `publicNetworkAccess` is set to
  `Disabled` (the two-step apply below).
- The decision portal is published under the REST API's path: each corpus
  at `/adrkit/portal/<key>/`, forwarded by one wildcard `GET /portal/*`
  operation. `/adrkit/` redirects there when `repos` has exactly one entry
  and lists the portals otherwise. The server's links and redirect are
  relative, so the `/adrkit` base path survives.
- Callers authenticate with an APIM subscription key on the `adrkit` product.
- The default gateway host name resolves to the private endpoint only from
  networks linked to the `privatelink.azure-api.net` zone. A private custom
  domain needs an Application Gateway in front and is out of scope (ADR-0056
  clause 10).
- The sync schedule is the only trigger.

### `public_access = true`: deliberately public

Everything above, plus, on every API:

- `validate-azure-ad-token` against `entra_tenant_id` and `entra_audience`
  (both required in this mode);
- `rate-limit-by-key` keyed on the token's subject, with separate counters
  for the REST API (`rest:`) and the MCP API (`mcp:`), because a tool call
  runs both policies;
- optionally (`enable_waf = true`) Azure Front Door Premium with a WAF policy,
  reaching APIM over Private Link. Off by default.

The portal (`/` and `/portal/...`) is **left out** in public mode: a browser carries no bearer
token, so the token policy would make it unreachable anyway. Serving it
publicly needs an interactive sign-in in front, which is a later change
(ADR-0056 clause 8).

## The two-step apply for `publicNetworkAccess`

Azure allows disabling APIM public network access only on an existing instance
and only after a private endpoint exists (Microsoft Learn, verified
2026-10-10). One `terraform apply` therefore runs these steps in order:

1. `azurerm_api_management` is created with public access **enabled**
   (required at creation).
2. `azapi_update_resource.outbound` sets outbound VNet integration.
3. `azurerm_private_endpoint.gateway` and its DNS zone group are created.
4. The `publicNetworkAccess` step. It is one of two resources, and which one
   exists decides where it sits relative to the policies:
   - **`public_access = false`:** `disable_public_access` sets `Disabled`
     **before** the APIs, policies, logger, backend, and product bindings are
     created or changed; they all depend on it.
   - **`public_access = true`:** `enable_public_access` sets `Enabled`
     **after** the policies (Entra validation and rate limiting), the
     method-guard operations, the diagnostic, and the product bindings; it
     depends on them.
5. In both modes the product bindings depend on the policies, so a product
   subscriber never reaches an API before its policy exists.

That makes both flips safe in one apply:

- **false to true:** the attached APIs get the public-mode policies first;
  only then does the gateway open.
- **true to false:** the gateway closes first; only then are the public-mode
  policies relaxed.

Only one of the two resources exists at a time (`count`). Removing the other
does nothing, because destroying an `azapi_update_resource` never reverts a
property. azurerm ignores `public_network_access_enabled` and the virtual
network attributes after creation (`lifecycle.ignore_changes`), so a later
plan does not revert step 4.

**The windows are real.**

- *Private mode, first apply:* between steps 1 and 4 the new instance is
  publicly addressable, with no API attached, so there is nothing to call.
- *Public mode, first apply:* the instance is public from creation, so
  between each API's creation and its policy's, the API exists without its
  policy. Every API requires a subscription key and joins the product only
  after its policy, so in that window it answers only to APIM's built-in
  all-access subscription key, an administrator credential. Unmeasured.

ADR-0056 clause 7 also asks for a global deny-all `ip-filter` from creation;
the skeleton does not add one, because a global deny-all would also block
callers on the private endpoint and has to be removed again in the same
apply. The ordering above is the mechanism here.

**Standard v2 caveat.** The maintainer states that Standard v2 supports
disabling `publicNetworkAccess` once the private endpoint exists. Microsoft
Learn still shows only the portal for Standard v2 (and the REST property for
classic tiers and Premium v2), so the ARM update in step 4 is **unmeasured**.
ADR-0056 action item 2 is that measurement. If the update fails, step 4 falls
back to the portal (Network, Inbound features, Public network access,
Disable), and ADR-0056 is revisited.

## Read-only invariant

Nothing in this deployment changes a decision record. Recording a person's act
(`accept`, `approve`, `object`, `resolve`) stays a human-run adrkit CLI command
and a pull request (ADR-0044, ADR-0051, ADR-0052).

- The REST API publishes only the `GET` operations of ADR-0055's routes,
  imported from the server's own OpenAPI document (vendored in
  `modules/apim/openapi/`; see the README there for its adrkit commit and how
  to regenerate it).
  APIM matches a request to an operation before API policies run, and an
  unmatched method would end as `404 OperationNotFound`, so the API also has
  catch-all `/*` operations for `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`,
  and `TRACE`. They exist only so the API policy runs and answers `405` with
  `Allow: GET, HEAD`; none is forwarded to the backend or exposed as a tool.
  `/healthz` is probed inside the environment and never published.
- The MCP API is "REST API as MCP server": tools only, each mapped to one of
  the seven `/api/v1` data operations (`listCorpora`, `listRecords`,
  `getRecord`, `getGraph`, `getQueue`, `getIssues`, `getGoverning`); never
  `getHealth`, `getOpenApi`, or a portal operation. CI
  (`scripts/check-openapi-tools.sh`) fails if a tool's operation is missing
  from the vendored document or is not a `GET /api/v1/...` operation. MCP's streamable HTTP transport uses `POST`, so the
  method guard is on the REST API, not the MCP API; a tool call still lands on
  a `GET` operation and passes the REST API's guard.
- The server mounts the corpus share through a **read-only** environment
  storage definition. Only the sync job mounts it read-write.
- No policy reads `context.Response.Body`, and the Application Insights
  diagnostic logs 0 bytes of request and response bodies for every API, the
  MCP API included (body logging would buffer streamed responses).
- The public-mode GitHub webhook in ADR-0056 clause 9 would be the one
  non-`GET` route, and it could only **start the sync job** (ARM `jobs/start`,
  no payload forwarded, APIM's identity holding only
  `Microsoft.App/jobs/start/action` on that job). **It is not built.** It
  waits on measuring HMAC verification in APIM policy (ADR-0056 action item
  5), and is dropped rather than weakened if that fails.

## Cost notes

No prices here; check the Azure pricing pages for your region before the first
`terraform apply`. These lines accrue **whether or not anything calls the
API**:

- **APIM Standard v2**: a fixed monthly charge per unit, the largest fixed
  line. Premium v2 costs much more.
- **Private endpoints**: three (APIM, Files, Key Vault), each billed hourly
  plus data processed.
- **Private DNS zones**: four, billed per zone and per query.
- **Container Apps**: minimum replicas 1 keeps one server replica always
  running; the workload-profiles environment may add its own charge; each
  sync run bills for its duration.
- **Log Analytics / Application Insights**: ingestion and retention.
- **Storage**: the Files share and its transactions (small).
- **Key Vault**: per operation (small).
- **Front Door Premium + WAF** (optional, off by default): the largest
  optional line when enabled.

ADR-0056 action item 6 requires these lines to be published before the first
tagged release; actual figures are not measured.

## Verified vs unverified provider facts

Verified against Microsoft Learn or the Terraform Registry on 2026-10-10:

- APIM Standard v2 supports an inbound private endpoint; combined with
  outbound VNet integration it is documented as end-to-end isolation.
- Public network access can be disabled only after a private endpoint exists,
  and only on an existing instance.
- v2 outbound integration needs a dedicated subnet (minimum /27), delegated to
  `Microsoft.Web/serverFarms`, with an NSG that allows outbound 443 to
  `AzureKeyVault`.
- "REST API as MCP server" is an API of type `mcp` with `apis/tools`
  children whose `operationId` is the backing operation's ARM ID, at API
  version `2025-09-01-preview` or later. azurerm has no native resource;
  Microsoft documents `azapi_resource`.
- azurerm's `public_network_access_enabled` is documented as management plane
  only and required `true` at creation.
- Registry: azurerm 4.81.0 is the newest 4.x (5.x exists);
  azapi 2.13.0; `avm-res-app-managedenvironment` 0.5.1 requires azapi
  `~> 2.12` and azurerm `~> 4.0`; `avm-res-app-job` 0.2.2 requires azurerm
  `>= 4.73.0, < 5.0.0`. An APIM AVM module (`avm-res-apimanagement-service`
  0.9.0) also exists; it is not used here because the `publicNetworkAccess`
  step and outbound integration need direct control.

Unverified (nothing has been applied). The first six items are what
[`measure/`](./measure/README.md) measures:

- The ARM `publicNetworkAccess` update on Standard v2 (stated by the
  maintainer; ADR-0056 action item 2).
- The ARM shape used for v2 outbound integration
  (`virtualNetworkType = "External"` with
  `virtualNetworkConfiguration.subnetResourceId`) at API version
  `2024-05-01`, and whether azurerm's own attributes could express it.
- That APIM names operations imported from OpenAPI after their `operationId`,
  which the MCP tool references assume.
- The `<key>.next/` two-move swap on an Azure Files (SMB) share under
  ADR-0055's reload (ADR-0056 action item 3).
- HMAC verification of `X-Hub-Signature-256` in APIM policy (action item 5).
- Whether APIM's MCP server passes MCP protocol revision `2026-07-28`.
- Front Door's Private Link origin to APIM v2 and the managed rule set
  version.
- That the Container Apps ingress IP restriction sees the APIM integration
  subnet's address as the client IP (it should, since traffic stays in the
  VNet), and that the NSG rule table is complete for this environment (it
  follows Microsoft Learn's workload-profile table).
- That APIM accepts the portal's `GET /portal/*` wildcard template
  (Microsoft Learn documents `/*`; a wildcard after a literal segment is not
  shown), and how it forwards the trailing slash of `/portal/<key>/` and of
  the API root `/adrkit/` (the server's matcher is segment-exact, so
  `/portal/<key>` without the slash is a backend `404`). Also whether a
  re-import of the OpenAPI document leaves the separately created operations
  (portal wildcard, method guard) in place.
- That the `/*` catch-all operations take precedence the way the method
  guard assumes, and that APIM resolves the true/false ordering exactly as
  described above (dependency order is Terraform's; the policy behaviour is
  APIM's).
- azapi schema validation of the request bodies, and azurerm's acceptance of
  `sku_name = "StandardV2_1"`: both are checked at plan time with real values,
  which CI does not do (`validate` sees variables as unknown).

## TODO list

| Tag | Where | What |
| --- | --- | --- |
| `TODO(sync-image)` | root `sync_image`, `modules/container_apps` | No sync image exists; the job runs a placeholder |
| `TODO(sync-contract)` | `modules/container_apps` | Sync job env var names are a proposal, not a contract (the on-share layout `<root>/<key>/docs/adr`, `<root>/<key>/.adrkit-corpus.json` is fixed by the server) |
| `TODO(github-app)` | `modules/container_apps` | GitHub App ID and installation ID are not wired |
| `TODO(webhook)` | `modules/apim` | Public-mode webhook not built, pending HMAC measurement |
| `TODO(egress)` | `modules/network` | Outbound restrictions for the APIM integration subnet and the environment |
| `TODO(rung-1)` | `modules/storage` | Measure the two-move swap on Azure Files (scripted in `measure/azure-files-swap`, not yet run) |
| `TODO(frontdoor-approval)` | `modules/frontdoor` | Approve the Private Link connection on APIM |
| `TODO(frontdoor-lockdown)` | `modules/frontdoor` | Restrict APIM to Front Door traffic when Front Door is in front |
| `TODO(frontdoor-probe)` | `modules/frontdoor` | Confirm the health probe path |
| `TODO(waf-rules)` | `modules/frontdoor` | Confirm the managed rule set type and version |

Also outstanding from ADR-0056: the drift CI job (run the pinned image's
`server` selector over a fixture corpus and assert the commit and the 503 on a
missing sidecar, observed failing first), Dependabot or Renovate for image-tag
bumps, and a state backend.

## License

Apache-2.0. See [LICENSE](./LICENSE).
