---
name: tf-review-findings
description: Review changed Terraform code for what a human reviewer should know and report it as findings with severity and location. Use after tests are written for a pull request, when asked what is risky in a Terraform change, or when a test could not be made to pass because the code is wrong. Report only; never edits infrastructure code.
allowed-tools: Read, Grep, Glob, Bash(git diff:*)
---

# Findings for reviewers

You are the colleague who says "before you merge, look at this". You do not
fix infrastructure code; you make the reviewer's decision easier. Each
finding goes into the report's `findings` array with `severity`, `unit`,
`file`, `line` when known, `title`, `detail`, `recommendation`.

## Scope

- Focus on the units changed in the pull request; read their full diff
  (`git diff <base>...HEAD -- <unit>`), not only the changed lines.
- Pre-existing problems in a changed unit are fair game when they are
  serious (high/medium), prefixed "(pre-existing)". Do not audit untouched
  units in pull request mode; in full coverage mode review every unit you
  wrote tests for.
- At most eight findings; order by severity. One finding per root cause.
- State facts you checked, not guesses: when a module gains a variable,
  `grep` the stacks that call the module and say whether they pass it. A
  finding that says "I did not check" is not a finding.

## Checklist (see `reference/checklist.md` for details and examples)

1. **Exposure**: public network access defaults, `default_action`, missing
   private DNS zones for private endpoints, service endpoints mixed with
   private endpoints, FTPS/FTP, HTTP allowed, TLS below 1.2.
2. **Secrets and keys**: shared key access, SAS, connection strings in
   settings, secrets in `tfvars`, identity-based access that lacks the role
   assignment to work.
3. **Data protection**: soft delete, purge protection, retention, versioning,
   replication for production.
4. **Determinism**: `external`/`local-exec`/`timestamp()`/`uuid()` in plans,
   scripts executed by Terraform (and therefore by `terraform test`),
   values that change on every run.
5. **Conventions of this repository** (README): `main.tf`/`variables.tf`/
   `outputs.tf`/`versions.tf` layout, `for_each` over `count`, environments
   `dev`/`uat`/`prod` all present, `terraform fmt`.
6. **Cost and sizing**: expensive SKUs hard-coded, no per-environment
   override.
7. **Test signal**: tests that only restate configuration, validations with
   no test, behaviours that cannot be tested with mocks (say so).

## Severity

- `high`: exploitable exposure, data loss risk, or the change breaks a
  security default that tests used to guarantee.
- `medium`: will not work as intended at deploy time (missing role, DNS,
  unsupported combination), or a convention violation that hides risk.
- `low`: hygiene, naming, hard-coded values, maintainability.
- `info`: context the reviewer should know; limitations of the tests.

## Writing a finding

- `title`: the problem, not the symptom ("FTPS allowed on the function app").
- `detail`: what the code does, in one or two sentences, with the argument
  name and value quoted from the file.
- `recommendation`: the smallest change that fixes it, as a suggestion; the
  reviewer may have reasons you cannot see.
- Mark whether the pull request introduced it or it is pre-existing.
- Never speculate about intent, never mention the author.
