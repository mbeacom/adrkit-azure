#!/usr/bin/env bash
# Fails if the vendored OpenAPI document no longer carries an operation the
# MCP tools expect, or if a tool would expose something other than a data
# operation (ADR-0056 clause 6: tools map to the read-only /api/v1 GET routes;
# never getHealth, the portal, or /openapi.json).
#
# Each key of modules/apim/openapi/mcp-tools.json (what modules/apim reads for
# local.mcp_tools) must be the operationId of a GET operation whose path
# starts with /api/v1/ in modules/apim/openapi/adrkit-server.openapi.json.
# It also fails on any non-GET operation in the document (the read-only
# invariant), and prints a notice for /api/v1 operations no tool exposes.
#
# Usage: scripts/check-openapi-tools.sh [openapi.json] [mcp-tools.json]
# Needs jq. Reads files only; no network, no Terraform, no Azure.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
openapi="${1:-$root/modules/apim/openapi/adrkit-server.openapi.json}"
tools="${2:-$root/modules/apim/openapi/mcp-tools.json}"

for f in "$openapi" "$tools"; do
  if [ ! -r "$f" ]; then
    echo "error: cannot read $f" >&2
    exit 2
  fi
done

status=0

# operationId<TAB>method<TAB>path, one line per operation.
ops="$(jq -r '.paths | to_entries[] | .key as $p | .value | to_entries[]
  | select(.value | type == "object" and has("operationId"))
  | "\(.value.operationId)\t\(.key)\t\($p)"' "$openapi")"

non_get="$(printf '%s\n' "$ops" | awk -F'\t' 'NF && $2 != "get"')"
if [ -n "$non_get" ]; then
  echo "FAIL: the OpenAPI document has non-GET operations (the deployment is read-only):" >&2
  printf '  %s\n' "$non_get" >&2
  status=1
fi

tool_ids="$(jq -r 'keys[]' "$tools")"
if [ -z "$tool_ids" ]; then
  echo "FAIL: $tools names no tools" >&2
  exit 1
fi

for id in $tool_ids; do
  line="$(printf '%s\n' "$ops" | awk -F'\t' -v id="$id" '$1 == id')"
  if [ -z "$line" ]; then
    echo "FAIL: MCP tool '$id' has no operation with that operationId in $(basename "$openapi")" >&2
    status=1
    continue
  fi
  method="$(printf '%s\n' "$line" | cut -f2)"
  path="$(printf '%s\n' "$line" | cut -f3)"
  case "$method:$path" in
    get:/api/v1/*) echo "ok: $id -> GET $path" ;;
    *)
      echo "FAIL: MCP tool '$id' maps to ${method} ${path}; tools may expose only GET /api/v1/... data operations" >&2
      status=1
      ;;
  esac
done

# Not a failure: a new data operation may be left out of the tools on purpose.
printf '%s\n' "$ops" | awk -F'\t' 'NF && $2 == "get" && index($3, "/api/v1/") == 1 { print $1 }' |
  while read -r id; do
    if ! printf '%s\n' "$tool_ids" | grep -qx "$id"; then
      echo "notice: /api/v1 operation '$id' is not exposed as an MCP tool"
    fi
  done

if [ "$status" -eq 0 ]; then
  echo "PASS: every MCP tool maps to a GET /api/v1 operation in $(basename "$openapi")"
fi
exit "$status"
