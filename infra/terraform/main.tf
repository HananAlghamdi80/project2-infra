#########################################
# Resource Group
#########################################
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

#########################################
# Virtual Network
#########################################
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

#########################################
# Subnets
#########################################
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "snet-frontend"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "snet-backend"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_subnet" "sql" {
  name                 = "snet-sql"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.4.0/24"]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "containerapps" {
  name                 = "snet-containerapps"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.6.0/23"]
}

#########################################
# Public IP for Application Gateway
#########################################
resource "azurerm_public_ip" "appgw_pip" {
  name                = "${var.prefix}-appgw-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

#########################################
# Application Gateway (WAF_v2)
#########################################
resource "azurerm_application_gateway" "appgw" {
  name                = "${var.prefix}-appgw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 3
  }

  ssl_policy {
    policy_type          = "Predefined"
    policy_name          = "AppGwSslPolicy20220101"
    min_protocol_version = "TLSv1_2"
  }

  gateway_ip_configuration {
    name      = "appgw-ipcfg"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  #########################################
  # 🔍 Health Probes
  #########################################
  probe {
    name                = "frontend-probe"
    protocol            = "Http"
    path                = "/"             # ✅ Frontend check root path
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-404"]
    }
  }

  probe {
    name                = "backend-probe"
    protocol            = "Http"
    path                = "/api/health"   # ✅ Required by task spec
    interval            = 30
    timeout             = 60
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-404"]
    }
  }

  #########################################
  # 🟢 Backend Pools
  #########################################
  backend_address_pool {
    name  = "frontend-pool"
    fqdns = ["p2-frontend.internal.happyglacier-2bde9e6a.eastus.azurecontainerapps.io"]
  }

  backend_address_pool {
    name  = "backend-pool"
    fqdns = ["p2-backend.internal.happyglacier-2bde9e6a.eastus.azurecontainerapps.io"]
  }

  #########################################
  # ⚙️ HTTP Settings
  #########################################
  backend_http_settings {
    name                                = "frontend-http-settings"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 30
    cookie_based_affinity               = "Disabled"
    probe_name                          = "frontend-probe"
    pick_host_name_from_backend_address = true
  }

  backend_http_settings {
    name                                = "backend-http-settings"
    port                                = 8080
    protocol                            = "Http"
    request_timeout                     = 60
    cookie_based_affinity               = "Disabled"
    probe_name                          = "backend-probe"
    pick_host_name_from_backend_address = true
  }

  #########################################
  # 🌐 Listener & Routing
  #########################################
  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-81"
    port = 81
  }

  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  http_listener {
    name                           = "listener-ip"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "port-81"
    protocol                       = "Http"
  }

  url_path_map {
    name = "path-map"

    default_backend_address_pool_name  = "frontend-pool"
    default_backend_http_settings_name = "frontend-http-settings"

    path_rule {
      name                       = "api-rule"
      paths                      = ["/api/*"]
      backend_address_pool_name  = "backend-pool"
      backend_http_settings_name = "backend-http-settings"
    }
  }

  request_routing_rule {
    name               = "path-routing-rule"
    rule_type          = "PathBasedRouting"
    http_listener_name = "listener-http"
    url_path_map_name  = "path-map"
    priority           = 10
  }

  request_routing_rule {
    name                       = "rule-ip-access"
    rule_type                  = "Basic"
    http_listener_name         = "listener-ip"
    backend_address_pool_name  = "frontend-pool"
    backend_http_settings_name = "frontend-http-settings"
    priority                   = 20
  }

  #########################################
  # 🧱 WAF Configuration
  #########################################
  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }
}
