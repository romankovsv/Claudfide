---
name: tf-test-authoring
description: Write or update terraform test files (.tftest.hcl) for the modules and stacks of this repository. Use when creating tests for a module, adding coverage, or fixing a test that fails; covers house conventions, mock providers, override_data, assertion patterns and what mock-based plan tests can and cannot prove.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(scripts/tf.sh:*)
---

# Authoring terraform tests in this repository

Existing suites (`modules/network`, `modules/storage-account`,
`modules/key-vault`) are the style reference. Read one before writing.
Concrete snippets for every pattern below are in `reference/patterns.md`;
limits of the mock-based approach in `reference/mock-limits.md`.

## File layout

- One file per unit: `tests/main.tftest.hcl`. Add `tests/<topic>.tftest.hcl`
  only when `main` would exceed ~150 lines or a topic needs different
  top-level `variables`.
- Top of file, in this order: one `mock_provider "<name>" {}` per provider in
  `versions.tf`; `override_data`/`override_resource` blocks; a `variables {}`
  block with realistic values (`tp-test`, `rg-test`, `westeurope`, zero GUIDs,
  well-formed Azure resource IDs for `*_id` inputs); then `run` blocks.
- `run` names: lower snake_case sentences stating the behaviour
  (`rejects_invalid_name`, `creates_one_container_per_name`). Every run uses
  `command = plan`. Two to four `assert`s per run; `error_message` is a full
  sentence saying what must hold.

## What to assert, in priority order

1. **Secure defaults** the module promises: public access off, TLS floor,
   shared keys off, RBAC on, purge protection, retention, HTTPS only, identity.
2. **Naming conventions**: prefixes (`vnet-`, `snet-`, `pe-`, `asp-`), derived
   names (`"${var.resource_group_name}-${var.name}-managed"`).
3. **Cardinality of `for_each`/`count`**: `length(resource.x) == N` and that
   the map keys drive the names (`resource.x["key"].name`).
4. **Variable validation**: one `run` per invalid value with
   `expect_failures = [var.<name>]` and the invalid value set in the run's
   own `variables {}` block.
5. **Conditionals and `dynamic` blocks**: one run with the feature on
   (`length(resource.x.block) == 1`) and one with it off (`== 0`).
6. **Wiring that is known at plan**: arguments copied from variables, module
   inputs forwarded unchanged, `role_definition_name`, `subresource_names`.

Prefer assertions that would fail if someone *broke* the behaviour over
assertions that restate the configuration.

## What not to assert (plan + mock providers)

- Anything **computed**: `id`, `principal_id`, `workspace_url`,
  `vault_uri`, `primary_dfs_endpoint`, `private_ip_address`, and outputs built
  from them. They are unknown at plan; the assertion errors with
  "Unknown condition value" **and every later run in the file is skipped**.
- `command = apply` with mock providers: the azurerm provider validates
  resource-ID arguments client-side and rejects the random IDs the mock
  generates. Stay with `plan`.
- Provider-side validation (invalid SKU names, region availability, global
  name uniqueness, policy): a mock never checks it.
- Values that only exist in `.tfvars` of a stack.

## Data sources and extra providers

- Any data source with side effects or network access (`external`, `http`,
  `local_file`) must be overridden so the test is hermetic:

  ```hcl
  mock_provider "external" {}

  override_data {
    target = data.external.build_info
    values = { result = { revision = "test-rev" } }
  }
  ```
  Then assert that the overridden value flows where it should
  (`app_settings["BUILD_REVISION"] == "test-rev"`).
- `mock_provider "azurerm" {}` also mocks azurerm data sources; their
  computed attributes stay unknown, so do not assert on them.

## Nested blocks and maps

Nested blocks are lists: `resource.x.site_config[0].ftps_state`,
`resource.x.network_acls[0].default_action`, `resource.x.identity[0].type`.
Maps and sets from `for_each` are indexed by key: `azurerm_subnet.this["apps"]`.
Set-typed arguments compare with `contains(...)` or `tolist(...)`, not `==` on
a list literal.

## Updating an existing file

Keep the existing runs unless the behaviour they assert was removed. Add new
runs at the end, grouped with a one-line `#` heading if the file has sections.
Do not reorder or rename passing runs; reviewers diff these files.

## Finish

After writing: `scripts/tf.sh fmt-fix <unit>` then hand over to the
`tf-test-verify` skill. Never leave a file with a run you have not executed.
