mock_provider "azurerm" {}

variables {
  name                = "tp-test-vault"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-endpoints"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
  subresource_name    = "vault"
}

run "names_and_subresource_follow_the_inputs" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-tp-test-vault"
    error_message = "The endpoint name must start with pe-."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-tp-test-vault"
    error_message = "The connection name must start with psc-."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "vault")
    error_message = "The sub-resource must be the one requested."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must not need manual approval."
  }
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No DNS zone group may be created when no zone is given."
  }
}

run "dns_zone_group_is_created_for_a_zone" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one DNS zone group is expected when a zone is given."
  }
}
