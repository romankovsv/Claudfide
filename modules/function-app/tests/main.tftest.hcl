mock_provider "azurerm" {}
mock_provider "external" {}

# The real data source runs scripts/build-info.sh; keep the test hermetic.
override_data {
  target = data.external.build_info
  values = { result = { revision = "test-rev" } }
}

variables {
  name                 = "func-tp-test"
  resource_group_name  = "rg-test"
  location             = "westeurope"
  storage_account_name = "sttptestraw"
  storage_account_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttptestraw"
  app_settings = {
    FOO = "bar"
  }
}

run "app_is_https_only_with_tls_12_and_managed_identity" {
  command = plan

  assert {
    condition     = azurerm_linux_function_app.this.https_only == true
    error_message = "The function app must accept HTTPS only."
  }

  assert {
    condition     = azurerm_linux_function_app.this.site_config[0].minimum_tls_version == "1.2"
    error_message = "The function app must require TLS 1.2."
  }

  assert {
    condition     = azurerm_linux_function_app.this.identity[0].type == "SystemAssigned"
    error_message = "The function app must have a system-assigned managed identity."
  }

  assert {
    condition     = azurerm_linux_function_app.this.storage_uses_managed_identity == true
    error_message = "The runtime storage must be reached with the managed identity, not a key."
  }
}

run "build_revision_comes_from_the_data_source" {
  command = plan

  assert {
    condition     = azurerm_linux_function_app.this.app_settings["BUILD_REVISION"] == "test-rev"
    error_message = "BUILD_REVISION must carry the revision reported by the build info script."
  }

  assert {
    condition     = azurerm_linux_function_app.this.app_settings["FOO"] == "bar"
    error_message = "Caller-supplied app settings must be kept."
  }
}

run "service_plan_is_linux_with_the_asp_prefix" {
  command = plan

  assert {
    condition     = azurerm_service_plan.this.name == "asp-func-tp-test"
    error_message = "The service plan name must start with asp-."
  }

  assert {
    condition     = azurerm_service_plan.this.os_type == "Linux"
    error_message = "The service plan must be Linux."
  }
}

run "runtime_storage_role_is_blob_data_owner_on_the_given_account" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.runtime_storage.role_definition_name == "Storage Blob Data Owner"
    error_message = "The app needs Storage Blob Data Owner on its runtime storage."
  }

  assert {
    condition     = azurerm_role_assignment.runtime_storage.scope == var.storage_account_id
    error_message = "The role must be assigned on the storage account passed in."
  }
}
