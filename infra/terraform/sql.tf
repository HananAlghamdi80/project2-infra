#########################################
# Variables
#########################################
variable "sql_admin_user" {
  default = "sqladminuser"
}

variable "sql_admin_password" {
  # لأغراض الاختبار - في مشروع حقيقي خزنيه في Secret أو KeyVault
  default = "Hh123@123"
}

#########################################
# SQL Server
#########################################
resource "azurerm_mssql_server" "sql_server" {
  name                         = "${var.prefix}-sqlsrv-eastus2" # ✅ اسم جديد وفريد
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = "eastus2" # ✅ المنطقة الجديدة
  version                      = "12.0"
  administrator_login          = var.sql_admin_user
  administrator_login_password = var.sql_admin_password

  public_network_access_enabled = true # 🚫 يمنع الوصول العام
}

#########################################
# SQL Database
#########################################
resource "azurerm_mssql_database" "sql_db" {
  name           = "hanandb" # ✅ اسم قاعدة البيانات
  server_id      = azurerm_mssql_server.sql_server.id
  sku_name       = "S0"
  max_size_gb    = 5
  zone_redundant = false
}

#########################################
# Private DNS Zone
#########################################
resource "azurerm_private_dns_zone" "sql_dns" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_dns_link" {
  name                  = "${var.prefix}-dnslink"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.sql_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

#########################################
# Private Endpoint for SQL
#########################################
resource "azurerm_private_endpoint" "sql_pe" {
  name                = "${var.prefix}-sql-pe"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.sql.id

  private_service_connection {
    name                           = "${var.prefix}-sql-psc"
    private_connection_resource_id = azurerm_mssql_server.sql_server.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql_dns.id]
  }
}
