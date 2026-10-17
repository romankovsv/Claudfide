#!/usr/bin/env bats
# scripts/agent-gate.sh — when the agent job may run.

load helpers

setup() {
  make_fixture_repo
  chmod +x scripts/agent-gate.sh
}

gate() {
  run scripts/agent-gate.sh "$@"
}

@test "a human push on a ready pull request runs the agent" {
  gate --actor alice --triggering-actor alice --draft false --labels '[]' --head HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"run_agent=true"* ]]
  [[ "$output" == *"reason=pushed by alice"* ]]
}

@test "draft pull requests skip the agent" {
  gate --actor alice --triggering-actor alice --draft true --labels '[]' --head HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"run_agent=false"* ]]
  [[ "$output" == *"draft"* ]]
}

@test "the tf-tests:skip label skips the agent" {
  gate --actor alice --triggering-actor alice --draft false --labels '["documentation","tf-tests:skip"]' --head HEAD
  [[ "$output" == *"run_agent=false"* ]]
  [[ "$output" == *"tf-tests:skip"* ]]
}

@test "other labels do not skip the agent" {
  gate --actor alice --triggering-actor alice --draft false --labels '["documentation"]' --head HEAD
  [[ "$output" == *"run_agent=true"* ]]
}

@test "bot actors skip the agent (github-actions[bot] is what the agent's push looks like)" {
  gate --actor 'github-actions[bot]' --triggering-actor 'github-actions[bot]' --draft false --labels '[]' --head HEAD
  [[ "$output" == *"run_agent=false"* ]]
  [[ "$output" == *"bot actor (github-actions[bot])"* ]]
  gate --actor 'claude[bot]' --triggering-actor alice --draft false --labels '[]' --head HEAD
  [[ "$output" == *"run_agent=false"* ]]
}

@test "an approved run keeps the bot actor even when a human approved it" {
  gate --actor 'github-actions[bot]' --triggering-actor alice --draft false --labels '[]' --head HEAD
  [[ "$output" == *"run_agent=false"* ]]
}

@test "a head commit authored by claude[bot] skips the agent whoever triggered the run" {
  echo "run \"b\" { command = plan }" >> modules/alpha/tests/main.tftest.hcl
  git add -A
  git -c user.name='claude[bot]' -c user.email='41898282+claude[bot]@users.noreply.github.com' commit -qm "test(alpha): more" > /dev/null
  gate --actor alice --triggering-actor alice --draft false --labels '[]' --head HEAD
  [[ "$output" == *"run_agent=false"* ]]
  [[ "$output" == *"made by the agent"* ]]
}

@test "the agent's e-mail is enough even with a different author name" {
  echo "# x" >> modules/alpha/main.tf
  git add -A
  git -c user.name='Claude' -c user.email='claude[bot]@users.noreply.github.com' commit -qm "x" > /dev/null
  gate --actor alice --triggering-actor alice --draft false --labels '[]' --head HEAD
  [[ "$output" == *"run_agent=false"* ]]
}

@test "a human commit on top of the agent's commit runs the agent again" {
  echo "# agent" >> modules/alpha/tests/main.tftest.hcl
  git add -A
  git -c user.name='claude[bot]' -c user.email='41898282+claude[bot]@users.noreply.github.com' commit -qm "test(alpha): more" > /dev/null
  echo "# human" >> modules/alpha/main.tf
  fixture_commit "human change"
  gate --actor alice --triggering-actor alice --draft false --labels '[]' --head HEAD
  [[ "$output" == *"run_agent=true"* ]]
}

@test "rejects labels that are not a JSON array" {
  gate --actor alice --triggering-actor alice --draft false --labels 'tf-tests:skip' --head HEAD
  [ "$status" -eq 2 ]
}

@test "rejects unknown arguments" {
  gate --bogus 1
  [ "$status" -eq 2 ]
}
