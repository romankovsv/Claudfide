mock_provider "azurerm" {}

variables {
  name                       = "adf-tp-test"
  resource_group_name        = "rg-test"
  location                   = "westeurope"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
  linked_storage_accounts = {
    raw     = "https://sttptestraw.dfs.core.windows.net"
    curated = "https://sttptestcur.dfs.core.windows.net"
  }
}

run "factory_uses_a_managed_identity" {
  command = plan

  assert {
    condition     = azurerm_data_factory.this.identity[0].type == "SystemAssigned"
    error_message = "The factory must have a system-assigned managed identity."
  }
}

run "public_access_can_be_switched_off" {
  command = plan

  variables {
    public_network_enabled = false
  }

  assert {
    condition     = azurerm_data_factory.this.public_network_enabled == false
    error_message = "Setting public_network_enabled to false must disable public access."
  }
}

run "links_one_storage_service_per_key" {
  command = plan

  assert {
    condition     = length(azurerm_data_factory_linked_service_data_lake_storage_gen2.this) == 2
    error_message = "Expected one linked service for each storage account key."
  }

  assert {
    condition     = azurerm_data_factory_linked_service_data_lake_storage_gen2.this["raw"].name == "ls-raw"
    error_message = "Linked service names must start with ls- followed by the key."
  }

  assert {
    condition     = alltrue([for ls in azurerm_data_factory_linked_service_data_lake_storage_gen2.this : ls.use_managed_identity == true])
    error_message = "Linked services must authenticate with the managed identity, not keys."
  }
}

run "no_linked_services_without_storage_accounts" {
  command = plan

  variables {
    linked_storage_accounts = {}
  }

  assert {
    condition     = length(azurerm_data_factory_linked_service_data_lake_storage_gen2.this) == 0
    error_message = "No linked services may be created when no storage accounts are given."
  }
}

run "sends_pipeline_and_activity_logs_to_the_workspace" {
  command = plan

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this.name == "diag-adf-tp-test"
    error_message = "The diagnostic setting name must be diag- followed by the factory name."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this.enabled_log) == 2
    error_message = "Pipeline runs and activity runs must both be logged."
  }
}
