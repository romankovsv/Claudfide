# Assertion patterns (copy, then adapt)

All snippets assume `mock_provider "azurerm" {}` and a top-level `variables {}`
block. Every `run` uses `command = plan`.

## Secure default

```hcl
run "account_is_locked_down_by_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "The account must require TLS 1.2."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared key access must be off; identities use RBAC."
  }
}
```

## Naming convention

```hcl
run "names_follow_the_convention" {
  command = plan

  assert {
    condition     = azurerm_virtual_network.this.name == "vnet-tp-test"
    error_message = "The virtual network name must be vnet-<name>."
  }

  assert {
    condition     = azurerm_subnet.this["apps"].name == "snet-apps"
    error_message = "Subnet names must be snet-<key>."
  }
}
```

## Cardinality driven by a map or set

```hcl
run "creates_one_container_per_name" {
  command = plan

  assert {
    condition     = length(azurerm_storage_container.this) == 2
    error_message = "Expected one container for each name in var.containers."
  }

  assert {
    condition     = alltrue([for k, c in azurerm_storage_container.this : c.name == k])
    error_message = "Container names must equal their keys."
  }
}
```

## Variable validation (one run per invalid value)

```hcl
run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Invalid-Name"
  }

  expect_failures = [var.name]
}
```

## Conditional / dynamic block, on and off

```hcl
run "adds_dns_zone_group_when_zone_given" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "A DNS zone group must be created when a zone ID is given."
  }
}

run "omits_dns_zone_group_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No DNS zone group must be created without a zone ID."
  }
}
```

## Nested block attributes

```hcl
assert {
  condition     = azurerm_linux_function_app.this.site_config[0].ftps_state == "Disabled"
  error_message = "FTPS must be disabled."
}

assert {
  condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny"
  error_message = "The vault must deny traffic by default."
}
```

## Set-typed arguments

```hcl
assert {
  condition     = contains(azurerm_storage_account_network_rules.this.bypass, "AzureServices")
  error_message = "Trusted Azure services must bypass the network rules."
}
```

## Wiring a variable into an argument

```hcl
assert {
  condition     = azurerm_role_assignment.runtime_storage.scope == var.storage_account_id
  error_message = "The runtime role must be scoped to the storage account passed in."
}
```

## Overriding a data source with side effects

```hcl
mock_provider "external" {}

override_data {
  target = data.external.build_info
  values = { result = { revision = "test-rev" } }
}

run "exposes_build_revision_from_the_script" {
  command = plan

  assert {
    condition     = azurerm_linux_function_app.this.app_settings["BUILD_REVISION"] == "test-rev"
    error_message = "BUILD_REVISION must come from the build-info script output."
  }
}
```

## Overriding a variable for one run only

```hcl
run "uses_given_replication_type" {
  command = plan

  variables {
    replication_type = "GRS"
  }

  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "GRS"
    error_message = "The replication type must be configurable."
  }
}
```

## Stack-level test (root module with its own provider block)

A `mock_provider "azurerm" {}` in the test file replaces the real provider
configuration of `stacks/<name>/provider.tf`; set every required variable in
`variables {}`. From the root you can assert on root resources
(`azurerm_resource_group.this.name`) and on module **outputs** that are known at
plan (strings derived from variables), never on resources inside child modules
or on computed outputs. Keep behaviour tests in the modules; use stack tests
for the composition only (resource group name, environment validation).

```hcl
run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}
```
