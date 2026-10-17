# Terraform test agent — solution notes

A custom [Claude Code](https://code.claude.com) agent with four reusable skills
writes and verifies `terraform test` suites for this repository. It runs on
every pull request that touches Terraform code, commits only green test files
to the PR branch, and tells reviewers what it found. Nothing here needs Azure
credentials; every test uses mock providers and `command = plan`.

Example pull request: **[#5](https://github.com/romankovsv/claudfide-agent-tf/pull/5)**
— a real change to `modules/function-app` (FTPS made configurable, disabled by
default), handled end to end by the agent in CI. Coverage for all nine units was
produced by the same agent in a local run: **[#2](https://github.com/romankovsv/claudfide-agent-tf/pull/2)**.

## 1. Main decisions and what they cost

| Decision | Why | What was given up |
|---|---|---|
| **Claude Code as the agent runtime** (`anthropics/claude-code-action` in CI, the `claude` CLI locally) | Its primitives map 1:1 onto the task: `.claude/agents/*.md` is a custom agent, `.claude/skills/*/SKILL.md` are reusable skills, `claude --agent <name>` runs the same definition in CI and on a laptop. No bespoke agent loop to defend. | Vendor lock-in; an API key with a balance in CI; the action's own prompt/system behaviour is a dependency (see "structured output" below). |
| **The agent may only write `**/tests/*.tftest.hcl`**, enforced by a CI job (`guard`), not just by instructions | Changing infrastructure code is a decision for people, so the agent reports and never edits it. Instructions are not enforcement; a diff check is. | The agent cannot fix a module even when the fix is obvious — it files a finding instead. |
| **Independent `verify` job without LLM or secrets** | The agent's "all tests pass" is self-reported. Re-running `fmt`/`validate`/`terraform test` on the branch tip is the oracle; it is also what runs when a human pushes. | ~25 s of extra CI per run; tests run twice. |
| **A single Terraform entry point, `scripts/tf.sh`** (`env -i`, fixed flags, read-only lock files, four allowed subcommands) | `terraform test` executes repository code: `modules/function-app` runs `scripts/build-info.sh` through `data "external"`. A PR can change that script, so Terraform must never inherit the job's secrets. The wrapper is also the only Bash the agent may run, which keeps the allow-list short and auditable. | No `terraform plan/apply` from the agent, by design; developers who want raw `terraform` run it outside the wrapper. |
| **Deterministic pre-analysis** (`scripts/changed-modules.sh` → JSON) fed to the agent | "Which units changed and how" is a git question, not an LLM question. Fewer tokens, no hallucinated file lists, testable with bats. | The categorisation is by path and file name; the agent still reads the real diff for the "what" part. |
| **Report as a file + schema validation** instead of the action's `--json-schema` structured output | The structured-output path worked locally but not inside the action (Claude ended with text; the action failed). A file written with the ordinary `Write` tool and validated by `scripts/validate-report.py` is boring and reliable. | Schema enforcement happens after the fact, not at generation time; an invalid report fails the job rather than being repaired. |
| **The PR comment is assembled by scripts, not by the agent** (`render-report.sh`, `post-comment.sh`, two sticky markers) | Results must reach the PR even when the agent times out, exceeds its budget or is rejected by the action. The comment also carries the verification table and the guard output, which the agent cannot vouch for. | The agent cannot format its own comment; findings follow a fixed template. |
| **`pull_request`, not `pull_request_target`** | Fork PRs never see secrets and never run the agent. The action also rejects bot and non-write actors. | External contributors get no agent help; a maintainer re-pushes their branch if they want it. |
| **Queued, not cancelled, runs per PR** (`concurrency.cancel-in-progress: false`) | The agent's push re-triggers the workflow; cancelling the first run would lose its report job. | Rapid pushes queue up; each queued run costs an agent invocation unless the `gate` job skips the agent (bot actor, or a head commit the agent made itself). |
| **A deterministic `gate` job decides whether the agent runs** (`scripts/agent-gate.sh`: draft, label, bot actor, head-commit author) | The agent must never run on its own commit. GitHub attributes the agent's push to `github-actions[bot]`, not `claude[bot]`, and an approved or re-run workflow carries yet another actor, so an actor check alone is not enough; the author of the head commit is. Found the hard way (section 7). | One more 5-second job per run. |
| **Sonnet with hard caps** (`--max-turns 120`, `--max-budget-usd 6`, job timeout 30 min) | Predictable cost; observed runs: $0.3–0.6, 1–3 minutes. | A very large PR may hit the cap; the agent is told to stop cleanly and report what it did not finish. |

## 2. How to run it

**Prerequisites**

- GitHub repository with Actions enabled; the [Claude GitHub App](https://github.com/apps/claude) installed on it (the action authenticates as the app; the agent's commits are authored by `claude[bot]`).
- Repository secret `ANTHROPIC_API_KEY` from an Anthropic Console organisation **with credits**; the workflow's preflight step fails fast with the API's own error when the key cannot authenticate or has no balance (see also "Billing path of the GitHub Action" in section 7).
- Branch protection on `main`: require a pull request; the agent never pushes to `main`.
- Locally: Terraform ≥ 1.9 (CI pins 1.16.6), `jq`, `bats` (`npm i -g bats`), `shellcheck`, `actionlint`, and the Claude Code CLI signed in.

**In CI** — nothing to start by hand. Open a pull request that changes `modules/**` or `stacks/**`:

1. `gate` (no secrets, 5 s): `scripts/agent-gate.sh` decides whether the agent may run — not on drafts, not with the label `tf-tests:skip`, not for a bot actor, and never when the head commit was authored by the agent.
2. `agent` (the only job with the API key): installs Terraform and bubblewrap, pre-downloads providers, checks the key with one minimal API call, installs Claude Code behind a small launcher (section 7), builds the prompt (`scripts/agent-prompt.sh`), runs `claude-code-action` with `--agent tf-test-engineer` and the tool allow-list, validates `agent-out/report.json`, summarises the transcript.
3. `verify` (no secrets): `scripts/verify.sh` on the branch tip — `fmt`, `validate`, `terraform test` for all nine units, JUnit + logs as artifacts, failures as annotations.
4. `guard`: `scripts/guard-agent-diff.sh <PR head before> <branch tip>` — only `**/tests/*.tftest.hcl` may differ.
5. `report`: one sticky comment with the agent's report, the verification table, the guard result and, if the agent failed, what it did.

The agent's own push re-triggers the workflow; the gate skips the agent job on that commit, so the second run only verifies it and writes a second sticky comment (marker `tf-test-agent-verify`) instead of overwriting the agent's report. GitHub treats a push by a GitHub App like one from an outside contributor and may hold that second run until a maintainer clicks "Approve and run workflows" (this repository keeps GitHub's default approval policy); approving it is safe because of the gate — the run only verifies.

**Locally** — the same agent, same skills, same allow-list:

```sh
make test          # bats suites for the scripts + terraform test everywhere
make verify        # exactly what CI's verify job runs
make agent         # analyse the current branch against main and write/update tests
make agent-all     # full coverage pass over every unit (how #2 was produced)
scripts/run-agent-local.sh --interactive   # watch and steer the agent
```

The local runner writes `agent-out/report.json` and `agent-out/transcript.md`; it commits but never pushes. Claude Code ignores `.claude/settings.json` until you accept the workspace trust dialog once (`claude` interactively in the repo); the explicit `--allowedTools` apply regardless.

## 3. Where things are and how they are used

```
.claude/agents/tf-test-engineer.md    the custom agent: scope, procedure, rules
.claude/skills/tf-change-analysis/    what a change means for tests (decision table)
.claude/skills/tf-test-authoring/     house conventions for .tftest.hcl + reference/patterns.md, mock-limits.md
.claude/skills/tf-test-verify/        the only Terraform commands, failure triage, retry budget
.claude/skills/tf-review-findings/    reviewer checklist + reference/checklist.md, severity scale
.claude/settings.json                 allow-list (wrapper + git) and deny-list (raw terraform, network, history rewrites)
CLAUDE.md                             repository notes every session reads
.github/workflows/tf-test-agent.yml   gate → agent → verify / guard → report
.github/workflows/ci.yml              shellcheck, bats, actionlint, terraform verification on every PR
scripts/                              tf.sh, changed-modules.sh, agent-gate.sh, agent-prompt.sh, verify.sh,
                                      guard-agent-diff.sh, render-report.sh, post-comment.sh, transcript-summary.sh,
                                      validate-report.py, report.schema.json, run-agent-local.sh
tests/scripts/*.bats                  63 tests for the scripts (fake terraform / fake gh)
```

**Execution.** The workflow runs Claude Code with `--agent tf-test-engineer`, so the main session *is* the custom agent: its markdown body is the system prompt, its `skills:` list is preloaded into context, its `disallowedTools` removes `WebFetch`/`WebSearch`/`Agent`. The prompt from `scripts/agent-prompt.sh` carries only context — repository, PR number, base/head, the change JSON — and the procedure comes from the agent file, which walks the four skills in order:

1. `tf-change-analysis` — turns the JSON plus the real diff into a per-unit decision (`created` / `updated` / `unchanged` / `skipped`) using a decision table (tests-only, format-only, lock-only and script-only changes need no tests).
2. `tf-test-authoring` — conventions distilled from the three suites the base repo shipped with, the `override_data` pattern for the `external` data source, and an explicit list of what cannot be asserted with mocks (computed values; one such assertion errors *and skips the rest of the file*).
3. `tf-test-verify` — `scripts/tf.sh fmt-fix → fmt → validate → test`, a triage table for the failure messages, three fix-and-rerun cycles per unit, and the rule that a failing test is never committed: if the module is wrong, the assertion is dropped and becomes a finding.
4. `tf-review-findings` — a checklist (exposure, keys, data protection, determinism, README conventions, cost, test signal) with a severity scale; report only.

The action restores `.claude/`, `CLAUDE.md` and `.mcp.json` from the **base** branch before Claude starts, so a pull request cannot rewrite the agent's instructions for its own run; the `gate` and `guard` jobs check out their scripts from the base branch for the same reason (the agent could otherwise edit `guard-agent-diff.sh` in the very commit the guard inspects). The repository's `.claude/settings.json` deny-list applies on top of the workflow's allow-list.

Skills are plain markdown with frontmatter and are usable outside this agent: `/tf-test-authoring` in any Claude Code session in this repo loads the same conventions.

## 4. Example run

### Full coverage pass (local, produced PR #2)

`make agent-all` on the base repository: 41 turns, 2 min 27 s, $0.56.

- Decisions: `created` for `data-factory`, `databricks-workspace`, `function-app`, `log-analytics-workspace`, `private-endpoint`, `stacks/data-platform`; `updated` for `key-vault` and `storage-account` (security defaults that were not asserted); `unchanged` for `network`.
- Skills used: all four, in order.
- Tests: 33 runs across 9 units, all passing in the agent's run and in `make verify`.
- The agent wrote an assertion "FTPS is disabled" for the function app, saw it fail against the code (`ftps_state = "AllAllowed"`), **left it out of the commit** and raised it as a `high` finding. Eight findings in total, among them: private endpoints without private DNS zones, no `uat` tfvars, public-access defaults differing between modules and stack, the `external` data source running a script during plan.
- Five Bash calls were denied by the allow-list (compound `cat`/`ls`/`mkdir` commands); the agent switched to `Read`/`Write`. The stack test overrides the data source inside the child module (`module.function_app.data.external.build_info`) — the agent found that on its own.

### Pull request run (CI, PR #5)

The change: `modules/function-app` gets a `ftps_state` variable with a `validation` block and the default `Disabled`, replacing the hard-coded `AllAllowed`. One human commit (`10aac77`); nothing else.

[Workflow run 38966166147](https://github.com/romankovsv/claudfide-agent-tf/actions/runs/38966166147) — `agent` 81 s end to end (Terraform, providers, sandbox and Claude Code set-up included; the Claude Code step itself 36 s), `verify` 25 s, `guard` 6 s, `report` 6 s; the whole workflow under two minutes.

- `tf-change-analysis`: one unit, `modules/function-app`, change kind `defaults` → `updated` ("new variable with a validation and a changed default needs default, wiring and invalid-value assertions").
- `tf-test-authoring` + `tf-test-verify`: three runs added to the existing suite — `ftps_is_disabled_by_default`, `ftps_state_is_forwarded_to_the_app`, `rejects_unknown_ftps_state` (`expect_failures`); 7/7 passing through `scripts/tf.sh`.
- Commit `432b2d1` by `claude[bot]`, `test(function-app): cover ftps_state default, forwarding and validation`, pushed to the PR branch. `guard`: one file changed, `modules/function-app/tests/main.tftest.hcl` — OK. `verify`: all nine units green on the branch tip, 36 runs.
- `tf-review-findings`: one `info` finding — the default moved from `AllAllowed` to `Disabled` and `stacks/data-platform` does not set the variable, so every environment changes on the next apply; suggestion to set `FtpsOnly` explicitly if any pipeline publishes over FTPS. Stated as checked (the agent grepped the stack), not guessed.
- Limitations stated by the agent: plan-only mock tests show the value reaches `site_config` and the validation fires, not that Azure accepts it; the stack was not run.
- Cost: the identical change run locally (`make agent`) took 20 turns, 66 s and $0.18; the CI run used the same model and tool budget.

What the sticky comment looks like is in the PR itself. An [earlier run](https://github.com/romankovsv/claudfide-agent-tf/actions/runs/38965702614) on the same PR shows the fail-safe path: the sandbox tooling on the runner was incomplete, the agent reported `blocked`, committed nothing, and the comment still carried the independent verification of the untouched branch.

## 5. What the tests can and cannot show

`terraform test` with `mock_provider` and `command = plan` never contacts Azure.

They **can** show: the module turns inputs into the intended arguments (names, flags, retention, SKUs, identity, network defaults); cardinality and keys of `for_each` resources; conditional/`dynamic` blocks on and off; `validation` blocks reject what they should; a data source's output is wired where it should be; the configuration is valid against the provider schema.

They **cannot** show: anything the Azure API decides (SKU availability, global name uniqueness, quota, policy, RBAC propagation); computed values (IDs, principal IDs, URLs) or outputs built from them — unknown during plan, and `apply` with mocks fails because azurerm validates resource-ID arguments client-side; runtime behaviour (a function app reaching its storage through `Deny` rules, DNS resolving a private endpoint, a linked service authenticating); drift or cost. Green tests mean "the module encodes these intentions", not "this deploys". That is why findings exist: the things the tests cannot cover go to the reviewer.

## 6. Assumptions

- Pull requests come from branches in the same repository (fork PRs get no secrets and no agent).
- The Claude GitHub App is installed and the API key has credits; one agent run costs well under a dollar.
- Reviewers read the sticky comment and the findings; the agent's commit is reviewed like any other commit.
- `scripts/`, `.github/` and `.claude/` are maintained by humans; the agent cannot change them (guard) and does not get their instructions from the PR (base-branch restore).
- Terraform version drift between local and CI is acceptable (CI pins 1.16.6, lock files pin providers).

## 7. Limitations

- The agent reads the diff and the files; it does not run `plan` against real infrastructure and cannot judge intent. Findings are heuristics from a checklist.
- Mock plan tests cannot detect provider-side or runtime failures (section 5).
- One agent invocation per push; large PRs may exceed the turn/budget caps and end with `blocked` or partial `skipped` units.
- The action's structured output (`--json-schema`) was unreliable in CI, so report validity is checked after the run; a malformed report fails the job instead of being repaired.
- Fork pull requests are not handled.
- Raw CI logs are needed for deep debugging; the transcript summary omits tool outputs on purpose.
- Lock files were added for the five modules that lacked them (`terraform providers lock`, linux + darwin); the three original lock files were left as shipped.
- Commits by the agent are not signed (`use_commit_signing` is off); GitHub shows them as unverified.

### Billing path of the GitHub Action

The first CI runs failed with HTTP 400 `Credit balance is too low` from the Messages API although the same key had credits and the very same request succeeded from `curl` and from `claude -p` on a laptop. Narrowed down with throw-away workflow steps: Claude Code tags every request with a billing header that names its entrypoint, and it reports `claude-code-github-action` whenever `CLAUDE_CODE_ENTRYPOINT` or `CLAUDE_CODE_ACTION` is set (the action sets both). Requests with that entrypoint were rejected for this organisation; requests with any other entrypoint went through. The workflow therefore (1) runs a preflight call with the agent's model so a key or balance problem fails in one second with the API's own message, and (2) starts Claude Code through a two-line launcher that drops those two variables (`path_to_claude_code_executable`). The launcher changes nothing about what the agent can do; it only changes how the request is labelled. Both steps are marked as removable once the API accepts the action's entrypoint for the organisation. Debugging this is also where the "the action refuses to run when the workflow file differs from the default branch" rule bit: every experiment had to be merged first.

### Loop prevention, second attempt

The first version skipped the agent job when `github.actor == 'claude[bot]'`. It never matched: GitHub attributes the push made by the Claude GitHub App to `github-actions[bot]`, and the run was only held back because GitHub asks a maintainer to approve workflow runs triggered by an app. Approving that run made the agent job start on its own commit; the action rejected the bot actor within seconds, the job failed, and the report job overwrote the agent's sticky comment with a failure notice. The fix is the `gate` job: a bot actor of any name skips the agent, and so does a head commit authored by `claude[bot]`, whoever triggered the run. The script is covered by eleven bats tests, including "approved by a human, actor still a bot" and "human commit on top of the agent's commit runs the agent again". Its first version checked out the gate script from the PR head commit, which on a branch cut before the script existed meant "command not found", empty outputs and a silently skipped agent; `gate` and `guard` now take their scripts from the base branch and the gate step uses `pipefail`, so a missing script fails the job instead of hiding.

## 8. With many more modules, teams or repositories

- **Workflow as a reusable workflow** (`workflow_call`) in a platform repository, called by each Terraform repo with its own secret; the agent and skills shipped as a Claude Code **plugin** (`plugin_marketplaces`/`plugins` inputs) so one definition is versioned and rolled out centrally instead of copied.
- **Scope per PR, not per repo**: `changed-modules.sh` already limits the agent to touched units; add a matrix job per unit for very large monorepos, and `CODEOWNERS` so the sticky comment pings the owning team.
- **Shared conventions, local overrides**: the authoring skill carries house rules; per-repo `CLAUDE.md` adds local naming. A central checklist in the findings skill keeps review quality consistent across teams.
- **Cost and quota**: per-run budget caps plus an organisation-level ceiling; cache providers across jobs (already done per repo); run the agent only on `ready_for_review` for noisy branches.
- **Governance**: required checks (`verify`, `guard`) on the default branch; `require conversation resolution` so every finding is acknowledged; a dashboard from the JSON reports (decision, findings per severity, cost) exported as artifacts.
- **Multiple providers/clouds**: the skills are Azure-flavoured in the checklist only; the mechanics (mock providers, plan assertions, wrapper, guard) are provider-agnostic.

## 9. What would change for production

- Authentication via **workload identity federation** instead of a stored API key (`anthropic_federation_rule_id` + `id-token: write`), or Bedrock/Vertex/Foundry with OIDC.
- **Signed commits** from the agent (`use_commit_signing`), and required status checks `verify` + `guard` on `main` (not set here only because check names appear after the first run).
- **Inline review comments** for findings (`mcp__github_inline_comment__create_inline_comment`) in addition to the sticky comment, and `require conversation resolution` so humans close each one.
- **Observability**: export every report JSON and transcript summary to a store; alert on `blocked` decisions and budget hits; track findings that recur across PRs.
- **Evaluation**: a small corpus of synthetic PRs (new variable with validation, removed resource, formatting-only, malicious instruction in a comment) run nightly against the agent, asserting the decision and the guard outcome — the bats suites already cover the deterministic half.
- **Hermetic providers**: a filesystem mirror for provider packages so the agent job can run with no outbound network at all.
- **Policy as code** (OPA/Sentinel or `tflint`/`checkov`) as another deterministic job; the agent's findings complement rather than replace it.
