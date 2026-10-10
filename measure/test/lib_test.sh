#!/usr/bin/env bash
# Unit tests for the Terraform error attribution helpers in measure/lib.sh.
# No Azure, no Terraform: fixtures are captured-format Terraform output.
#   bash measure/test/lib_test.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$here/../lib.sh"
fx="$here/fixtures"
failures=0

expect() { # yes|no LOG ADDRESS
  local got=no
  if tf_error_attributed_to "$fx/$2" "$3"; then got=yes; fi
  if [ "$got" = "$1" ]; then
    printf 'ok    %-22s %-48s %s\n' "$2" "$3" "$got"
  else
    printf 'FAIL  %-22s %-48s expected %s, got %s\n' "$2" "$3" "$1" "$got"
    failures=$((failures + 1))
  fi
}

# Attributed to the resource.
expect yes attributed.log azurerm_api_management_api_policy.webhook
# The same log does not attribute anything else.
expect no attributed.log azapi_resource.mcp_tool
# Attributed to another resource (quota on the service), although the plan
# names every resource under test.
expect no other-resource.log azurerm_api_management_api_policy.webhook
expect no other-resource.log azapi_resource.mcp_tool
expect no other-resource.log azapi_update_resource.disable_public_access
expect yes other-resource.log azurerm_api_management.this
# No resource attribution (a provider/auth error).
expect no no-attribution.log azurerm_api_management_api_policy.webhook
expect no no-attribution.log azapi_resource.mcp_tool
expect no no-attribution.log azapi_update_resource.disable_public_access
# A successful plan and apply mentioning the resources.
expect no success.log azurerm_api_management_api_policy.webhook
expect no success.log azapi_resource.mcp_tool
expect no success.log azapi_update_resource.disable_public_access
# Coloured output with the box prefix, and a count index.
expect yes colored-indexed.log azapi_update_resource.disable_public_access
expect no colored-indexed.log azapi_update_resource.enable_public_access
# A module-prefixed address is a different resource.
expect no module-prefixed.log azapi_resource.mcp_tool
# A missing log attributes nothing.
expect no does-not-exist.log azapi_resource.mcp_tool

summary=$(tf_error_summary "$fx/no-attribution.log")
case "$summary" in
*'provider["registry.terraform.io/hashicorp/azurerm"]'*) echo "ok    summary names the provider" ;;
*) echo "FAIL  summary: $summary"; failures=$((failures + 1)) ;;
esac

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
