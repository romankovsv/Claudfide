#!/usr/bin/env bats
# Tests for scripts/tf.sh — the hermetic Terraform wrapper.

load helpers

setup() {
  make_fixture_repo
  install_fake_terraform
}

@test "prints usage without arguments" {
  run scripts/tf.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "rejects unknown commands" {
  run scripts/tf.sh plan modules/alpha
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "rejects paths that escape the repository" {
  run scripts/tf.sh fmt ../etc
  [ "$status" -eq 2 ]
  run scripts/tf.sh fmt /etc
  [ "$status" -eq 2 ]
  run scripts/tf.sh fmt modules/does-not-exist
  [ "$status" -eq 2 ]
}

@test "rejects directories without .tf files" {
  mkdir -p modules/empty
  run scripts/tf.sh fmt modules/empty
  [ "$status" -eq 2 ]
  [[ "$output" == *"no .tf files"* ]]
}

@test "allows only -filter, -verbose and -junit-xml for test" {
  run scripts/tf.sh test modules/alpha -destroy
  [ "$status" -eq 2 ]
  run scripts/tf.sh test modules/alpha -var=x=1
  [ "$status" -eq 2 ]
  run scripts/tf.sh test modules/alpha -filter=tests/main.tftest.hcl -verbose
  [ "$status" -eq 0 ]
  grep -q -- "-filter=tests/main.tftest.hcl -verbose" "$FAKE_TF_LOG"
}

@test "passes no extra arguments to fmt" {
  run scripts/tf.sh fmt modules/alpha -verbose
  [ "$status" -eq 2 ]
}

@test "runs terraform with a scrubbed environment" {
  export ANTHROPIC_API_KEY="sk-ant-secret" GITHUB_TOKEN="ghs_secret" AWS_SECRET_ACCESS_KEY="aws" ARBITRARY=1
  run scripts/tf.sh fmt modules/alpha
  [ "$status" -eq 0 ]
  ! grep -q "ANTHROPIC_API_KEY" "$FAKE_TF_LOG"
  ! grep -q "GITHUB_TOKEN" "$FAKE_TF_LOG"
  ! grep -q "AWS_SECRET_ACCESS_KEY" "$FAKE_TF_LOG"
  ! grep -q "ARBITRARY" "$FAKE_TF_LOG"
  grep -q "^TF_IN_AUTOMATION=1$" "$FAKE_TF_LOG"
  grep -q "^TF_INPUT=0$" "$FAKE_TF_LOG"
  grep -q "^CHECKPOINT_DISABLE=1$" "$FAKE_TF_LOG"
  grep -q "^TF_CLI_ARGS=-no-color$" "$FAKE_TF_LOG"
}

@test "forwards plugin cache and proxy settings only" {
  export TF_PLUGIN_CACHE_DIR="/tmp/cache" HTTPS_PROXY="http://proxy:1" SSL_CERT_FILE="/ca.pem" TF_LOG=DEBUG
  run scripts/tf.sh fmt modules/alpha
  [ "$status" -eq 0 ]
  grep -q "^TF_PLUGIN_CACHE_DIR=/tmp/cache$" "$FAKE_TF_LOG"
  grep -q "^HTTPS_PROXY=http://proxy:1$" "$FAKE_TF_LOG"
  grep -q "^SSL_CERT_FILE=/ca.pem$" "$FAKE_TF_LOG"
  ! grep -q "^TF_LOG=" "$FAKE_TF_LOG"
}

@test "init honours an existing lock file read-only" {
  run scripts/tf.sh init modules/alpha
  [ "$status" -eq 0 ]
  grep -q -- "init -backend=false -input=false -lockfile=readonly" "$FAKE_TF_LOG"
}

@test "init without a lock file does not pass readonly" {
  run scripts/tf.sh init modules/beta
  [ "$status" -eq 0 ]
  grep -q -- "init -backend=false -input=false$" "$FAKE_TF_LOG"
  ! grep -q -- "lockfile=readonly" "$FAKE_TF_LOG"
}

@test "test initialises first and uses -chdir" {
  run scripts/tf.sh test modules/alpha
  [ "$status" -eq 0 ]
  grep -q -- "-chdir=$FIXTURE/modules/alpha init" "$FAKE_TF_LOG"
  grep -q -- "-chdir=$FIXTURE/modules/alpha test" "$FAKE_TF_LOG"
}

@test "fmt check uses -check -diff -recursive and fmt-fix rewrites" {
  run scripts/tf.sh fmt modules/alpha
  grep -q -- "fmt -check -diff -recursive" "$FAKE_TF_LOG"
  run scripts/tf.sh fmt-fix modules/alpha
  grep -q -- "fmt -recursive$" "$FAKE_TF_LOG"
}

@test "propagates terraform's exit code" {
  install_fake_terraform "modules/alpha"
  run scripts/tf.sh test modules/alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failure!"* ]]
}
