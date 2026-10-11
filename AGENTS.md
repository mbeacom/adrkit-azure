# AGENTS.md

Guidance for coding agents working in this repository. Read
[README.md](./README.md) for the full design and
[measure/README.md](./measure/README.md) before you touch `measure/`. This
file covers what you need to change code safely, not the design in full.

## What this is

Terraform that deploys the [adrkit](https://github.com/mbeacom/adrkit)
read-only decision server on Azure behind API Management (APIM Standard v2).
It implements ADR-0056 (proposed, not ratified) in mbeacom/adrkit, and serves
ADR-0055's server and ADR-0054's portal.

**It is a skeleton at evidence rung 0.** Nothing has been applied. The server
(`server` selector) first shipped in adrkit v0.20.0, the `image_tag` floor;
the sync image does not exist yet.
CI checks syntax, types, provider schemas, lint rules, static security
findings, and plan-only tests with mocked providers; none of it reaches
Azure. Do not describe anything here as working, deployed, or tested against
Azure.

## Layout

| Path | What it is |
| --- | --- |
| `main.tf` | Composition root: resource group, then `network`, `observability`, `identity_secrets`, `storage`, `container_apps`, `apim`, and `frontdoor` (only when `public_access && enable_waf`) |
| `variables.tf`, `outputs.tf` | Root inputs (validated) and outputs |
| `versions.tf` | Version constraints. The module configures **no** providers; callers do (see `examples/*/providers.tf`) |
| `.terraform.lock.hcl` | Committed lock file, multi-platform |
| `examples/basic`, `examples/advanced` | Runnable callers (private mode; public mode with Front Door). Each is a root with its own `providers.tf` and lock file |
| `tests/` | Plan-only `terraform test` suites and mocks; read `tests/README.md` before adding a run |
| `modules/*/README.md`, `examples/*/README.md` | Prose plus a terraform-docs block between `BEGIN_TF_DOCS`/`END_TF_DOCS` |
| `.tflint.hcl`, `.checkov.yaml`, `trivy.yaml`, `.terraform-docs.yml` | Linter, scanner, and docs configuration |
| `.pre-commit-config.yaml` | Local hooks that run the same commands as CI |
| `.github/workflows/ci.yml`, `security.yml` | CI (fmt, validate, tflint, test, docs, scripts) and security scans (Checkov, Trivy, zizmor) |
| `modules/network` | VNet, three subnets (Container Apps, APIM integration, private endpoints), NSGs, Private DNS zones |
| `modules/observability` | Log Analytics, Application Insights |
| `modules/identity_secrets` | Sync job identity, Key Vault (private), role assignment |
| `modules/storage` | Storage account and `corpora` Files share (private) |
| `modules/container_apps` | Internal environment (AVM), server app, sync job (AVM) |
| `modules/apim` | APIM, outbound integration, private endpoint, `publicNetworkAccess` step, REST and MCP APIs, the private-mode keyless portal API, policies |
| `modules/apim/policies/*.xml.tftpl` | API policies, rendered with `templatefile()` |
| `modules/apim/openapi/adrkit-server.openapi.json` | The server's own `/openapi.json`, vendored from adrkit (source commit and regeneration in that directory's README) |
| `modules/apim/openapi/mcp-tools.json` | operationId to description of the MCP tools; read by `modules/apim` |
| `scripts/check-openapi-tools.sh` | CI check: every MCP tool is a `GET /api/v1` operation in the vendored document |
| `modules/frontdoor` | Optional Front Door Premium + WAF over Private Link |
| `measure/` | Rung-1 measurement harness: five standalone Terraform roots plus bash scripts that create **billed** Azure resources |
| `measure/RESULTS.md` | Template for the maintainer to transcribe a run into |
| `measure/test/` | Unit tests for `measure/lib.sh` (fixtures only) |

## Checks (run these before you finish)

CI ([.github/workflows/ci.yml](./.github/workflows/ci.yml)) runs, with no
cloud credentials:

