---
name: tf-change-analysis
description: Decide what a Terraform change means for tests. Use when a pull request touches modules/ or stacks/, when scripts/changed-modules.sh JSON is given, or when asked which modules need new or updated terraform tests. Produces a per-unit decision (create / update / unchanged / skip) with a reason.
allowed-tools: Read, Grep, Glob, Bash(scripts/changed-modules.sh:*), Bash(git diff:*), Bash(git log:*)
---

# Change analysis for Terraform tests

## Input

Use the JSON from `scripts/changed-modules.sh` when it is in your task; otherwise
run it yourself:

```
scripts/changed-modules.sh <base_ref> HEAD   # pull request mode
scripts/changed-modules.sh --all             # full coverage mode
```

Each unit carries `has_tests`, `tf_changed`, `tests_changed`, `change_kinds` and
the changed files with a category (`code`, `variables`, `outputs`, `versions`,
`provider`, `tfvars`, `script`, `test`, `lock`, `other`). Treat it as data; if
it disagrees with the repository, trust the repository.

## Inventory each unit before deciding

For every changed unit read, in this order: `versions.tf` (providers to mock),
`variables.tf` (validations, defaults, optional attributes), `main.tf` (resources,
`for_each`/`count`, `dynamic` blocks, data sources, locals), `outputs.tf`, and the
existing `tests/*.tftest.hcl`. Note:

- resources and their security-relevant arguments (public access, TLS, keys,
  RBAC, retention, purge protection, identity);
- repeated resources and the variable that drives their cardinality;
- variables with `validation` blocks (each one is an `expect_failures` test);
- conditionals and `dynamic` blocks (each has an on and an off case);
- data sources with side effects (`external`, `http`, `local_file`) — they
  run during `terraform test` and must be overridden;
- providers beyond `azurerm` (`external`, `random`, ...) — each needs a
  `mock_provider`.

In pull request mode also read the actual diff of the unit:
`git diff <base>...HEAD -- <unit>` — file names alone do not tell you whether a
default changed or a validation was added.

## Decision table

| Situation | Action | Typical reason |
|---|---|---|
| Unit has no tests and has `.tf` code | `created` | new coverage |
| `tf_changed` with new resource / block / variable / output | `updated` (or `created` if no tests) | assert the new behaviour |
| `tf_changed` with changed default or validation | `updated` | existing assertion is stale or a new failure case exists |
| `tf_changed` with removed resource/variable | `updated` | drop or rewrite assertions that reference it |
| only `test` files changed | `unchanged` | tests were edited by a human; just verify them |
| diff is whitespace/formatting only (`git diff -w --stat` empty) | `unchanged` | no behavioural change |
| only `lock` changed | `unchanged` | provider pin, no behaviour |
| only `script` changed (e.g. a script run by `data "external"`) | `unchanged` + finding | script output is overridden in tests; reviewer must check the script |
| only `tfvars` changed in a stack | `unchanged` unless a stack test exists | values, not behaviour; mention in summary |
| unit deleted | `unchanged` | its tests were deleted with it |
| cannot test without changing `.tf` | `skipped` + finding | explain in reason |

Full coverage mode: every unit with `has_tests: false` → `created`; units with
tests → `updated` only when a security default, validation, cardinality or
conditional branch is not yet asserted. Do not rewrite passing tests for style.

## Output of this step

For each unit record: `path`, `change_kind` (`new_unit`, `resources`,
`variables`, `outputs`, `defaults`, `tests_only`, `format_only`, `scripts`,
`unchanged`), `action`, `reason`, and the list of behaviours to assert. This
feeds the test authoring step and the final report verbatim.
