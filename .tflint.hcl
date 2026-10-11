# TFLint configuration. CI runs, from the repository root:
#   tflint --init
#   tflint --recursive --config "$(pwd)/.tflint.hcl"
# Plugin versions are pinned; bump them deliberately.

config {
  # Lint local child modules through their callers so passed values are
  # checked too. Registry modules (the AVM modules) are not inspected.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
