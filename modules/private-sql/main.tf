resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = var.regions
  name                  = "link-${var.name}-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = each.value.vnet_id
  tags                  = var.tags
}
resource "azurerm_private_endpoint" "sql" {
  for_each            = var.regions
  name                = "pe-${var.name}-sql-${each.key}"
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  subnet_id           = each.value.subnet_id
  private_service_connection {
    name                           = "sql"
    private_connection_resource_id = each.value.server_id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }
  private_dns_zone_group {
    name                 = "sql"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
  tags = var.tags
}
