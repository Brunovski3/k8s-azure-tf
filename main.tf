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
  count               = var.vm_count
  name                = "pip-${var.cluster_name}-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  count               = var.vm_count
  name                = "nic-${var.cluster_name}-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  count                     = var.vm_count
  network_interface_id      = azurerm_network_interface.nic[count.index].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  count                           = var.vm_count
  name                            = count.index == 0 ? "${var.cluster_name}-master" : "${var.cluster_name}-worker-${count.index}"
  computer_name                   = count.index == 0 ? "${var.cluster_name}-master" : "${var.cluster_name}-worker-${count.index}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = count.index == 0 ? var.vm_size : var.worker_vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nic[count.index].id]

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
  count              = var.vm_count
  virtual_machine_id = azurerm_linux_virtual_machine.vm[count.index].id
  location           = azurerm_resource_group.rg.location
  enabled            = true

  daily_recurrence_time = var.shutdown_time
  timezone              = var.shutdown_timezone

  notification_settings {
    enabled = false
  }
}
