#!/usr/bin/env bats
# Tests for scripts/guard-agent-diff.sh — the scope guard for agent commits.

load helpers

setup() {
  make_fixture_repo
  BEFORE="$(git rev-parse HEAD)"
}

@test "passes when nothing was committed" {
  run scripts/guard-agent-diff.sh "$BEFORE" "$BEFORE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no commits"* ]]
}

@test "passes when only test files changed" {
  echo 'run "c" { command = plan }' > modules/alpha/tests/extra.tftest.hcl
  mkdir -p modules/beta/tests
  echo 'run "b" { command = plan }' > modules/beta/tests/main.tftest.hcl
  fixture_commit "agent: add tests"
  run scripts/guard-agent-diff.sh "$BEFORE" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "fails when infrastructure code changed" {
  echo '# nope' >> modules/alpha/main.tf
  echo 'run "c" { command = plan }' > modules/alpha/tests/extra.tftest.hcl
  fixture_commit "agent: sneaky"
  run scripts/guard-agent-diff.sh "$BEFORE" "$(git rev-parse HEAD)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION"* ]]
  [[ "$output" == *"modules/alpha/main.tf"* ]]
}

@test "fails when files outside modules/stacks changed" {
  mkdir -p .github/workflows .claude/agents
  echo 'x' > .github/workflows/evil.yml
  echo 'x' > .claude/agents/tf-test-engineer.md
  fixture_commit "agent: touches config"
  run scripts/guard-agent-diff.sh "$BEFORE" "$(git rev-parse HEAD)"
  [ "$status" -eq 1 ]
  [[ "$output" == *".github/workflows/evil.yml"* ]]
  [[ "$output" == *".claude/agents/tf-test-engineer.md"* ]]
}

@test "fails when a test file sits outside a tests/ directory" {
  echo 'run "x" { command = plan }' > modules/alpha/main.tftest.hcl
  fixture_commit "agent: wrong place"
  run scripts/guard-agent-diff.sh "$BEFORE" "$(git rev-parse HEAD)"
  [ "$status" -eq 1 ]
}

@test "fails when history was rewritten" {
  echo 'run "c" { command = plan }' > modules/alpha/tests/extra.tftest.hcl
  fixture_commit "agent: add tests"
  AFTER="$(git rev-parse HEAD)"
  git reset -q --hard "$BEFORE"
  echo '# rewrite' >> README.md
  fixture_commit "someone rewrote"
  run scripts/guard-agent-diff.sh "$AFTER" "$(git rev-parse HEAD)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rewritten"* ]]
}

@test "errors on unknown revisions" {
  run scripts/guard-agent-diff.sh deadbeef "$BEFORE"
  [ "$status" -eq 2 ]
}
