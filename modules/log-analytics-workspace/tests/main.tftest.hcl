mock_provider "azurerm" {}

variables {
  name                = "log-tp-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "defaults_to_30_days_retention_on_pergb2018" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "Default retention must be 30 days."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "The workspace must use the PerGB2018 tier."
  }
}

run "retention_can_be_raised" {
  command = plan

  variables {
    retention_in_days = 90
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 90
    error_message = "The retention variable must be passed to the workspace."
  }
}
