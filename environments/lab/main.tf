locals {
  ranks     = { foundation = 0, primary = 1, dr = 2, edge = 3 }
  rank      = lookup(local.ranks, var.stage, -1)
  locations = local.rank >= 2 ? { primary = "eastus2", secondary = "centralus" } : { primary = "eastus2" }
  workloads = local.rank >= 1 ? local.locations : {}
}
check "stage" {
  assert {
    condition     = contains(keys(local.ranks), var.stage)
    error_message = "stage must be foundation, primary, dr, or edge."
  }
}
data "azurerm_resource_group" "regional" {
  for_each = local.locations
  name     = "rg-${var.prefix}-${each.key}"
}
data "azurerm_resource_group" "global" { name = "rg-${var.prefix}-global" }
module "network" {
  source              = "../../modules/network"
  for_each            = local.locations
  name                = "${var.prefix}-${each.key}"
  resource_group_name = data.azurerm_resource_group.regional[each.key].name
  location            = each.value
  cidr                = each.key == "primary" ? "10.10.0.0/16" : "10.20.0.0/16"
  enable_nat          = var.enable_nat
  remote_cidr         = local.rank >= 2 ? (each.key == "primary" ? "10.20.0.0/16" : "10.10.0.0/16") : null
  tags                = var.tags
}
module "bastion" {
  source              = "../../modules/bastion"
  for_each            = var.enable_bastion ? local.locations : {}
  name                = "${var.prefix}-${each.key}"
  resource_group_name = data.azurerm_resource_group.regional[each.key].name
  location            = each.value
  subnet_id           = module.network[each.key].subnet_ids["AzureBastionSubnet"]
  tags                = var.tags
}
module "sql" {
  source             = "../../modules/sql"
  count              = local.rank >= 1 ? 1 : 0
  name               = "${var.prefix}-${var.unique_suffix}"
  primary_rg         = data.azurerm_resource_group.regional["primary"].name
  secondary_rg       = "rg-${var.prefix}-secondary"
  primary_location   = "eastus2"
  secondary_location = "centralus"
  enable_secondary   = local.rank >= 2
  admin_login        = var.sql_admin_login
  admin_object_id    = var.sql_admin_object_id
  tenant_id          = var.tenant_id
  sku                = var.sql_sku
  zone_redundant     = var.sql_zone_redundant
  tags               = var.tags
}
module "private_sql" {
  source              = "../../modules/private-sql"
  count               = local.rank >= 1 ? 1 : 0
  name                = var.prefix
  resource_group_name = data.azurerm_resource_group.global.name
  regions = { for k, v in local.workloads : k => {
    location            = v
    resource_group_name = data.azurerm_resource_group.regional[k].name
    subnet_id           = module.network[k].subnet_ids["database"]
    vnet_id             = module.network[k].vnet_id
    server_id           = module.sql[0].server_ids[k]
  } }
  tags = var.tags
}
module "regional" {
  source              = "../../modules/regional"
  for_each            = local.workloads
  name                = "${var.prefix}-${each.key}"
  resource_group_name = data.azurerm_resource_group.regional[each.key].name
  location            = each.value
  network             = module.network[each.key].subnet_ids
  ssh_public_key      = var.ssh_public_key
  vm_size             = each.key == "primary" ? var.vm_size : var.standby_vm_size
  instances           = 2
  database_endpoint   = module.sql[0].connection_endpoint
  front_door_id       = local.rank >= 3 ? module.edge[0].resource_guid : ""
  tags                = var.tags
  depends_on          = [module.network]
}
module "backup" {
  source              = "../../modules/backup"
  for_each            = local.workloads
  name                = "${var.prefix}-${each.key}"
  resource_group_name = data.azurerm_resource_group.regional[each.key].name
  location            = each.value
  tags                = var.tags
}
module "edge" {
  source              = "../../modules/edge"
  count               = local.rank >= 3 ? 1 : 0
  name                = "${var.prefix}-${var.unique_suffix}"
  resource_group_name = data.azurerm_resource_group.global.name
  origins             = { for k, v in module.regional : k => { hostname = v.origin_hostname, priority = k == "primary" ? 1 : 2 } }
  tags                = var.tags
}
output "networks" { value = { for k, v in module.network : k => { vnet_id = v.vnet_id, subnet_ids = v.subnet_ids } } }
output "origins" { value = { for k, v in module.regional : k => v.origin_hostname } }
output "front_door_url" { value = local.rank >= 3 ? module.edge[0].url : null }
output "sql_endpoint" { value = local.rank >= 1 ? module.sql[0].connection_endpoint : null }
output "backup_targets" {
  value = { for k, v in module.backup : k => { resource_group = data.azurerm_resource_group.regional[k].name, vault = v.vault_name, policy = v.policy_name } }
}

output "deployment_prefix" { value = var.prefix }

resource "azurerm_virtual_network_peering" "primary_to_secondary" {
  count                     = local.rank >= 2 ? 1 : 0
  name                      = "primary-to-secondary"
  resource_group_name       = data.azurerm_resource_group.regional["primary"].name
  virtual_network_name      = module.network["primary"].vnet_name
  remote_virtual_network_id = module.network["secondary"].vnet_id
}
resource "azurerm_virtual_network_peering" "secondary_to_primary" {
  count                     = local.rank >= 2 ? 1 : 0
  name                      = "secondary-to-primary"
  resource_group_name       = data.azurerm_resource_group.regional["secondary"].name
  virtual_network_name      = module.network["secondary"].vnet_name
  remote_virtual_network_id = module.network["primary"].vnet_id
}
module "dns" {
  source              = "../../modules/dns"
  count               = local.rank >= 3 && var.dns_zone_name != "" ? 1 : 0
  resource_group_name = data.azurerm_resource_group.global.name
  zone_name           = var.dns_zone_name
  host_label          = var.dns_host_label
  profile_id          = module.edge[0].profile_id
  firewall_policy_id  = module.edge[0].firewall_policy_id
  endpoint_id         = module.edge[0].endpoint_id
  endpoint_hostname   = module.edge[0].hostname
  origin_group_id     = module.edge[0].origin_group_id
  origin_ids          = module.edge[0].origin_ids
  tags                = var.tags
}
output "dns_name_servers" { value = length(module.dns) > 0 ? module.dns[0].name_servers : [] }
output "custom_url" { value = length(module.dns) > 0 ? module.dns[0].url : null }

output "front_door_id" { value = local.rank >= 3 ? module.edge[0].resource_guid : null }
