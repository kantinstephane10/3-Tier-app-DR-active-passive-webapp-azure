locals {
  tags    = { owner = "Kantin Tongue", project = "azure-three-tier", environment = "lab" }
  regions = { primary = "eastus2", secondary = "centralus", global = "eastus2" }
}
resource "azurerm_resource_group" "workload" {
  for_each = local.regions
  name     = "rg-${var.prefix}-${each.key}"
  location = each.value
  tags     = local.tags
}
resource "azurerm_role_assignment" "jenkins_workload" {
  for_each             = azurerm_resource_group.workload
  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = var.service_principal_object_id
}
output "resource_groups" {
  value = { for k, v in azurerm_resource_group.workload : k => v.name }
}
