# What mock-based plan tests can and cannot show

`terraform test` with `mock_provider` and `command = plan` runs entirely
offline: no credentials, no API calls, no state. That is the point of these
tests in this repository, and also their ceiling.

## They can show

- The module turns its inputs into the intended arguments: names, flags,
  retention days, SKUs, tags, identity type, network rule defaults.
- Cardinality and keys of repeated resources follow the variables.
- Conditional blocks appear and disappear with their switch.
- Variable `validation` blocks reject what they should.
- A data source's output is wired to the right place (through `override_data`).
- The configuration is syntactically valid against the provider **schema**
  (unknown arguments, wrong types, missing required arguments fail at plan).

## They cannot show

- Anything the Azure API decides: whether a SKU exists in a region, whether a
  globally unique name is free, quota, policy, RBAC propagation, whether an
  identity may read a vault.
- Computed values: IDs, principal IDs, URLs, endpoint IPs, and outputs built
  from them. They are unknown during plan; the mock would only invent
  random strings during apply, which azurerm then rejects as malformed IDs.
- Runtime behaviour: that a function app can actually reach its storage
  through the network rules, that DNS resolves a private endpoint, that a
  linked service authenticates.
- Cross-module wiring beyond what the stack root passes explicitly.
- Drift, cost, or anything about already-deployed infrastructure.

## Consequences for the agent

- A green suite means "the module encodes these intentions", not "this
  deploys". Say so in the report's `limitations`.
- Findings about runtime behaviour (missing DNS zones, missing role
  assignments, unsupported combinations) cannot be turned into tests; they
  go to the reviewer as findings.
- Never try to make a computed value assertable by switching to `apply`.