```bash
# Once, from the repository root (covers examples/ and measure/ too)
terraform fmt -check -recursive -diff

# In ., examples/basic, examples/advanced, and each of
# measure/public-network-access, measure/outbound-integration,
# measure/azure-files-swap, measure/mcp-2026, measure/hmac-policy
terraform init -backend=false -lockfile=readonly
terraform validate

# In . only: plan-only tests, mocked providers, no credentials
terraform test

# Lint (from the root)
tflint --init
tflint --recursive --config "$(pwd)/.tflint.hcl" --format compact

# Generated docs must be current
for d in . modules/*/ examples/*/; do terraform-docs --output-check "$d"; done

# Security scanners (security.yml); CI runs Checkov 3.3.26 from its image
checkov --config-file .checkov.yaml
trivy config --config trivy.yaml .

# Scripts
shellcheck -x measure/run.sh measure/lib.sh measure/*/measure.sh \
  measure/azure-files-swap/swap.sh measure/test/lib_test.sh \
  scripts/check-openapi-tools.sh
bash measure/test/lib_test.sh
bash scripts/check-openapi-tools.sh
```

`pre-commit run --all-files` runs all of the above except `init`/`validate`
per root. A local Checkov of another version can flag a different set;
CI's pinned image (3.3.26) is the reference.

CI uses Terraform 1.13.3; the floor is 1.10 (an AVM module uses an ephemeral
resource). `validate` sees variables as unknown, so it does not check azapi
request bodies or `sku_name` values; say so rather than claiming they are
checked.

If you add a measurement root or an example, add it to the CI matrix and give
it its own lock file. If you change a provider or module version, refresh
every lock file (root, each `examples/<name>`, and each `measure/<root>`) for
all four platforms, or `-lockfile=readonly` fails:

```bash
terraform providers lock \
  -platform=linux_amd64 -platform=linux_arm64 \
  -platform=darwin_arm64 -platform=darwin_amd64
```

## Never do these

- **Never run `terraform apply`, `plan` against a subscription, or
  `measure/run.sh`** unless the user explicitly asks in this session. They
  create billed resources (APIM Standard v2 is the largest line). `run.sh
  --preflight-only` creates nothing but still needs `az login`.
- Never commit state, `*.tfvars`, plans, `measure/results/`, or any
  credential, including in examples. The GitHub App private key is set in Key
  Vault out of band; Terraform must never see it (it would land in state).
- Never add a route, MCP tool, policy, or job that can change a decision
  record. The deployment is read-only by design and that is a security
  boundary ([SECURITY.md](./SECURITY.md)).
- Never make the Container Apps environment or server app reachable except
  through APIM. The server authenticates no one and binds `0.0.0.0` only
  because three layers (internal environment, NSG admitting only the APIM
  integration subnet, ingress IP restriction) keep APIM the only route in. If
  you change that, remove `ADRKIT_SERVER_HOST`.
- Never default or loosen `image_tag` to `latest` or a moving major tag; the
  validation regex enforces `vX.Y.Z[@sha256:<digest>]` (ADR-0056 clause 2).
- Don't upgrade to azurerm 5.x here: the AVM modules require
  `>= 4.73.0, < 5.0.0`. The 5.x move (replacing both AVM modules with native
  resources) is planned as its own pull request.
- Never add `provider` blocks to the root or to `modules/*`; they belong to
  callers. Never add a `command = apply` run to `tests/`: `azapi` is a real
  provider there (tests/README.md).
- Never suppress a finding in `.tflint.hcl`, `.checkov.yaml`, or
  `trivy.yaml`. Suppress inline, next to the resource, with the reason, and
  add it to README "Security scanning".

## Invariants that are easy to break

- **`publicNetworkAccess` ordering in `modules/apim`.** The service is created
  with public access enabled, then azapi sets outbound integration, then the
  private endpoint exists, then one of two count-gated
  `azapi_update_resource`s flips the property. `disable_public_access`
  (private mode) must run *before* APIs, policies, and product bindings;
  `enable_public_access` (public mode) must run *after* them. Product
  bindings always depend on policies. Read the header comment of
  `modules/apim/main.tf` and README "The two-step apply" before touching any
  `depends_on` there.
- **`lifecycle.ignore_changes` on `azurerm_api_management.this`** keeps a later
  plan from reverting azapi's changes. Don't remove it.
- **Method guard.** The REST API publishes only `GET` operations plus
  catch-all `/*` operations for other methods so the policy can answer `405`.
  None is forwarded or exposed as an MCP tool.
- **No body reads.** No policy may read `context.Response.Body`, and
  diagnostics log 0 bytes of bodies; both would break streaming.
- **Read-only mount.** The server mounts the share through the `corpora-ro`
  environment storage; only the sync job uses `corpora-rw`.
- **`public_access` changes the gateway only.** The environment is internal in
  both modes; flipping the flag must not recreate the backend.
