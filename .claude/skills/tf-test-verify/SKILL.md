---
name: tf-test-verify
description: Run and interpret terraform tests for a module or stack through scripts/tf.sh. Use after writing or changing .tftest.hcl files, when a test run fails, or when asked whether the tests of a unit pass; covers the exact commands, how to read failures, the retry budget, and the rule that failing tests are never committed.
allowed-tools: Read, Edit, Bash(scripts/tf.sh:*)
---

# Verifying terraform tests

Only `scripts/tf.sh` runs Terraform here. It initialises without a backend,
scrubs the environment and refuses anything but these commands:

```
scripts/tf.sh fmt      <unit>      # exit 3 when files need formatting
scripts/tf.sh fmt-fix  <unit>      # format in place (also formats tests/)
scripts/tf.sh validate <unit>
scripts/tf.sh test     <unit> [-filter=tests/<file>] [-verbose]
```

`<unit>` is `modules/<name>` or `stacks/<name>`.

## Sequence per touched unit

1. `scripts/tf.sh fmt-fix <unit>` then `scripts/tf.sh fmt <unit>` (must exit 0).
2. `scripts/tf.sh validate <unit>` — catches malformed HCL before tests run.
3. `scripts/tf.sh test <unit>` — read the summary line
   (`Success! N passed, 0 failed.` / `Failure! N passed, M failed[, K skipped].`).
4. Record `passed`/`failed` from the final run for the report.

## Reading failures

| Message | Meaning | Fix |
|---|---|---|
| `Unknown condition value` | the assertion touches a computed value during plan | remove or replace the assertion; every later run in that file was skipped, so re-run after the fix |
| `Reference to undeclared resource` / `Unsupported attribute` | wrong resource name, attribute or block index | check `main.tf`; nested blocks are lists (`[0]`) |
| `Missing expected failure` | `expect_failures` listed a variable whose validation did not trigger | the invalid value is not invalid; pick one that violates the `condition` |
| `Error: Invalid value for variable` outside an `expect_failures` run | a value in `variables {}` violates a validation | fix the test value |
| `Missing required argument` / type errors from the provider schema | the test's `variables {}` does not satisfy the module | add the variable |
| `Failed to query available provider packages` / network errors | provider download problem, not your test | report as `not_run`, do not retry more than once |
| assertion `error_message` printed | the module does not do what the test expects | see below |

## When the module, not the test, is wrong

If an assertion is correct about the *intended* behaviour and the code
violates it (for example the change under review relaxes a security default),
do **not** weaken the assertion to make it pass and do **not** edit the
module. Remove that assertion from the committed file, run the suite again,
and record a finding (`tf-review-findings`) that states what the test would
have caught, with file and line. The reviewer decides.

## Retry budget

At most three fix-and-rerun cycles per unit. After that mark the unit
`skipped` with the last error in `reason`, keep other units moving, and
never commit a file whose suite is not green.

## Before committing

Run `scripts/tf.sh test <unit>` once more on the exact files you will commit,
then `git status` to confirm only `**/tests/*.tftest.hcl` changed.
