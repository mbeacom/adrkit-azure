# Optional Front Door Premium with WAF (ADR-0056 clause 8), public mode only.
# The root instantiates this with count = public_access && enable_waf.
#
# Front Door reaches APIM over Private Link (target type "Gateway"). The
# private endpoint connection Front Door creates on APIM arrives PENDING and
# must be approved on the APIM side.
# TODO(frontdoor-approval): automate or document that approval.
# TODO(frontdoor-lockdown): once Front Door is in front, restrict APIM so the
# gateway accepts only Front Door traffic (for example, check the
# X-Azure-FDID header in policy). Not done in the skeleton.

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.name_prefix}-adrkit-afd"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.name_prefix}-adrkit"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "apim" {
  name                     = "apim"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  load_balancing {}

  health_probe {
    # TODO(frontdoor-probe): APIM's built-in status endpoint; adrkit's
    # /healthz is deliberately not published through APIM.
    path                = "/status-0123456789abcdef"
    protocol            = "Https"
    request_type        = "GET"
    interval_in_seconds = 100
  }
}

resource "azurerm_cdn_frontdoor_origin" "apim" {
  name                           = "apim"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.apim.id
  enabled                        = true
  host_name                      = var.apim_gateway_host
  origin_host_header             = var.apim_gateway_host
  https_port                     = 443
  http_port                      = 80
  certificate_name_check_enabled = true

  private_link {
    target_type            = "Gateway"
    private_link_target_id = var.apim_id
    location               = var.location
    request_message        = "Front Door to adrkit APIM gateway"
  }
}

resource "azurerm_cdn_frontdoor_route" "apim" {
  name                          = "apim"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.apim.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.apim.id]
  supported_protocols           = ["Https"]
  patterns_to_match             = ["/*"]
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = false
  link_to_default_domain        = true
}

resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                = "${var.name_prefix}adrkitwaf"
  resource_group_name = var.resource_group_name
  sku_name            = azurerm_cdn_frontdoor_profile.this.sku_name
  enabled             = true
  mode                = "Prevention"
  tags                = var.tags

  managed_rule {
    # TODO(waf-rules): confirm the current managed rule set type and version
    # for Front Door Premium before the first apply.
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "waf"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id

      association {
        patterns_to_match = ["/*"]
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
      }
    }
  }
}
