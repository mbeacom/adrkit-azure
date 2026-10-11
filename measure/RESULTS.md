# Rung-1 results for ADR-0056

Fill this in from `measure/results/<run id>/summary.txt` after a run (see
[README](./README.md)). One section per measurement. Each names the ADR-0056
clause it confirms or refutes, and what to change in the ADR if it refutes it.
Paste raw output where asked; summarise everything else.

Status values: **confirmed** (all checks PASS), **refuted** (a FAIL that
contradicts the ADR), **inconclusive** (an ERROR, or not run).

## Run

| Field | Value |
| --- | --- |
| Date (UTC) | |
| Run id | |
| Operator | |
| Region | |
| Subscription type (no ID) | |
| Terraform | |
| azurerm / azapi / random | 4.81.0 / 2.13.0 / 3.9.1 (from the lock files) |
| Azure CLI | |
| MCP Inspector | 2.8.0 |
| adrkit-azure commit | |
| Measurements run | |

## 1. `public-network-access`

Confirms or refutes: ADR-0056 Context fact 5 ("Unverified, load-bearing":
an ARM update of `publicNetworkAccess` on Standard v2), **clause 7**, action
item 2 (first half), and two "How we would know this was wrong" lines: "the
`publicNetworkAccess` update failing on Standard v2" and "a plan that reverts
the flip".

| Check | Step 1 (false) | Step 2 (true) | Step 3 (false) |
| --- | --- | --- | --- |
| apply succeeded | | | |
| ARM `publicNetworkAccess` (value, seconds to take effect) | | | |
| `az apim show` value | | | |
| outside probe (curl rc, HTTP status, seconds) | | | |
| plan after apply exits 0 | | | |

| Check | Result |
| --- | --- |
| azapi outbound integration body took effect (`virtualNetworkType`, subnet) | |

**Status:** confirmed / refuted / inconclusive

