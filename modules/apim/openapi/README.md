# Vendored OpenAPI document

`adrkit-server.openapi.json` is the adrkit server's own OpenAPI 3.0.3
document (ADR-0055 clause 11), the same content its `GET /openapi.json`
serves. `modules/apim` imports it into the REST API, minus `/healthz` (never
published), the `/portal/...` operations (forwarded by one wildcard
operation instead), and, in public mode, `/` (the portal root).

**Source:** `buildOpenApi()` in `packages/server/src/openapi.ts` of
[mbeacom/adrkit](https://github.com/mbeacom/adrkit) at tag
[`v0.20.0`](https://github.com/mbeacom/adrkit/tree/v0.20.0/packages/server)
(commit `d94698cf4142133a166d4af4d33d06a660c2579f`), the first release with
the `server` selector and the `image_tag` floor: the source
`ghcr.io/mbeacom/adrkit:v0.20.0` is built from. (Generated from source, not
read from a running image.) When `image_tag` moves to a release
whose routes changed, regenerate from that tag and update this paragraph.

v0.20.0 has 17 operations: `getHealth`, `getOpenApi`, the seven `/api/v1`
data operations (the MCP tools), `getPortal` (`/`), and seven under
`/portal/{corpus}/` (`getCorpusPortal`, `getCorpusPortalData`,
`getPortalStylesheet`, `getPortalApp`, `getPortalIcon`,
`getPortalBoardLayout`, `getPortalBoardView`), all forwarded by the one
`GET /portal/*` wildcard.

`mcp-tools.json` lists the operations exposed as MCP tools (operationId to
tool description). `scripts/check-openapi-tools.sh` checks it against the
document in CI.

## Regenerate

From an adrkit checkout at the tag to vendor (with Bun installed; this only
imports a pure module and writes stdout). A detached worktree keeps your own
checkout untouched:

```bash
git -C /path/to/adrkit worktree add --detach /tmp/adrkit-vX.Y.Z vX.Y.Z
cd /tmp/adrkit-vX.Y.Z
bun -e "import { buildOpenApi } from './packages/server/src/openapi.ts'; process.stdout.write(JSON.stringify(buildOpenApi(), null, 2) + '\n');" \
  > /path/to/adrkit-azure/modules/apim/openapi/adrkit-server.openapi.json
```

Or read `GET /openapi.json` from a running server of the pinned image. The served body has canonical (sorted) key order, so compare
semantically, for example with `jq -S . | diff`, not byte for byte.

Then update the tag and commit above and run `bash scripts/check-openapi-tools.sh`.
An operationId the tools use that disappears from the document fails that
check; `operationId`s are APIM operation and tool names, so the server treats
renaming one as breaking.
