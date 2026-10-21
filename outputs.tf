output "vm_public_ips" {
  description = "IP público de cada nó do cluster"
  value       = { for k, vm in azurerm_linux_virtual_machine.vm : vm.name => azurerm_public_ip.pip[k].ip_address }
}

output "ssh_commands" {
  description = "Comando ssh pronto de cada nó"
  value       = { for k, vm in azurerm_linux_virtual_machine.vm : vm.name => "ssh ${var.admin_username}@${azurerm_public_ip.pip[k].ip_address}" }
}