If refuted: clause 7 falls back to the documented portal step (Network,
Inbound features, Public network access, Disable), the top-level README's
"Standard v2 caveat" becomes a measured fact, and ADR-0056 is revisited as
clause 7 says. If only the plan check fails, read which resource the plan
names: a diff on `azurerm_api_management.this` means `ignore_changes` in
`modules/apim` is wrong; a diff on an `azapi_update_resource` means ARM
normalised the body (for example the subnet ID's casing), so the azapi body
needs to match what ARM returns. Neither refutes the flip itself.

Raw evidence (`public-network-access.probes.log`, the failing step's plan
or apply error):

```text
```

## 2. `outbound-integration`

Confirms or refutes: ADR-0056 Context fact 5 ("Unverified. Whether azurerm's
`virtual_network_type` and `virtual_network_configuration` express v2
outbound integration at all"), **clause 12** ("azapi ... for v2 outbound
integration if azurerm cannot express it"), action item 2 (second half).

| Check | Result |
| --- | --- |
| plan action for the imported instance (`no-op` or `update`) | |
| attributes the plan would change | |

**Status:** azurerm can represent it / azapi required / inconclusive

Remember the limit: plan shows whether azurerm reads the integration back,
not whether ARM accepts azurerm's own create or update. If azurerm reads it,
clause 12 may say azurerm *can* express it, and moving `modules/apim` off azapi
for integration is optional and would need that apply measured first. If not,
clause 12 stands as written.

Raw evidence (`outbound-integration.plan.txt`, relevant lines):

```text
```

## 3. `azure-files-swap`

Confirms or refutes: ADR-0056 **clause 4** (the `<key>.next/` two-move swap,
"whether directory rename on Azure Files (SMB) behaves this way ... is
unmeasured and is the first rung-1 item"), action item 3, and "a sync that a
load observes half-written".

| Check | Writer | reader-same | reader-cross |
| --- | --- | --- | --- |
| swaps completed / requested | | | |
| move1 / move2 / restore failures | | | |
| `rm -rf` of old tree failures | | | |
| absence window between moves (max / mean ms) | | | |
| loads (accepted / total) | | | |
| torn | | | |
| sidecar invalid / missing in tree | | | |
| failed in window (absent / mid-load) | | | |
| rejected because commit moved | | | |

**Status:** confirmed / refuted / inconclusive

If refuted by torn > 0 or an invalid sidecar: the swap does not keep a load
from seeing half a sync on SMB; clause 4 (and ADR-0055 clause 5) need another
mechanism. If refuted by move failures: the two moves themselves are not
reliable on SMB under reads, and clause 4 needs a retry or a different
layout. The window counts are expected and do not refute anything.

Raw evidence (any `TORN`, `SIDECAR_*`, or `*_FAIL` lines from the logs):

```text
```

## 4. `mcp-2026`

Confirms or refutes: ADR-0056 Context fact 5 ("Unverified. Whether APIM
passes MCP protocol revision `2026-07-28`"), **clause 6** (REST API as MCP
server), the Revisit-if "APIM is measured against a `2026-07-28` client", and
ADR-0055 clause 15 and action item 8. Side check: the skeleton's
operation-naming assumption (`local.mcp_tools` in `modules/apim`).

| Check | legacy (2025) | modern (2026-07-28) | auto |
| --- | --- | --- | --- |
| `tools/list` lists `getHello` | | | |
| `tools/call getHello` returns the stub body | | | |

| Check | Result |
| --- | --- |
| MCP endpoint that answered | |
| names APIM gave the imported operations | |
| tool create against `.../operations/getHello` | |
| raw `initialize`: status, `Mcp-Session-Id` present | |

**Status:** both eras / 2025 era only / 2026-07-28 only / neither /
inconclusive

Read the status from the `tools/list` row (the script records PASS or FAIL per
era independently, so any combination can appear):

| legacy | modern | Status | What it means |
| --- | --- | --- | --- |
| PASS | PASS | both eras | APIM serves 2025-era and stateless `2026-07-28` clients. ADR-0055 clause 15's open question closes in APIM's favour. |
| PASS | FAIL | 2025 era only | A `2026-07-28`-only client cannot use the APIM path. Say so in both ADRs and the adrkit-azure README; ADR-0055's deferred native transport (its Option B) becomes the route for modern-only clients. |
| FAIL | PASS | 2026-07-28 only | 2025-era clients, today's majority, cannot use it. Check the legacy `.stderr` first: a 2025 failure on a gateway that serves 2026 is surprising enough to rule out a harness or endpoint problem (the endpoint probe tries both eras) before recording it. If it holds, ADR-0056 clause 6 must say APIM's MCP path is modern-only, and the README must tell 2025-era clients to wait. |
| FAIL | FAIL | neither | Check the stub row and the endpoint row first; if both are fine, APIM's MCP path does not work with this Inspector, which refutes clause 6 as written. |

`auto` should match whichever era the server accepts first; an `auto` result
that disagrees with both explicit eras is recorded but does not change the
status.

**The era verdict rests on `tools/list`** (and the raw `initialize`). The
stub has no backend; its answer comes from an API-level `return-response`
policy. If APIM's MCP path does not run the REST API's inbound policy,
`tools/call` fails in every era alike while `tools/list` passes. A `tools/call`
failure that is uniform across all three eras points at the backend-less stub,
not the protocol: set `service_url` on `azurerm_api_management_api.stub` to any
reachable HTTPS host and rerun `--only mcp-2026` to tell them apart.

Either answer is useful: ADR-0055 clause 15 already says which revisions APIM
serves is APIM's. Record the result in both ADRs. If modern fails, say so in
the adrkit-azure README and in ADR-0055's clause 15 text, so a 2026-only
client knows. If the tool create failed, change how `modules/apim` builds its
tool references (`local.mcp_tools`) before the first real apply.

Raw evidence (`mcp-2026.modern.tools-list.json` and its `.stderr`, and the
same for any failing era):

```text
```

## 5. `hmac-policy`

Confirms or refutes: ADR-0056 Context fact 5 ("whether a GitHub
`X-Hub-Signature-256` HMAC can be verified inside an APIM policy"), **clause
9**, action item 5.

| Case | Expected | Observed |
| --- | --- | --- |
| APIM accepted the policy | yes | |
| correct signature | 200 | |
| signature from another secret | 401 | |
| no signature header | 401 | |
| body changed after signing | 401 | |
| `sha1=` prefix | 401 | |
| correct, non-ASCII UTF-8 body | 200 | |
| correct, empty body | 200 | |
| correct, about 1 MiB body | 200 | |

**Status:** confirmed / refuted / inconclusive

If APIM rejected the policy, or any 401 case answered 200: clause 9's
condition is met, and the webhook is dropped rather than weakened. If only the
1 MiB case failed: GitHub payloads can exceed it, so record the observed limit
and decide whether a webhook that rejects large deliveries (falling back to the
schedule) is acceptable.

Raw evidence (`hmac-policy.terraform.log` error, if any):

```text
```

## Outcome for ADR-0056

| Action item | Outcome | ADR edit needed |
| --- | --- | --- |
| 2. `publicNetworkAccess` update; azurerm outbound integration | | |
| 3. two-move swap on Azure Files | | |
| 5. HMAC in APIM policy (webhook kept or dropped) | | |
| (ADR-0055 item 8) APIM MCP eras | | |

Teardown: no leftovers reported / leftovers removed by hand (list).
