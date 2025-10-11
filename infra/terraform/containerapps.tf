#########################################
# Variables for ACR & SQL Connection
#########################################
variable "acr_name" {
  default = "p2acr"
}

variable "sql_server_fqdn" {
  # 👇 استخدم FQDN الخاص بـ Private Link
  default = "p2-sqlsrv-eastus2.privatelink.database.windows.net"
}

variable "sql_db_name" {
  default = "hanandb"
}

#########################################
# Container Apps Environment
#########################################
resource "azurerm_container_app_environment" "cae" {
  name                     = "${var.prefix}-cae"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  infrastructure_subnet_id = azurerm_subnet.containerapps.id
}

#########################################
# Frontend Container App (Private Ingress ✅)
#########################################
resource "azurerm_container_app" "frontend_app" {
  name                         = "${var.prefix}-frontend"
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.cae.id
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "frontend"
      image  = "${var.acr_name}.azurecr.io/frontend:1.0"
      cpu    = 0.5
      memory = "1Gi"
    }
  }

  ingress {
    external_enabled = false # 🔒 يمنع الوصول من الإنترنت
    target_port      = 80
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  registry {
    server               = "${var.acr_name}.azurecr.io"
    username             = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.acr.admin_password
  }
}

#########################################
# Backend Container App (Private Ingress ✅)
#########################################
resource "azurerm_container_app" "backend_app" {
  name                         = "${var.prefix}-backend"
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.cae.id
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "backend"
      image  = "${var.acr_name}.azurecr.io/backend:1.0"
      cpu    = 0.5
      memory = "1Gi"

      # ✅ تحديد بيئة التشغيل
      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = "azure"
      }

      # ✅ إعدادات قاعدة بيانات Azure SQL
      env {
        name  = "DB_HOST"
        value = var.sql_server_fqdn
      }
      env {
        name  = "DB_PORT"
        value = "1433"
      }
      env {
        name  = "DB_NAME"
        value = var.sql_db_name
      }
      env {
        name  = "DB_USERNAME"
        value = "sqladminuser"
      }
      env {
        name  = "DB_PASSWORD"
        value = "Hh123@123"
      }
      env {
        name  = "DB_DRIVER"
        value = "com.microsoft.sqlserver.jdbc.SQLServerDriver"
      }
    }
  }

  ingress {
    external_enabled = false # 🔒 يمنع الوصول من الإنترنت
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  registry {
    server               = "${var.acr_name}.azurecr.io"
    username             = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.acr.admin_password
  }
}
