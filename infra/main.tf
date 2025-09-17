locals {
  name_prefix = var.prefix
}

resource "azurerm_resource_group" "rg" {
  name     = "${local.name_prefix}-rg"
  location = var.location
}

# Storage account for WordPress media
resource "azurerm_storage_account" "media" {
  name                     = substr("${local.name_prefix}media", 0, 24)
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  kind                     = "StorageV2"
}

resource "azurerm_storage_container" "media_container" {
  name                  = "media"
  storage_account_name  = azurerm_storage_account.media.name
  container_access_type = "private"
}

# Networking
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${local.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${local.name_prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Public IP + NIC for the VM
resource "azurerm_public_ip" "vm_pip" {
  name                = "${local.name_prefix}-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "${local.name_prefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id
  }
}

# MySQL server (Azure Database for MySQL Single Server example)
resource "random_password" "mysql_admin" {
  length  = 20
  special = true
}

resource "azurerm_mysql_server" "mysql" {
  name                = "${local.name_prefix}-mysql"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = "GP_Gen5_2"
  storage_mb = 5120
  version    = "8.0"

  administrator_login          = "mysqladmin"
  administrator_login_password = random_password.mysql_admin.result

  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  public_network_access_enabled     = true
  ssl_enforcement_enabled           = true
}

resource "azurerm_mysql_database" "wordpress" {
  name                = "wordpressdb"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_server.mysql.name
  charset             = "utf8"
  collation           = "utf8_general_ci"
}

# Linux VM for WordPress with cloud-init
data "template_file" "cloudinit" {
  template = file("${path.module}/cloud-init.tpl")

  vars = {
    db_host     = azurerm_mysql_server.mysql.fqdn
    db_name     = azurerm_mysql_database.wordpress.name
    db_user     = azurerm_mysql_server.mysql.administrator_login
    db_pass     = random_password.mysql_admin.result
    storage_account = azurerm_storage_account.media.name
    storage_container = azurerm_storage_container.media_container.name
  }
}

resource "azurerm_linux_virtual_machine" "wordpress" {
  name                = "${local.name_prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.vm_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # cloud-init must be base64 encoded per Azure rules
  custom_data = base64encode(data.template_file.cloudinit.rendered)

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub") # you can parameterize this
  }

  tags = {
    project = "wordpress-opentofu"
  }
}
