#!/usr/bin/env bash
# Fails if the vendored OpenAPI document no longer carries an operation the
# MCP tools expect, or if a tool would expose something other than a data
# operation (ADR-0056 clause 6: tools map to the read-only /api/v1 GET routes;
# never getHealth, the portal, or /openapi.json).
#
# Each key of modules/apim/openapi/mcp-tools.json (what modules/apim reads for
# local.mcp_tools) must be the operationId of a GET operation whose path
# starts with /api/v1/ in modules/apim/openapi/adrkit-server.openapi.json.
# It also fails on any non-GET/HEAD operation in the document, with or without
# an operationId (the read-only invariant), and prints notices for
# operations without an operationId and /api/v1 operations no tool exposes.
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

# Every path x method entry, whether or not it has an operationId:
# operationId<TAB>method<TAB>path, with "-" for a missing operationId. All
# eight OpenAPI operation methods are listed, so an operation cannot slip past
# the checks below by omitting its id.
ops="$(jq -r '.paths | to_entries[] | .key as $p | .value | to_entries[]
  | select(.key | IN("get", "put", "post", "delete", "options", "head", "patch", "trace"))
  | "\(.value.operationId // "-")\t\(.key)\t\($p)"' "$openapi")"

# Read-only invariant: GET and HEAD only, regardless of operationId.
non_get="$(printf '%s\n' "$ops" | awk -F'\t' 'NF && $2 != "get" && $2 != "head"')"
if [ -n "$non_get" ]; then
  echo "FAIL: the OpenAPI document has non-GET/HEAD operations (the deployment is read-only):" >&2
  printf '  %s\n' "$non_get" >&2
  status=1
fi

missing_id="$(printf '%s\n' "$ops" | awk -F'\t' 'NF && $1 == "-"')"
if [ -n "$missing_id" ]; then
  echo "notice: operations without an operationId (never usable as MCP tools):"
  printf '  %s\n' "$missing_id"
fi

if [ "$(jq 'type == "object" and length > 0' "$tools")" != "true" ]; then
  echo "FAIL: $tools must be a non-empty JSON object of operationId to description" >&2
  exit 1
fi

# Keys are checked in jq, before any shell handling, so an empty key or one
# with whitespace or control characters cannot be dropped or split by the
# loop below. Valid keys are what an OpenAPI operationId and an APIM tool
# name can both be here: letters, digits, "_" and "-", starting alphanumeric.
bad_keys="$(jq -r 'keys[] | select(test("^[A-Za-z0-9][A-Za-z0-9_-]*$") | not) | @json' "$tools")"
if [ -n "$bad_keys" ]; then
  echo "FAIL: invalid MCP tool keys in $(basename "$tools") (must match ^[A-Za-z0-9][A-Za-z0-9_-]*$):" >&2
  printf '  %s\n' "$bad_keys" >&2
  status=1
fi
tool_ids="$(jq -r 'keys[] | select(test("^[A-Za-z0-9][A-Za-z0-9_-]*$"))' "$tools")"

while IFS= read -r id; do
  [ -n "$id" ] || continue
  line="$(printf '%s\n' "$ops" | awk -F'\t' -v id="$id" '$1 == id')"
  if [ "$(printf '%s\n' "$line" | grep -c .)" -gt 1 ]; then
    echo "FAIL: MCP tool '$id': that operationId is used by more than one operation" >&2
    status=1
    continue
  fi
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
done <<EOF_IDS
$tool_ids
EOF_IDS

# Not a failure: a new data operation may be left out of the tools on purpose.
printf '%s\n' "$ops" | awk -F'\t' 'NF && $1 != "-" && $2 == "get" && index($3, "/api/v1/") == 1 { print $1 }' |
  while read -r id; do
    if ! printf '%s\n' "$tool_ids" | grep -qx "$id"; then
      echo "notice: /api/v1 operation '$id' is not exposed as an MCP tool"
    fi
  done

if [ "$status" -eq 0 ]; then
  echo "PASS: every MCP tool maps to a GET /api/v1 operation in $(basename "$openapi")"
fi
exit "$status"
