# Vendored OpenAPI document

`adrkit-server.openapi.json` is the adrkit server's own OpenAPI 3.0.3
document (ADR-0055 clause 11), the same content its `GET /openapi.json`
serves. `modules/apim` imports it into the REST API, minus `/healthz` (never
published), the `/portal/...` operations (forwarded by one wildcard
operation instead), and, in public mode, `/` (the portal root).

**Source:** `buildOpenApi()` in `packages/server/src/openapi.ts` of
[mbeacom/adrkit](https://github.com/mbeacom/adrkit) at commit
[`e491a785b3254d035cf4c23ef90065712ae682d1`](https://github.com/mbeacom/adrkit/tree/e491a785b3254d035cf4c23ef90065712ae682d1/packages/server)
(`main` after PR #314, which added the server). No released image contains
it yet; the first is expected to be v0.20.0. When that release is tagged,
regenerate from the tag and update the commit here.

`mcp-tools.json` lists the operations exposed as MCP tools (operationId to
tool description). `scripts/check-openapi-tools.sh` checks it against the
document in CI.

## Regenerate

From an adrkit checkout at the commit or tag to vendor (with Bun installed;
this only imports a pure module and writes stdout):

```bash
bun -e "import { buildOpenApi } from './packages/server/src/openapi.ts'; process.stdout.write(JSON.stringify(buildOpenApi(), null, 2) + '\n');" \
  > /path/to/adrkit-azure/modules/apim/openapi/adrkit-server.openapi.json
```

Or, once a released image contains the `server` selector, read it from a
running server. The served body has canonical (sorted) key order, so compare
semantically, for example with `jq -S . | diff`, not byte for byte.

Then update the commit above and run `bash scripts/check-openapi-tools.sh`.
An operationId the tools use that disappears from the document fails that
check; `operationId`s are APIM operation and tool names, so the server treats
renaming one as breaking.
