resource "azurerm_recovery_services_vault" "this" {
  name                         = "rsv-${var.name}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  sku                          = "Standard"
  storage_mode_type            = "GeoRedundant"
  cross_region_restore_enabled = true
  soft_delete_enabled          = true
  tags                         = var.tags
}
resource "azurerm_backup_policy_vm" "this" {
  name                = "daily-vm"
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.this.name
  timezone            = "UTC"
  backup {
    frequency = "Daily"
    time      = "23:00"
  }
  retention_daily { count = 7 }
}
output "vault_name" { value = azurerm_recovery_services_vault.this.name }
output "policy_name" { value = azurerm_backup_policy_vm.this.name }
