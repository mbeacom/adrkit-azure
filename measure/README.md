# Rung-1 measurements for ADR-0056

These are the measurements
[ADR-0056](https://github.com/mbeacom/adrkit/blob/main/docs/adr/0056-ship-the-azure-deployment-surface-as-terraform-in-a-separate-repository-behind-a.md)
needs before it can be ratified
([mbeacom/adrkit#297](https://github.com/mbeacom/adrkit/issues/297)). Each one
is a small Terraform root plus a script that applies it, observes, asserts,
and destroys it. `run.sh` runs them one at a time against a throwaway resource
group.

**This creates real, billed Azure resources.** Nothing here has been run yet;
CI only checks `terraform fmt`, `init -backend=false`, and `validate` on each
root, plus `shellcheck` on the scripts.

## What each measurement proves

| Measurement | Question | ADR-0056 |
| --- | --- | --- |
| [`public-network-access`](./public-network-access) | Does the `azapi_update_resource` flip of `publicNetworkAccess`, exactly as `modules/apim` makes it, work on an existing **Standard v2** instance with a private endpoint, in both directions? Does the gateway really close and open to a caller outside the VNet? Does a plan after each apply stay empty? | Context fact 5 (unverified, load-bearing), clause 7, action item 2 (first half) |
| [`outbound-integration`](./outbound-integration) | Can azurerm's `virtual_network_type` / `virtual_network_configuration` represent v2 **outbound** VNet integration, or is `azapi` required? Plan only, against the instance above. | Context fact 5, clause 12, action item 2 (second half) |
| [`azure-files-swap`](./azure-files-swap) | On an Azure Files (SMB) share, does the sync job's write-aside-then-two-moves swap ever let a reader following ADR-0055 clause 5 accept a half-written tree? Do the moves fail while reads are in flight? | Clause 4, action item 3 |
| [`mcp-2026`](./mcp-2026) | Which MCP protocol eras does APIM's "REST API as MCP server" serve: the 2025 era, the stateless `2026-07-28` era, both? | Context fact 5, clause 6, Revisit-if; ADR-0055 clause 15 and action item 8 |
| [`hmac-policy`](./hmac-policy) | Can an APIM policy verify GitHub's `X-Hub-Signature-256` HMAC over the raw body, with the secret in a secret named value? | Context fact 5, clause 9, action item 5 |

### Per measurement

**1. `public-network-access`** reuses `modules/network` unchanged and mirrors
`modules/apim` steps 1 to 4 (same resource types, API version `2024-05-01`,
bodies, count-gated disable/enable pair, and `ignore_changes`). It is not a
module call, because `modules/apim` also builds the MCP preview API, policies,
a backend, and a logger, and a failure in any of them would confound the
answer. Keep the two in sync. The script applies `public_access=false`, then
`true`, then `false`, and after each:

- polls `properties.publicNetworkAccess` from ARM (a direct GET at the flip's own
  API version) until it equals the expected value, and records how long that
  took; also records `az apim show`'s view;
- probes `https://<gateway>/status-0123456789abcdef` from your machine.
  `Enabled` passes on any HTTP answer except 403; `Disabled` passes on no
  answer or 403. Every probe is logged raw, so you can reinterpret it;
- runs `terraform plan -detailed-exitcode`, which must exit 0. Exit 2 is the
  ADR's own falsifier, "a plan that reverts the flip".

After the first apply it also reads back the outbound integration azapi set
(`virtualNetworkType`, `subnetResourceId`). That checks the azapi body the
skeleton uses, which the top-level README lists as unverified.

It does **not** measure clause 7's ordering of API attachment around the flip;
no API is attached here.

**2. `outbound-integration`** imports the instance above into an
`azurerm_api_management` that declares `virtual_network_type = "External"`
with the integration subnet, and reads the plan as JSON. Nothing is applied.
An import with no update means azurerm reads the azapi-set integration back.
An update to `virtual_network_*` means it does not. **Plan cannot show whether
ARM would accept azurerm's own create or update call** for a v2 SKU; see "What
cannot be scripted".

**3. `azure-files-swap`** creates a storage account and Files share, a
Container Apps environment (reusing `modules/observability` for logs), and two
jobs running [`swap.sh`](./azure-files-swap/swap.sh):

- the **writer** seeds a tree, then performs 300 swaps: write `demo.next/`
  (40 files, then `.adrkit-corpus.json` last), `mv demo demo.old.N`,
  `mv demo.next demo`, `rm -rf demo.old.N`. It also runs a same-client reader
  in the background;
- the **reader** is a separate replica with its own SMB mount, as the server
  is, and loads in a loop the way ADR-0055 clause 5 does: read the sidecar,
  read every file, read the sidecar again, keep the load only if the commit did
  not move.

A load is **torn** when the commit did not move but some file is from another
generation. The script asserts torn, invalid sidecars, and trees without a
sidecar are all zero, that every swap completed, and that no move failed. The
absence window between the two moves, and loads that failed inside it, are
recorded, not failed: clause 4 expects that window and says clause 5
survives it.

The storage account allows public network access and shared-key auth and has
no private endpoint, unlike `modules/storage`: the environment here has no
VNet, and SMB rename semantics do not depend on which endpoint carries the
traffic. The reader models clause 5's reload; ADR-0055's server itself does
not exist yet, so its real reload is not exercised.

The harness was checked locally (not on SMB): on a local filesystem 200
swaps gave zero torn loads, and a planted writer that rewrites files in place
with the sidecar first gave over 1,500 torn loads per reader, so the reader
does catch a half-written tree.

**4. `mcp-2026`** creates a public Standard v2 instance with a stub REST API
(one `GET /hello`, imported from OpenAPI, answered by a `return-response`
policy, no backend), an API of type `mcp` with one tool created exactly the
way `modules/apim` creates its tools, and an all-APIs subscription. The script
checks the stub answers as plain REST, records the names APIM gave the imported
operations, finds the MCP endpoint (`<path>/mcp`, then `<path>`), and drives it
with the official MCP Inspector CLI
(`@modelcontextprotocol/inspector@2.8.0`, as ADR-0018's run used; override with
`INSPECTOR_VERSION`) at `--protocol-era legacy`, `modern`, and `auto`. Each
era passes if `tools/list` lists `getHello` and `tools/call getHello` returns
the stub's body. It also saves one raw `initialize` response, noting whether
APIM sent an `Mcp-Session-Id`.

The era verdict rests on `tools/list`. The stub's answer comes from a policy,
not a backend, so a `tools/call` failure in all three eras alike may mean
APIM's MCP path skips the REST API's policy rather than an era failure;
[`RESULTS.md`](./RESULTS.md) says how to tell them apart.

As a side effect it tests the skeleton's `TODO(openapi)` assumption: the tool
references the operation by its OpenAPI `operationId`. If APIM names it
differently, the tool's create fails, and that is recorded.

**5. `hmac-policy`** creates a public Standard v2 instance, a secret named
value holding a random hex secret generated per run, and a `POST` operation
whose policy ([`webhook-policy.xml`](./hmac-policy/webhook-policy.xml))
recomputes `sha256=` plus the lowercase hex HMAC-SHA256 of the raw body and
compares it in constant time. The script signs bodies with `openssl` exactly as
GitHub does and expects:

| Case | Expected |
| --- | --- |
| correct signature | 200 |
| signature from another secret | 401 |
| no signature header | 401 |
| body changed after signing | 401 |
| `sha1=` prefix | 401 |
| correct, non-ASCII UTF-8 body | 200 |
| correct, empty body | 200 |
| correct, about 1 MiB body | 200 |

If APIM refuses to save the policy (for example, a type not permitted in policy
expressions), that is recorded as the result, ADR-0056 clause 9's drop
condition, not as a harness error.

## Prerequisites

- `az login` with an identity that can create APIM, networking, storage,
  Container Apps, and Log Analytics resources in the chosen group.
- **A throwaway resource group** you create first, for example
  `az group create --name adrkit-measure-rg --location eastus2`. `run.sh`
  refuses a group that already has resources unless you pass
  `--allow-nonempty-rg`, and it never creates or deletes the group.
- **Quota for APIM Standard v2** in that region. Measurements 1, 4, and 5 each
  create one instance, one at a time, so one unit of Standard v2 quota is
  enough. Check the region offers Standard v2 before you start.
- Resource providers registered for what you select: `Microsoft.ApiManagement`
  (measurements 1, 4, 5); `Microsoft.Network` and `Microsoft.Web` (the APIM
  subnet delegation) for measurement 1; `Microsoft.App`, `Microsoft.Storage`,
  `Microsoft.OperationalInsights`, and `Microsoft.Insights` for measurement 3.
  `run.sh` checks only the ones the selected measurements need, and stops if
  one is not registered.
- For measurements 1, 4, and 5, an APIM publisher email. It defaults to the
  signed-in user; signed in as a service principal, pass `--publisher-email`.
  `--only azure-files-swap` needs none.
- A subscription policy that allows shared-key storage accounts with public
  network access (measurement 3 only).
- Tools: Terraform 1.10 or later (CI uses 1.13.3), Azure CLI with the
  `containerapp` extension (`az extension add --name containerapp`), `jq`,
  `curl`, `perl`, `openssl`, Node.js with `npx` (measurement 4), and
  optionally `dig`. `bash` 3.2 (the macOS default) or later.
- Outbound HTTPS from your machine to `*.azure-api.net` and the npm registry.

## Running

```bash
# Check tools, login, group, and providers; creates nothing, asks nothing.
measure/run.sh --resource-group adrkit-measure-rg --subscription <id-or-name> --preflight-only

# Everything, one measurement at a time.
measure/run.sh --resource-group adrkit-measure-rg --subscription <id-or-name>

# A subset (outbound-integration always runs inside public-network-access).
measure/run.sh --resource-group adrkit-measure-rg --subscription <id-or-name> \
  --only public-network-access,outbound-integration
```

`run.sh` asks you to type the resource group's name before it creates
anything. It never changes your Azure CLI default subscription, and works
when the selected subscription is in a different tenant from the CLI's
active one:

- every subscription-scoped `az` call passes `--subscription` explicitly;
- ARM reads (the `publicNetworkAccess` and integration properties, the
  operation names) use a token from
  `az account get-access-token --subscription <selected>`, which is issued
  for that subscription's tenant, and call ARM with `curl`, not `az rest`
  (which has no `--subscription` and uses the active context). The token is
  passed to `curl` on stdin, not on its command line;
- Terraform gets `ARM_SUBSCRIPTION_ID`.

As a safeguard, the exit handler checks the default is still the one you
started with, and restores it if anything else moved it.

Results go to `measure/results/<run id>/` (gitignored):
`summary.txt` (one line per check: PASS, FAIL, ERROR, or INFO), `run.log`,
each root's Terraform log, and each measurement's raw evidence. **FAIL** means
the observation contradicts what ADR-0056 assumes, and is a result. **ERROR**
means the harness could not observe, so the check is inconclusive. Exit code 3
means at least one FAIL or ERROR.

Copy the outcome into [`RESULTS.md`](./RESULTS.md), which maps each check to
the ADR-0056 clause it confirms or refutes.

## Time and cost

No prices here; check the Azure pricing pages for your region first.

- **Time.** Each APIM Standard v2 instance can take tens of minutes to create,
  and each of the three `publicNetworkAccess` changes can take minutes to
  take effect (the script waits up to 30 minutes for each before it records a
  FAIL). Budget about half a day of wall-clock for a full run. Run subsets in
  separate sessions if that suits you better.
- **Cost.** Three APIM Standard v2 instances, each existing for well under a
  day and never at the same time: the largest line, billed for the time each
  exists. Smaller lines: one private endpoint and four Private DNS zones
  (measurement 1); a storage account, a Container Apps environment with two
  short job runs, and a Log Analytics workspace (measurement 3). Teardown runs
  right after each measurement, so nothing should accrue after the run.

## Teardown

- Each measurement ends with an explicit `terraform destroy` of its own root.
- An `EXIT` trap destroys anything still applied if a step fails, the script
  errors, or you press Ctrl-C (newest first, two attempts each).
- The APIM roots set `purge_soft_delete_on_destroy = true`, so a destroyed
  instance does not stay soft-deleted holding its name.
- At the end, `run.sh` lists any resource still tagged
  `adrkit-measure=<run id>` in the group, and any soft-deleted APIM instance
  from the run, with the purge command.

If a destroy fails, the root's state and `terraform.tfvars.json` are kept in
its directory: run `terraform -chdir=measure/<root> destroy` to retry. Then
delete the resource group itself (`az group delete --name <rg>`); `run.sh`
never does that for you.

The `hmac-policy` secret and the `mcp-2026` subscription key exist only in
that root's local state and tfvars, both deleted after a successful destroy.
They are also passed on command lines (`openssl -hmac`, the Inspector's
`--header`), so they are visible to other users of your machine for the
seconds those commands run. They protect throwaway resources only.

## What cannot be scripted

- **azurerm creating or updating v2 outbound integration itself.**
  Measurement 2 shows whether azurerm *reads* it. Whether ARM accepts
  azurerm's own `virtual_network_type` on create or update for a v2 SKU needs
  a second Standard v2 instance with its own dedicated delegated subnet (a
  subnet serves one APIM instance). Do that by hand only if measurement 2
  fails and the answer would change clause 12.
- **The private side of the gateway.** Measurement 1 probes from outside the
  VNet only. Calling the gateway through its private endpoint needs a machine
  inside the VNet (a VM or Bastion), which this harness does not create.
- **Clause 7's API ordering and the public-mode first-apply window.** Both need
  the full `modules/apim` with APIs and policies, and a way to observe the
  window from outside, which is not a single scripted check.
- **ADR-0055's real reload.** The server does not exist yet
  ([adrkit#296](https://github.com/mbeacom/adrkit/issues/296)). Measurement 3
  models clause 5's rule in shell.
- **The webhook's ARM `jobs/start` call** from APIM's managed identity.
  Measurement 5 covers only the HMAC check that gates it.
- **Assumptions only a real run can check.** If one is wrong the script
  records an ERROR or a FAIL with the evidence, not a false PASS:
  `az containerapp job start --query name` returns the execution name; the MCP
  endpoint is `<path>/mcp` (the script also tries `<path>`); an
  `azurerm_api_management_subscription` with neither `product_id` nor `api_id`
  is scoped to all APIs; `HMACSHA256` and `Body.As<byte[]>` are permitted in
  policy expressions (if not, apply fails on the policy, which is recorded as
  the result); Container Apps accepts `swap.sh` (about 7 KB) as one `args`
  element (if not, pass it in an environment variable piped to `bash`).
- **Reading the results into the ADR.** The verdicts in `RESULTS.md` and any
  edit to ADR-0056 are the maintainer's.
