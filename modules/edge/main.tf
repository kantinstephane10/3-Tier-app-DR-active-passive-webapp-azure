resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "afd-${var.name}"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}
resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "endpoint-${var.name}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}
resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "regional"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = false
  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
  health_probe {
    interval_in_seconds = 30
    path                = "/health"
    protocol            = "Http"
    request_type        = "GET"
  }
}
resource "azurerm_cdn_frontdoor_origin" "this" {
  for_each                       = var.origins
  name                           = each.key
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.this.id
  host_name                      = each.value.hostname
  origin_host_header             = each.value.hostname
  http_port                      = 80
  https_port                     = 443
  priority                       = each.value.priority
  weight                         = 1000
  certificate_name_check_enabled = true
  enabled                        = true
}
resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "application"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [for v in azurerm_cdn_frontdoor_origin.this : v.id]
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = ["/*"]
  forwarding_protocol           = "HttpOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
}
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                = replace("waf${var.name}", "-", "")
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  enabled             = true
  mode                = "Prevention"
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }
  tags = var.tags
}
resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "waf"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id
      association {
        domain { cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id }
        patterns_to_match = ["/*"]
      }
    }
  }
}
output "url" { value = "https://${azurerm_cdn_frontdoor_endpoint.this.host_name}" }

output "profile_id" { value = azurerm_cdn_frontdoor_profile.this.id }
output "endpoint_id" { value = azurerm_cdn_frontdoor_endpoint.this.id }
output "hostname" { value = azurerm_cdn_frontdoor_endpoint.this.host_name }
output "origin_group_id" { value = azurerm_cdn_frontdoor_origin_group.this.id }
output "origin_ids" { value = [for v in azurerm_cdn_frontdoor_origin.this : v.id] }

output "firewall_policy_id" { value = azurerm_cdn_frontdoor_firewall_policy.this.id }

output "resource_guid" { value = azurerm_cdn_frontdoor_profile.this.resource_guid }
