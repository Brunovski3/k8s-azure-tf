terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_id" "suffix" {
  byte_length = 2
  keepers = {
    cluster_name = var.cluster_name
  }
}

# Um nó por chave: control-plane ("master") + N-1 workers.
# Elas são identificadas por nome e não por índice — adicionar ou
# remover um worker não reescreve os nós existentes, como acontecia com count.
locals {
  nodes = merge(
    { "master" = var.vm_size },
    { for i in range(var.vm_count - 1) : "worker-${i + 1}" => var.worker_vm_size }
  )
}

# Nomes derivados do cluster_name + sufixo único de 4 hex chars.
# Permite subir o blueprint duas vezes na mesma conta sem conflito de nomes.
resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}-${random_id.suffix.hex}"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.cluster_name}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.cluster_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "K8sAPI"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "NodePort"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }

  # Libera todo tráfego interno entre as VMs do cluster (calico/flannel, etcd, kubelet etc)
  security_rule {
    name                       = "InternalAll"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.10.1.0/24"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "pip" {
  for_each            = local.nodes
  name                = "pip-${var.cluster_name}-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  for_each            = local.nodes
  name                = "nic-${var.cluster_name}-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[each.key].id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  for_each                  = local.nodes
  network_interface_id      = azurerm_network_interface.nic[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.nodes
  name                            = "${var.cluster_name}-${each.key}"
  computer_name                   = "${var.cluster_name}-${each.key}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = each.value
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nic[each.key].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = filebase64("${path.module}/cloud-init.yaml")
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "shutdown" {
  for_each            = local.nodes
  virtual_machine_id = azurerm_linux_virtual_machine.vm[each.key].id
  location           = azurerm_resource_group.rg.location
  enabled            = true

  daily_recurrence_time = var.shutdown_time
  timezone              = var.shutdown_timezone

  notification_settings {
    enabled = false
  }
}
