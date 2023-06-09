terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.0.0"
    }

  }
}

provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "erik" {
  name     = "erik-rg"
  location = "West Europe"
}

resource "azurerm_virtual_network" "erik-vn" {
  name                = "erik-virtualnetwork"
  resource_group_name = azurerm_resource_group.erik.name
  location            = azurerm_resource_group.erik.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "ontw"
  }



}

resource "azurerm_subnet" "erik-subnet" {
  name                 = "erik-subnet"
  resource_group_name  = azurerm_resource_group.erik.name
  virtual_network_name = azurerm_virtual_network.erik-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "erik-sg" {
  name                = "erik-sg"
  location            = azurerm_resource_group.erik.location
  resource_group_name = azurerm_resource_group.erik.name

  tags = {
    environment = "ontw"
  }

}

resource "azurerm_network_security_rule" "erik-ontw-rule" {
  name                        = "erik-ontw-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "86.89.9.185/32"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.erik.name
  network_security_group_name = azurerm_network_security_group.erik-sg.name
}

resource "azurerm_subnet_network_security_group_association" "erik-sga" {
  subnet_id                 = azurerm_subnet.erik-subnet.id
  network_security_group_id = azurerm_network_security_group.erik-sg.id
}

resource "azurerm_public_ip" "erik-ip" {
  name                = "erik-ip"
  resource_group_name = azurerm_resource_group.erik.name
  location            = azurerm_resource_group.erik.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "ontw"
  }
}

resource "azurerm_network_interface" "erik-nic" {
  name                = "erik-nic"
  location            = azurerm_resource_group.erik.location
  resource_group_name = azurerm_resource_group.erik.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.erik-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.erik-ip.id
  }

  tags = {
    environment = "ontw"
  }

}

resource "azurerm_linux_virtual_machine" "erik-vm" {
  name                = "erik-vm"
  resource_group_name = azurerm_resource_group.erik.name
  location            = azurerm_resource_group.erik.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.erik-nic.id
  ]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/id_rsa"

    })

    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]

  }


  tags = {
    environment = "ontw"
  }

}

data "azurerm_public_ip" "erik-ip-data" {
  name                = azurerm_public_ip.erik-ip.name
  resource_group_name = azurerm_resource_group.erik.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.erik-vm.name}: ${data.azurerm_public_ip.erik-ip-data.ip_address}"
}
