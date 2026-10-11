variable "location" {
  description = "Azure region for every resource. APIM, the VNet, and its integration subnet must share it."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "name_prefix" {
  description = "Short prefix for resource names. Lowercase letters and digits, 3 to 10 characters, so derived storage and Key Vault names stay within their limits."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 10 lowercase letters or digits, starting with a letter."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create. Defaults to \"<name_prefix>-adrkit-rg\"."
  type        = string
  default     = null

  # 1-90 letters, digits, underscores, hyphens, periods, parentheses; no
  # trailing period. Verified, Microsoft Learn "Naming rules and restrictions
  # for Azure resources", 2026-10-10.
  validation {
    condition     = var.resource_group_name == null || can(regex("^[\\p{L}\\p{Nd}_().-]{0,89}[\\p{L}\\p{Nd}_()-]$", var.resource_group_name))
    error_message = "resource_group_name must be 1 to 90 letters, digits, underscores, hyphens, periods, or parentheses, and must not end with a period."
  }
}

variable "public_access" {
  description = <<-EOT
    false (default): fully private. APIM's gateway is reachable only through its
    inbound private endpoint, and its publicNetworkAccess is set to Disabled in a
    second step after that endpoint exists. true: the gateway stays public and
    every API adds validate-azure-ad-token and rate-limit-by-key. The Container
    Apps environment is internal in both modes, so flipping this never recreates
    the backend.
  EOT
  type        = bool
  default     = false
}

variable "apim_sku" {
  description = "APIM v2 tier. StandardV2 is the baseline (ADR-0056 clause 6); PremiumV2 is allowed for teams already on it. Basic v2 is not offered because the private-endpoint tier list omits it."
  type        = string
  default     = "StandardV2"

  validation {
    condition     = contains(["StandardV2", "PremiumV2"], var.apim_sku)
    error_message = "apim_sku must be StandardV2 or PremiumV2."
  }
}

variable "apim_name" {
  description = "Optional explicit APIM name. APIM names are globally unique (<name>.azure-api.net); null derives \"<name_prefix>-adrkit-apim-<random 6>\", stable across applies."
  type        = string
  default     = null

  # 1-50 alphanumerics and hyphens, starting with a letter and ending with an
  # alphanumeric. Verified, Microsoft Learn "Naming rules and restrictions for
  # Azure resources", 2026-10-10.
  validation {
    condition     = var.apim_name == null || can(regex("^[A-Za-z]([A-Za-z0-9-]{0,48}[A-Za-z0-9])?$", var.apim_name))
    error_message = "apim_name must be 1 to 50 letters, digits, or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "apim_capacity" {
  description = "APIM scale units."
  type        = number
  default     = 1

  # No upper bound here: the per-tier maximum is the service's to enforce.
  validation {
    condition     = var.apim_capacity >= 1 && floor(var.apim_capacity) == var.apim_capacity
    error_message = "apim_capacity must be a whole number of at least 1."
  }
}

variable "apim_publisher_name" {
  description = "APIM publisher name (required by the service)."
  type        = string
  default     = "adrkit"

  validation {
    condition     = length(trimspace(var.apim_publisher_name)) > 0
    error_message = "apim_publisher_name must not be empty."
  }
}

variable "apim_publisher_email" {
  description = "APIM publisher email (required by the service)."
  type        = string

  # A shape check only; the service does its own validation.
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.apim_publisher_email))
    error_message = "apim_publisher_email must look like an email address (name@domain.tld)."
  }
}

variable "image_repository" {
  description = "Container image repository for the adrkit server, without a tag or digest (those come from image_tag)."
  type        = string
  default     = "ghcr.io/mbeacom/adrkit"

  # A registry port ("host:5000/repo") is fine; a tag or digest is not, so
  # image_tag stays the only place a version is chosen (ADR-0056 clause 2).
  validation {
    condition     = length(var.image_repository) > 0 && !strcontains(var.image_repository, "@") && !can(regex(":[^/]*$", var.image_repository))
    error_message = "image_repository must not carry a tag or digest; set the version through image_tag."
  }
}

