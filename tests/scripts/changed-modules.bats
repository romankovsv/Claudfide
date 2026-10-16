#!/usr/bin/env bats
# Tests for scripts/changed-modules.sh — deterministic change analysis.

load helpers

setup() {
  make_fixture_repo
}

@test "--all lists every unit with its test status" {
  run scripts/changed-modules.sh --all
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "all"'
  echo "$output" | jq -e '[.units[].path] == ["modules/alpha", "modules/beta", "stacks/platform"]'
  echo "$output" | jq -e '.units[] | select(.path == "modules/alpha") | .has_tests == true and .kind == "module"'
  echo "$output" | jq -e '.units[] | select(.path == "modules/beta") | .has_tests == false'
  echo "$output" | jq -e '.units[] | select(.path == "stacks/platform") | .kind == "stack"'
}

@test "diff mode classifies changed files per unit" {
  git checkout -q -b feature
  echo '# change' >> modules/alpha/main.tf
  echo 'variable "size" { type = number }' >> modules/alpha/variables.tf
  echo 'run "b" { command = plan }' > modules/beta/tests.tftest.hcl
  mkdir -p modules/beta/tests && mv modules/beta/tests.tftest.hcl modules/beta/tests/main.tftest.hcl
  echo '# doc' >> README.md
  fixture_commit "feature work"

  run scripts/changed-modules.sh main HEAD
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "diff"'
  echo "$output" | jq -e '.other_files == ["README.md"]'
  echo "$output" | jq -e '.units[] | select(.path == "modules/alpha") | .tf_changed and (.tests_changed | not) and (.change_kinds == ["code", "variables"])'
  echo "$output" | jq -e '.units[] | select(.path == "modules/beta") | (.tf_changed | not) and .tests_changed and .has_tests'
  echo "$output" | jq -e '.units[] | select(.path == "modules/beta") | .files[0].status == "A" and .files[0].category == "test"'
}

@test "diff mode uses the merge base, not the base tip" {
  git checkout -q -b feature
  echo '# feature' >> modules/beta/main.tf
  fixture_commit "feature"
  git checkout -q main
  echo '# main moved on' >> modules/alpha/main.tf
  fixture_commit "main"
  git checkout -q feature

  run scripts/changed-modules.sh main HEAD
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.units[].path] == ["modules/beta"]'
}

@test "deleted units are reported as deleted" {
  git checkout -q -b feature
  git rm -rq modules/beta
  fixture_commit "remove beta"
  run scripts/changed-modules.sh main HEAD
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.units[] | select(.path == "modules/beta") | .deleted == true and .files[0].status == "D"'
}

@test "scripts, lock files and tfvars get their own categories" {
  git checkout -q -b feature
  mkdir -p modules/beta/scripts stacks/platform/envs
  echo 'echo hi' > modules/beta/scripts/x.sh
  echo '# lock' > modules/beta/.terraform.lock.hcl
  echo 'x = 1' > stacks/platform/envs/dev.tfvars
  fixture_commit "misc"
  run scripts/changed-modules.sh main HEAD
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.units[] | select(.path == "modules/beta") | (.change_kinds == ["lock", "script"])'
  echo "$output" | jq -e '.units[] | select(.path == "stacks/platform") | (.change_kinds == ["tfvars"]) and .tf_changed'
}

@test "fails cleanly on an unknown ref" {
  run scripts/changed-modules.sh nope HEAD
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown base ref"* ]]
}
