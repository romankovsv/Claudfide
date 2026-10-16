# Review checklist with Azure specifics

Each entry: what to look for → why it matters → typical severity.

## Exposure

- `public_network_access_enabled` / `public_network_enabled` defaulting to
  `true` in a module while the stack defaults to `false` → inconsistent
  defaults let a direct module use ship exposed → medium.
- `azurerm_private_endpoint` without `private_dns_zone_group` and no
  `private_dns_zone_id` passed from the stack → clients still resolve the
  public IP; the endpoint is decorative → medium.
- Storage/Key Vault with `default_action = "Deny"` plus `virtual_network_subnet_ids`
  **and** private endpoints → two access models at once; clarify which is
  intended → low.
- Services outside the VNet (Function App without VNet integration, Data
  Factory without managed VNet) that must reach a `Deny`-by-default resource →
  will fail at runtime → medium.
- `ftps_state = "AllAllowed"` → plaintext FTP → high.
- `min_tls_version` below `TLS1_2`, `https_only = false`,
  `https_traffic_only_enabled = false` → high.

## Secrets and keys

- `shared_access_key_enabled = false` on an account used as a Function App
  runtime store on an Elastic Premium / Dedicated plan → Azure Files content
  share needs a key; identity-based Azure Files is unsupported → medium.
- Managed identity on a linked service (`use_managed_identity = true`) with no
  `azurerm_role_assignment` for that identity → authentication fails at
  runtime → medium.
- Overly broad roles (`Storage Blob Data Owner` on a whole data lake for a
  runtime identity) → least privilege → low/medium.
- Secrets in `app_settings`, `tfvars`, or plain `value =` on
  `azurerm_key_vault_secret` → high.

## Data protection

- `purge_protection_enabled` and `soft_delete_retention_days` on Key Vault;
  `delete_retention_policy`, `container_delete_retention_policy`, versioning
  on storage; `retention_in_days` on Log Analytics → missing in prod → medium.
- `account_replication_type = "LRS"` not overridable per environment →
  production durability → low/medium.

## Determinism

- `data "external"` running a script (`git rev-parse`, `date`, network) →
  plan changes every run, script runs during `terraform test`; tests must
  override it; review the script when it changes → medium.
- `timestamp()`, `uuid()`, `random_*` without `keepers` → perpetual diffs → low.

## Conventions (README of this repository)

- Files `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` only;
  `provider.tf` carrying `terraform {}` in a stack → low.
- `count` instead of `for_each` for repeated resources → low.
- Environments `dev`, `uat`, `prod`: an `envs/<env>.tfvars` missing → low.
- Hard-coded SKUs (`EP1`, `premium`, `standard`) with no variable → low.
- Global-uniqueness names without a suffix (storage accounts, key vaults,
  function apps) → low in a test repo, medium for real deployments.

## Tests

- A validation block with no `expect_failures` test → info.
- Assertions that only restate literal values of the resource, with no
  variable involved → info ("low signal").
- Behaviour that only the API can verify → info, state it in `limitations`.
