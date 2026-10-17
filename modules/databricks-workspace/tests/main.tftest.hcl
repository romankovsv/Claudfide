mock_provider "azurerm" {}

variables {
  name                = "dbw-tp-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "cluster_nodes_get_no_public_ips" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "Cluster nodes must not get public IP addresses."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "premium"
    error_message = "The default tier must be premium."
  }
}

run "managed_resource_group_name_is_derived" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.managed_resource_group_name == "rg-test-dbw-tp-test-managed"
    error_message = "The managed resource group must be named <resource group>-<name>-managed."
  }
}

run "public_access_can_be_switched_off" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "Setting public_network_access_enabled to false must disable public access."
  }
}

run "public_access_is_off_by_default" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "Public network access must be disabled unless the caller opts in."
  }
}

run "public_access_can_be_switched_on" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == true
    error_message = "Setting public_network_access_enabled to true must enable public access."
  }
}

run "accepts_standard_sku" {
  command = plan

  variables {
    sku = "standard"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "standard"
    error_message = "The standard tier must be accepted and passed through."
  }
}

run "rejects_unknown_sku" {
  command = plan

  variables {
    sku = "trial"
  }

  expect_failures = [var.sku]
}
