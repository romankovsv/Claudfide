#!/usr/bin/env bats
# Tests for scripts/verify.sh — the independent verification runner.

load helpers

setup() {
  make_fixture_repo
}

@test "runs fmt, validate and test for every unit and passes" {
  install_fake_terraform
  run scripts/verify.sh --out out
  [ "$status" -eq 0 ]
  [[ "$output" == *"all checks passed"* ]]
  jq -e '.ok == true' out/summary.json
  jq -e '[.results[] | select(.unit == "modules/alpha" and .step == "test")][0].status == "pass"' out/summary.json
  jq -e '[.results[] | select(.unit == "modules/beta" and .step == "test")][0].status == "skipped"' out/summary.json
  [ -f out/modules_alpha.xml ]
  [ -f out/modules_alpha.log ]
  grep -q '| modules/alpha | ✅ | ✅ | ✅ Success! 2 passed, 0 failed. |' out/summary.md
}

@test "fails and reports when a test suite fails" {
  install_fake_terraform "modules/alpha"
  run scripts/verify.sh --out out
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  jq -e '.ok == false' out/summary.json
  grep -q '| modules/alpha | ✅ | ✅ | ❌ Failure! 1 passed, 1 failed. |' out/summary.md
}

@test "fails when formatting is off" {
  install_fake_terraform "" "modules/beta"
  run scripts/verify.sh --out out
  [ "$status" -eq 1 ]
  jq -e '[.results[] | select(.unit == "modules/beta" and .step == "fmt")][0].status == "fail"' out/summary.json
}

@test "relative --out works with the chdir-based wrapper (junit path regression)" {
  install_fake_terraform
  run scripts/verify.sh --out rel-out --units "modules/alpha"
  [ "$status" -eq 0 ]
  [ -f rel-out/modules_alpha.xml ]
  grep -q -- "-junit-xml=$FIXTURE/rel-out/modules_alpha.xml" "$FAKE_TF_LOG"
}

@test "--units restricts the run" {
  install_fake_terraform
  run scripts/verify.sh --out out --units "modules/beta"
  [ "$status" -eq 0 ]
  jq -e '[.results[].unit] | unique == ["modules/beta"]' out/summary.json
}

@test "never leaks secrets into terraform" {
  install_fake_terraform
  export ANTHROPIC_API_KEY="sk-ant-secret"
  run scripts/verify.sh --out out
  [ "$status" -eq 0 ]
  ! grep -q "sk-ant-secret" "$FAKE_TF_LOG"
}
