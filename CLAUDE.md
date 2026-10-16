# Terraform Platform Base — working notes for Claude

Small Terraform repository for an Azure data platform: reusable modules under
`modules/`, one stack under `stacks/data-platform` with per-environment
`envs/*.tfvars`. There is no Azure subscription; nothing is ever deployed from
here. Tests use `terraform test` with mock providers.

## Conventions (from README)

- Each module/stack: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`.
- `for_each`, not `count`. Environments: `dev`, `uat`, `prod`.
- `terraform fmt -recursive` before committing.
- Tests live in `<unit>/tests/*.tftest.hcl`, mock the providers, use
  `command = plan`.

## Commands

- `scripts/tf.sh <init|fmt|fmt-fix|validate|test> <unit>` — the only way to
  run Terraform here (scrubbed environment, no backend).
- `make test` — bats suites for the scripts, then `terraform test` everywhere.
- `make verify` — what CI's verification job runs.
- `make agent` / `make agent-all` — run the test agent locally.

## The test agent

`.claude/agents/tf-test-engineer.md` plus the skills in `.claude/skills/`
write and verify tests for changed modules on pull requests
(`.github/workflows/tf-test-agent.yml`). The agent only writes
`**/tests/*.tftest.hcl`; infrastructure changes are for humans. See
`SOLUTION.md` for the design.
