mock_provider "azurerm" {}

variables {
  name                = "sttptest001"
  resource_group_name = "rg-test"
  location            = "westeurope"
  containers          = ["raw", "curated"]
}

run "account_is_locked_down_by_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "The account must require TLS 1.2."
  }

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Public blob access must be off."
  }

  assert {
    condition     = azurerm_storage_account_network_rules.this.default_action == "Deny"
    error_message = "Network access must be denied by default."
  }
}

run "keys_are_off_and_traffic_is_https_only" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared key access must be off; use Entra ID."
  }

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "Only HTTPS traffic may be accepted."
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "Deleted blobs must be kept for 7 days."
  }
}

run "creates_one_container_per_name" {
  command = plan

  assert {
    condition     = length(azurerm_storage_container.this) == 2
    error_message = "Expected one container for each name."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Invalid-Name"
  }

  expect_failures = [var.name]
}
