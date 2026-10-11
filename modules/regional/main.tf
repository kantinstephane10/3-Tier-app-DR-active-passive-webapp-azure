resource "azurerm_public_ip" "ingress" {
  name                = "pip-${var.name}-ingress"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  domain_name_label   = "${var.name}-${substr(md5(var.resource_group_name), 0, 8)}"
  tags                = var.tags
}
resource "azurerm_application_gateway" "this" {
  name                = "agw-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  zones               = ["1", "2"]
  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }
  autoscale_configuration { min_capacity = 1 }
  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = var.network["ingress"]
  }
  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.ingress.id
  }
  frontend_port {
    name = "http"
    port = 80
  }
  backend_address_pool { name = "web" }
  backend_http_settings {
    name                  = "web-http"
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 30
    probe_name            = "web-health"
  }
  probe {
    name                = "web-health"
    protocol            = "Http"
    host                = "127.0.0.1"
    path                = "/health"
    interval            = 30
    timeout             = 10
    unhealthy_threshold = 3
  }
  http_listener {
    name                           = "http"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }
  request_routing_rule {
    name                       = "web"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "http"
    backend_address_pool_name  = "web"
    backend_http_settings_name = "web-http"
  }
  tags = var.tags
}
resource "azurerm_lb" "app" {
  name                = "lb-${var.name}-app"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  frontend_ip_configuration {
    name                          = "private"
    subnet_id                     = var.network["app"]
    private_ip_address_allocation = "Dynamic"
    zones                         = ["1", "2", "3"]
  }
  tags = var.tags
}
resource "azurerm_lb_backend_address_pool" "app" {
  name            = "app"
  loadbalancer_id = azurerm_lb.app.id
}
resource "azurerm_lb_probe" "app" {
  name            = "app-health"
  loadbalancer_id = azurerm_lb.app.id
  port            = 8080
  protocol        = "Http"
  request_path    = "/health"
}
resource "azurerm_lb_rule" "app" {
  name                           = "app-http"
  loadbalancer_id                = azurerm_lb.app.id
  protocol                       = "Tcp"
  frontend_port                  = 8080
  backend_port                   = 8080
  frontend_ip_configuration_name = "private"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app.id]
  probe_id                       = azurerm_lb_probe.app.id
}
resource "azurerm_orchestrated_virtual_machine_scale_set" "tier" {
  for_each                    = toset(["web", "app"])
  name                        = "vmss-${var.name}-${each.key}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  sku_name                    = var.vm_size
  instances                   = var.instances
  platform_fault_domain_count = 1
  zones                       = ["1", "2"]
  zone_balance                = false
  os_profile {
    custom_data = base64encode(templatefile("${path.module}/cloud-init-${each.key}.yaml.tftpl", {
      app_ip            = azurerm_lb.app.private_ip_address
      region            = var.location
      database_endpoint = var.database_endpoint
      front_door_id     = var.front_door_id
    }))
    linux_configuration {
      admin_username                  = "azureadmin"
      disable_password_authentication = true
      admin_ssh_key {
        username   = "azureadmin"
        public_key = var.ssh_public_key
      }
    }
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  network_interface {
    name    = "nic"
    primary = true
    ip_configuration {
      name                                         = "private"
      primary                                      = true
      subnet_id                                    = var.network[each.key]
      application_gateway_backend_address_pool_ids = each.key == "web" ? [one(azurerm_application_gateway.this.backend_address_pool).id] : []
      load_balancer_backend_address_pool_ids       = each.key == "app" ? [azurerm_lb_backend_address_pool.app.id] : []
    }
  }
  boot_diagnostics {}
  tags = merge(var.tags, { tier = each.key })
  lifecycle { ignore_changes = [instances] }
}
resource "azurerm_monitor_autoscale_setting" "tier" {
  for_each            = azurerm_orchestrated_virtual_machine_scale_set.tier
  name                = "autoscale-${var.name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = each.value.id
  profile {
    name = "cpu"
    capacity {
      default = tostring(var.instances)
      minimum = tostring(var.instances)
      maximum = "4"
    }
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = each.value.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = each.value.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
  tags = var.tags
}
output "origin_hostname" { value = azurerm_public_ip.ingress.fqdn }
output "scale_sets" { value = { for k, v in azurerm_orchestrated_virtual_machine_scale_set.tier : k => v.name } }