- **MCP tool references** in `local.mcp_tools` assume APIM names imported
  operations after their OpenAPI `operationId` (unverified; measured by
  `measure/mcp-2026`). Tools are the `/api/v1` data operations only, listed in
  `modules/apim/openapi/mcp-tools.json`; `scripts/check-openapi-tools.sh`
  enforces that against the vendored document.
- **The server's configuration and the share layout are one contract.**
  `ADRKIT_SERVER_CORPORA` is the `repos[].key` list (bare keys), so each corpus
  is `<ADRKIT_SERVER_ROOT>/<key>` with records in `docs/adr` and the sidecar
  `.adrkit-corpus.json` at its top. Change one side and the sync job's layout
  (or the env var) must follow.
- **`/healthz` and the portal (`/`, `/portal/...`) are never imported into
  the REST API**; see `local.openapi_paths`.
- **The portal is its own keyless API, `adrkit-portal`, in private mode
  only** (`local.portal_enabled`). It must never exist when
  `public_access = true`, never join the product, and never back an MCP
  tool; its policy keeps the GET/HEAD guard and a per-IP rate limit. A
  browser's relative subrequests carry no subscription key, which is why it
  cannot live in the REST API. On a private -> public flip, the only thing
  that keeps the gateway closed until the portal is gone is
  `enable_public_access`'s `depends_on` on every portal resource (measured
  with `terraform_data` stand-ins on 1.13.3; see the comment there). Keep
  that list complete when you add a portal resource. The `enable_portal`
  validation (root and module) is config-only defence in depth and does not
  prevent a one-apply flip by itself.
- **`measure/public-network-access` mirrors `modules/apim` steps 1 to 4** (same
  resource types, API version, bodies, `ignore_changes`) rather than calling
  the module. If you change those steps in one place, change the other.

## Conventions

- **Validators come with tests.** A new or changed input validation gets an
  `expect_failures` run in `tests/validation.tftest.hcl`; a new invariant gets
  an assertion, and you should check that it fails when the invariant is
  broken.
- **Examples carry the provider contract.** The `azurerm` `features` block in
  `examples/*/providers.tf` (and README "Use as a module") is required by the
  module; keep all three copies identical.

- **Comments carry evidence.** When code relies on Azure behaviour, state in
  the comment whether it is verified (with source and date, for example
  "verified, Microsoft Learn, 2026-10-10") or unmeasured. Keep README's
  "Verified vs unverified provider facts" in step.
- **Cite the decision.** Module headers and comments name the ADR-0056 (or
  ADR-0055) clause they implement. A change that contradicts ADR-0056 needs
  the ADR amended in mbeacom/adrkit first; flag it to the user rather than
  coding around it.
- **Placeholders use tagged TODOs**: `TODO(<tag>)`, for example
  `TODO(sync-image)`. Every tag is listed in README's "TODO list" table; add,
  update, or remove the row when you add or resolve one.
- **Module shape**: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
  (no provider blocks inside modules). Every module takes `name_prefix`,
  `location`, `resource_group_name`, and `tags`. Names follow
  `"${name_prefix}-adrkit-<kind>"`; globally unique names get a
  `random_string` suffix with an optional explicit override variable.
- **azapi where azurerm can't**: the `publicNetworkAccess` flip, v2 outbound
  integration (API version `2024-05-01`), and the MCP API and tools
  (`2025-09-01-preview`). Keep API versions in the `locals` of
  `modules/apim`.
- **Variables** have descriptions, use validation blocks for invariants, and
  cross-check modes (for example, `entra_tenant_id` is required when
  `public_access = true`).
- **Bash in `measure/`**: `set -euo pipefail`, bash 3.2 compatible (macOS
  default; no `timeout`, use `with_timeout`), shellcheck-clean. Every
  subscription-scoped `az` call goes through `azs`; ARM reads go through
  `arm_get`; never change the user's Azure CLI default subscription. Checks
  report through `record` as PASS, FAIL (a result contradicting ADR-0056),
  ERROR (could not observe), or INFO.
- **Docs are plain and exact**: no prices, no claims beyond the evidence,
  dates on verified facts.

## Git

- Commits need a DCO sign-off: `git commit -s`.
- Messages follow Conventional Commits, for example
  `feat(measure): ...` or `fix(apim): ...`.
- Changes land on `main` through pull requests; branch first. CODEOWNERS is
  `@mbeacom`.
