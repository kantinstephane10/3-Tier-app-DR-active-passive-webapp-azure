locals {
  subnets = {
    AzureBastionSubnet = cidrsubnet(var.cidr, 10, 0)
    ingress            = cidrsubnet(var.cidr, 8, 1)
    web                = cidrsubnet(var.cidr, 8, 10)
    app                = cidrsubnet(var.cidr, 8, 20)
    database           = cidrsubnet(var.cidr, 8, 30)
  }
  tiers = toset(["web", "app", "database"])
}
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.cidr]
  tags                = var.tags
}
resource "azurerm_subnet" "this" {
  for_each                          = local.subnets
  name                              = each.key == "AzureBastionSubnet" ? each.key : "snet-${each.key}"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [each.value]
  private_endpoint_network_policies = "Enabled"
}
resource "azurerm_network_security_group" "tier" {
  for_each            = local.tiers
  name                = "nsg-${var.name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  security_rule {
    name                       = "Allow-required-tier-traffic"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = each.key == "web" ? "80" : each.key == "app" ? "8080" : "1433"
    source_address_prefixes    = each.key == "database" && var.remote_cidr != null ? [local.subnets["app"], cidrsubnet(var.remote_cidr, 8, 20)] : [local.subnets[each.key == "web" ? "ingress" : each.key == "app" ? "web" : "app"]]
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-load-balancer-probes"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = each.key == "web" ? "80" : each.key == "app" ? "8080" : "1433"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-bastion-ssh"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.subnets["AzureBastionSubnet"]
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Deny-other-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "tier" {
  for_each                  = local.tiers
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.tier[each.key].id
}
resource "azurerm_public_ip" "nat" {
  for_each            = var.enable_nat ? toset(["web", "app"]) : toset([])
  name                = "pip-${var.name}-nat-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}
resource "azurerm_nat_gateway" "this" {
  for_each                = azurerm_public_ip.nat
  name                    = "nat-${var.name}-${each.key}"
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}
resource "azurerm_nat_gateway_public_ip_association" "this" {
  for_each             = azurerm_nat_gateway.this
  nat_gateway_id       = each.value.id
  public_ip_address_id = azurerm_public_ip.nat[each.key].id
}
resource "azurerm_subnet_nat_gateway_association" "this" {
  for_each       = azurerm_nat_gateway.this
  subnet_id      = azurerm_subnet.this[each.key].id
  nat_gateway_id = each.value.id
}
output "subnet_ids" { value = { for k, v in azurerm_subnet.this : k => v.id } }
output "vnet_id" { value = azurerm_virtual_network.this.id }

resource "azurerm_network_security_group" "ingress" {
  name                = "nsg-${var.name}-ingress"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  security_rule {
    name                       = "Allow-Front-Door"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "AzureFrontDoor.Backend"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-Gateway-Manager"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-load-balancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Deny-other-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "ingress" {
  subnet_id                 = azurerm_subnet.this["ingress"].id
  network_security_group_id = azurerm_network_security_group.ingress.id
}

output "vnet_name" { value = azurerm_virtual_network.this.name }
