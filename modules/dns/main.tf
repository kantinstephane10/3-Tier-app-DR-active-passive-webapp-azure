resource "azurerm_dns_zone" "this" {
  name                = var.zone_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
resource "azurerm_cdn_frontdoor_custom_domain" "this" {
  name                     = "application-domain"
  cdn_frontdoor_profile_id = var.profile_id
  host_name                = "${var.host_label}.${var.zone_name}"
  dns_zone_id              = azurerm_dns_zone.this.id
  tls {
    certificate_type    = "ManagedCertificate"
    minimum_tls_version = "TLS12"
  }
}
resource "azurerm_dns_txt_record" "validation" {
  name                = "_dnsauth.${var.host_label}"
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  record { value = azurerm_cdn_frontdoor_custom_domain.this.validation_token }
}
resource "azurerm_dns_cname_record" "this" {
  name                = var.host_label
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  record              = var.endpoint_hostname
}
resource "azurerm_cdn_frontdoor_route" "this" {
  name                            = "custom-application"
  cdn_frontdoor_endpoint_id       = var.endpoint_id
  cdn_frontdoor_origin_group_id   = var.origin_group_id
  cdn_frontdoor_origin_ids        = var.origin_ids
  cdn_frontdoor_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.this.id]
  supported_protocols             = ["Http", "Https"]
  patterns_to_match               = ["/*"]
  forwarding_protocol             = "HttpOnly"
  https_redirect_enabled          = true
  link_to_default_domain          = false
}
output "name_servers" { value = azurerm_dns_zone.this.name_servers }
output "url" { value = "https://${var.host_label}.${var.zone_name}" }
output "custom_domain_id" { value = azurerm_cdn_frontdoor_custom_domain.this.id }

resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "custom-domain-waf"
  cdn_frontdoor_profile_id = var.profile_id
  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = var.firewall_policy_id
      association {
        domain { cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_custom_domain.this.id }
        patterns_to_match = ["/*"]
      }
    }
  }
}
