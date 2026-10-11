resource "azurerm_mssql_server" "primary" {
  name                          = "sql-${var.name}-primary"
  resource_group_name           = var.primary_rg
  location                      = var.primary_location
  version                       = "12.0"
  connection_policy             = "Proxy"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  azuread_administrator {
    login_username              = var.admin_login
    object_id                   = var.admin_object_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }
  tags = var.tags
}
resource "azurerm_mssql_database" "primary" {
  name                 = "appdb"
  server_id            = azurerm_mssql_server.primary.id
  sku_name             = var.sku
  zone_redundant       = var.zone_redundant
  storage_account_type = "Geo"
  tags                 = var.tags
}
resource "azurerm_mssql_server" "secondary" {
  count                         = var.enable_secondary ? 1 : 0
  name                          = "sql-${var.name}-secondary"
  resource_group_name           = var.secondary_rg
  location                      = var.secondary_location
  version                       = "12.0"
  connection_policy             = "Proxy"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  azuread_administrator {
    login_username              = var.admin_login
    object_id                   = var.admin_object_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }
  tags = var.tags
}
resource "azurerm_mssql_failover_group" "this" {
  count     = var.enable_secondary ? 1 : 0
  name      = "fog-${var.name}"
  server_id = azurerm_mssql_server.primary.id
  databases = [azurerm_mssql_database.primary.id]
  partner_server { id = azurerm_mssql_server.secondary[0].id }
  read_write_endpoint_failover_policy {
    mode = "Manual"
  }
  tags = var.tags
}
output "server_ids" {
  value = merge({ primary = azurerm_mssql_server.primary.id }, var.enable_secondary ? { secondary = azurerm_mssql_server.secondary[0].id } : {})
}
output "connection_endpoint" {
  value = var.enable_secondary ? "${azurerm_mssql_failover_group.this[0].name}.database.windows.net" : azurerm_mssql_server.primary.fully_qualified_domain_name
}
