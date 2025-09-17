output "vm_public_ip" {
  value = azurerm_public_ip.vm_pip.ip_address
}

output "mysql_fqdn" {
  value = azurerm_mysql_server.mysql.fqdn
}

output "storage_media_container" {
  value = "${azurerm_storage_account.media.name}/${azurerm_storage_container.media_container.name}"
}