variable "image_tag" {
  description = <<-EOT
    Immutable adrkit image tag, optionally with a digest, for example
    "v0.20.0" or "v0.20.0@sha256:<64 hex>". Required, with no default. The
    minimum is v0.20.0, the first adrkit release with the `server` selector
    (ADR-0055, mbeacom/adrkit#314); tags below it are refused. "latest" and
    the moving major tag ("v0") are refused (ADR-0056 clause 2).
  EOT
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+(@sha256:[0-9a-f]{64})?$", var.image_tag))
    error_message = "image_tag must be an immutable vX.Y.Z tag, optionally with @sha256:<digest>. \"latest\" and moving major tags are refused."
  }

  # Semver floor: >= v0.20.0, the first release with the `server` selector. try() makes a malformed tag pass this block (regex()
  # errors on no match, and `||` does not short-circuit on Terraform 1.10), so
  # the format check above owns that message. Patch is irrelevant to the
  # floor.
  validation {
    condition = try(
      tonumber(regex("^v([0-9]+)\\.([0-9]+)\\.", var.image_tag)[0]) > 0 ||
      tonumber(regex("^v([0-9]+)\\.([0-9]+)\\.", var.image_tag)[1]) >= 20,
      true
    )
    error_message = "image_tag must be v0.20.0 or later: earlier adrkit releases do not contain the `server` selector (ADR-0055)."
  }
}

variable "sync_image" {
  description = <<-EOT
    TODO(sync-image): image for the corpus sync job. No sync image exists yet.
    The default is Microsoft's public Container Apps jobs quickstart sample,
    used only so the job resource can exist; it does not implement the sync
    and writes no corpus. Replace it once a sync image implementing ADR-0056
    clause 4 (shallow clone, write `<key>.next/`, write .adrkit-corpus.json
    last, two-move swap) is published. It must write, for each repos[].key,
    `<share>/<key>/docs/adr/...` and `<share>/<key>/.adrkit-corpus.json`: the
    layout the server reads through ADRKIT_SERVER_ROOT and
    ADRKIT_SERVER_CORPORA.
  EOT
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart-jobs:latest"
}

variable "sync_cron" {
  description = "Cron expression (UTC) for the corpus sync job's Schedule trigger."
  type        = string
  default     = "*/15 * * * *"

  # Field count only; Container Apps validates the expression itself.
  validation {
    condition     = can(regex("^\\S+( \\S+){4}$", var.sync_cron))
    error_message = "sync_cron must be a five-field cron expression separated by single spaces, for example \"*/15 * * * *\"."
  }
}

variable "repos" {
  description = <<-EOT
    Repositories whose docs/adr corpus is synced and served; at least one. `key`
    is the `{corpus}` path segment of ADR-0055 (^[a-z0-9][a-z0-9-]{0,63}$),
    the directory `<share>/<key>` the sync job writes, and the portal path
    `/portal/<key>/`. `url` is the HTTPS clone URL, `ref` the branch or tag to
    follow, and `private` marks repositories read through the GitHub App
    (ADR-0056 clause 5). With exactly one entry, the gateway's portal root
    redirects to that corpus's portal.
  EOT
  type = list(object({
    key     = string
    url     = string
    ref     = optional(string, "main")
    private = optional(bool, false)
  }))

  # The server refuses to start with an empty ADRKIT_SERVER_CORPORA
  # (packages/server/src/config.ts, "corpora-missing"), so an empty list
  # would leave the server app crash-looping.
  validation {
    condition     = length(var.repos) > 0
    error_message = "repos must name at least one repository: the server refuses to start with no corpus."
  }

  validation {
    condition     = alltrue([for r in var.repos : can(regex("^[a-z0-9][a-z0-9-]{0,63}$", r.key))])
    error_message = "Each repos[].key must match ^[a-z0-9][a-z0-9-]{0,63}$ (ADR-0055 clause 6)."
  }

  validation {
    condition     = length(distinct([for r in var.repos : r.key])) == length(var.repos)
    error_message = "repos[].key values must be unique."
  }

  validation {
    condition     = alltrue([for r in var.repos : startswith(r.url, "https://")])
    error_message = "Each repos[].url must be an https:// clone URL."
  }

  validation {
    condition     = alltrue([for r in var.repos : length(trimspace(r.ref)) > 0])
    error_message = "Each repos[].ref must be a non-empty branch or tag name."
  }
}

variable "github_app_private_key_secret_name" {
  description = "Name of the Key Vault secret that holds the GitHub App private key used by the sync job for private repositories. The secret value is set out of band; Terraform never sees it. Unused while every repo is public."
  type        = string
  default     = "github-app-private-key"

  # 1-127 alphanumerics and hyphens. Verified, Microsoft Learn "Naming rules
  # and restrictions for Azure resources", 2026-10-10.
  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,127}$", var.github_app_private_key_secret_name))
    error_message = "github_app_private_key_secret_name must be 1 to 127 letters, digits, or hyphens."
  }
}

variable "entra_tenant_id" {
  description = "Entra ID tenant that issues tokens accepted in public mode (validate-azure-ad-token). Required when public_access = true."
  type        = string
  default     = null

  validation {
    condition     = !var.public_access || var.entra_tenant_id != null
    error_message = "entra_tenant_id is required when public_access = true."
  }

  validation {
    condition     = var.entra_tenant_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.entra_tenant_id))
    error_message = "entra_tenant_id must be a tenant GUID."
  }
}

