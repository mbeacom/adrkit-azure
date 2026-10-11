# Advanced example: public mode with Entra ID token validation, per-subject
# rate limiting, Front Door Premium with a WAF, private repositories read
# through a GitHub App, explicit global names, and a non-default network.
#
# Front Door is the largest optional cost line, and public mode is a
# deliberate exposure: read README "The two modes" before applying this.
#
# Outside this repository, use a pinned Git source instead of the path, for
# example source = "github.com/mbeacom/adrkit-azure?ref=vX.Y.Z", or the
# registry address once the module is published (README, "Publishing to the
# Terraform Registry").

module "adrkit" {
  source = "../.."

  location            = var.location
  name_prefix         = var.name_prefix
  resource_group_name = "${var.name_prefix}-adrkit-public-rg"

  apim_sku             = "StandardV2"
  apim_capacity        = 1
  apim_name            = var.apim_name
  apim_publisher_name  = "Platform team"
  apim_publisher_email = var.apim_publisher_email

  image_tag = var.image_tag

  # Public mode: every API validates an Entra ID token and rate-limits by
  # its subject.
  public_access             = true
  enable_portal             = false # the keyless portal is private-mode only (ADR-0056 clause 8)
  entra_tenant_id           = var.entra_tenant_id
  entra_audience            = var.entra_audience
  rate_limit_calls          = 60
  rate_limit_period_seconds = 60

  enable_waf              = true
  frontdoor_endpoint_name = var.frontdoor_endpoint_name

  # Private repositories are read through a GitHub App whose private key you
  # put in Key Vault yourself, under this secret name; Terraform never sees it.
  github_app_private_key_secret_name = "github-app-private-key"

  repos = [
    { key = "adrkit", url = "https://github.com/mbeacom/adrkit" },
    { key = "platform", url = "https://github.com/example-org/platform", ref = "main", private = true },
  ]
  sync_cron = "*/30 * * * *"

  address_space = "10.70.0.0/16"

  tags = {
    environment = "example"
    owner       = "platform"
  }
}
