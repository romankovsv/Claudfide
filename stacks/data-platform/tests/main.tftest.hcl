mock_provider "azurerm" {}
mock_provider "external" {}

# The function app module runs a shell script through the external provider.
override_data {
  target = module.function_app.data.external.build_info
  values = { result = { revision = "test-rev" } }
}

variables {
  subscription_id    = "00000000-0000-0000-0000-000000000001"
  tenant_id          = "00000000-0000-0000-0000-000000000000"
  environment        = "dev"
  vnet_address_space = ["10.20.0.0/16"]
  data_lakes = {
    raw     = { containers = ["landing", "bronze"] }
    curated = { containers = ["silver", "gold"] }
  }
}

run "names_and_tags_follow_the_environment" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-tp-dev"
    error_message = "The resource group must be named rg-tp-<environment>."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["environment"] == "dev"
    error_message = "Resources must be tagged with their environment."
  }
}

run "one_data_lake_per_key_and_two_endpoints_each" {
  command = plan

  assert {
    condition     = length(module.data_lake) == 2
    error_message = "Expected one storage account for each entry in data_lakes."
  }

  assert {
    condition     = length(module.lake_endpoint) == 4
    error_message = "Expected a blob and a dfs private endpoint for each data lake."
  }
}

run "subnets_are_carved_from_the_address_space" {
  command = plan

  assert {
    condition     = local.subnets["apps"].address_prefixes[0] == "10.20.0.0/24" && local.subnets["endpoints"].address_prefixes[0] == "10.20.1.0/24"
    error_message = "The apps and endpoints subnets must be the first two /24 ranges of the virtual network."
  }
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}