variable "entra_audience" {
  description = "Audience (application ID URI or client ID) required on tokens in public mode. Required when public_access = true."
  type        = string
  default     = null

  validation {
    condition     = !var.public_access || var.entra_audience != null
    error_message = "entra_audience is required when public_access = true."
  }
}

variable "rate_limit_calls" {
  description = "Calls allowed per token subject per renewal period in public mode. A positive integer."
  type        = number
  default     = 120

  validation {
    condition     = var.rate_limit_calls >= 1 && floor(var.rate_limit_calls) == var.rate_limit_calls
    error_message = "rate_limit_calls must be a positive integer (APIM rate-limit-by-key calls)."
  }
}

variable "rate_limit_period_seconds" {
  description = "Renewal period, in seconds, for rate-limit-by-key: the public-mode APIs and the private-mode portal. An integer from 1 to 300."
  type        = number
  default     = 60

  validation {
    condition     = var.rate_limit_period_seconds >= 1 && var.rate_limit_period_seconds <= 300 && floor(var.rate_limit_period_seconds) == var.rate_limit_period_seconds
    error_message = "rate_limit_period_seconds must be an integer from 1 to 300 (APIM rate-limit-by-key renewal-period)."
  }
}

variable "enable_portal" {
  description = <<-EOT
    Private mode only: publish the decision portal at /adrkit-portal/ as its own
    APIM API with no subscription key (a browser's relative subrequests carry
    none), so anyone who can reach the private endpoint can read it. Never
    created in public mode (ADR-0056 clause 8): public_access = true requires
    enable_portal = false, and validation refuses the combination. A private
    -> public flip in one apply destroys the portal before the gateway opens
    (dependency ordering in modules/apim). Set false also to keep every route
    key-protected in private mode.
  EOT
  type        = bool
  default     = true

  # Defence in depth, not the ordering guarantee: it only makes a public-mode
  # configuration state its intent. The ordering of a private -> public flip
  # comes from enable_public_access's depends_on on the portal resources
  # (modules/apim), which makes one apply destroy the portal before the
  # gateway opens.
  validation {
    condition     = !(var.public_access && var.enable_portal)
    error_message = "enable_portal must be false when public_access = true: the keyless portal is never created in public mode (ADR-0056 clause 8)."
  }
}

variable "portal_rate_limit_calls" {
  description = "Private-mode portal: requests allowed per client IP per renewal period. One page load is about eight requests."
  type        = number
  default     = 300
  validation {
    condition     = var.portal_rate_limit_calls >= 1 && floor(var.portal_rate_limit_calls) == var.portal_rate_limit_calls
    error_message = "portal_rate_limit_calls must be a positive integer (APIM rate-limit-by-key calls)."
  }
}

variable "enable_waf" {
  description = "Public mode only: put Azure Front Door Premium with a WAF policy in front of APIM over Private Link. Off by default; it is the largest optional cost line. Requires public_access = true."
  type        = bool
  default     = false

  # Refused rather than silently ignored: in private mode there is no public
  # gateway for Front Door to sit in front of.
  validation {
    condition     = !var.enable_waf || var.public_access
    error_message = "enable_waf requires public_access = true."
  }
}

variable "frontdoor_endpoint_name" {
  description = "Optional explicit Front Door endpoint name (globally unique). Null derives \"<name_prefix>-adrkit-<random 6>\". Used only when public_access && enable_waf."
  type        = string
  default     = null

  # 1-50 alphanumerics and hyphens, starting and ending with an alphanumeric:
  # the "profiles / endpoints" row (afdEndpoints has no row of its own).
  # Verified, Microsoft Learn "Naming rules and restrictions for Azure
  # resources", 2026-10-10.
  validation {
    condition     = var.frontdoor_endpoint_name == null || can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,48}[A-Za-z0-9])?$", var.frontdoor_endpoint_name))
    error_message = "frontdoor_endpoint_name must be 1 to 50 letters, digits, or hyphens, starting and ending with a letter or digit."
  }
}

variable "address_space" {
  description = "VNet address space, an IPv4 CIDR of /16 or larger. The network module carves its subnets from it."
  type        = string
  default     = "10.60.0.0/16"

  # Mirrors modules/network so a bad value fails at the root, before any
  # module is evaluated.
  validation {
    condition     = can(cidrhost(var.address_space, 0)) && can(regex("^[0-9.]+/[0-9]+$", var.address_space)) && tonumber(split("/", var.address_space)[1]) <= 16
    error_message = "address_space must be a valid IPv4 CIDR of /16 or larger."
  }
}

variable "tags" {
  description = "Tags applied to every resource that accepts them."
  type        = map(string)
  default     = {}
}
