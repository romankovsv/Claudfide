#!/usr/bin/env bats
# scripts/hooks/*.sh — the Claude Code hooks of the test agent.
# Each hook reads a JSON tool call on stdin; a deny/block is a JSON line on
# stdout with exit 0, silence is "let the normal permission flow decide".

load helpers

setup() {
  make_fixture_repo
  chmod +x scripts/hooks/*.sh
  export TF_TEST_AGENT=1
  export CLAUDE_PROJECT_DIR="$FIXTURE"
}

hook() {       # hook <script> <json>
  run bash -o pipefail -c 'printf "%s" "$2" | "scripts/hooks/$1"' _ "$1" "$2"
}

denied() { [[ "$output" == *'"permissionDecision":"deny"'* ]]; }
allowed() { [ "$status" -eq 0 ] && [ -z "$output" ]; }

# --- guard-write-path ------------------------------------------------------

@test "write: a module test file is allowed (relative and absolute)" {
  hook guard-write-path.sh '{"tool_name":"Write","tool_input":{"file_path":"modules/alpha/tests/main.tftest.hcl","content":"x"}}'
  allowed
  hook guard-write-path.sh "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FIXTURE/stacks/platform/tests/main.tftest.hcl\"}}"
  allowed
}

@test "write: the report file is allowed" {
  hook guard-write-path.sh '{"tool_name":"Write","tool_input":{"file_path":"agent-out/report.json","content":"{}"}}'
  allowed
}

@test "write: infrastructure code, scripts, workflows, agent and hooks are denied" {
  for p in modules/alpha/main.tf scripts/tf.sh .github/workflows/tf-test-agent.yml .claude/agents/tf-test-engineer.md .claude/settings.json scripts/hooks/guard-write-path.sh stacks/platform/envs/dev.tfvars; do
    hook guard-write-path.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$p\",\"content\":\"x\"}}"
    denied
    [[ "$output" == *"$p"* ]]
  done
}

@test "write: paths that escape the repository or use .. are denied" {
  hook guard-write-path.sh '{"tool_name":"Write","tool_input":{"file_path":"/tmp/elsewhere/modules/alpha/tests/x.tftest.hcl","content":"x"}}'
  denied
  hook guard-write-path.sh '{"tool_name":"Write","tool_input":{"file_path":"modules/alpha/tests/../main.tf","content":"x"}}'
  denied
  hook guard-write-path.sh '{"tool_name":"Write","tool_input":{"file_path":"modules/alpha/tests/deeper/x.tftest.hcl","content":"x"}}'
  denied
}

@test "write: a missing file_path is denied" {
  hook guard-write-path.sh '{"tool_name":"Write","tool_input":{}}'
  denied
}

@test "hooks are no-ops outside an agent session" {
  unset TF_TEST_AGENT
  hook guard-write-path.sh '{"tool_name":"Write","tool_input":{"file_path":"scripts/tf.sh","content":"x"}}'
  allowed
  hook guard-read-path.sh '{"tool_name":"Read","tool_input":{"file_path":".git/config"}}'
  allowed
  hook check-report-on-stop.sh '{"stop_hook_active":false}'
  allowed
}

# --- check-test-content ----------------------------------------------------

@test "content: a new test file without mock_provider is denied" {
  hook check-test-content.sh '{"tool_name":"Write","tool_input":{"file_path":"modules/alpha/tests/main.tftest.hcl","content":"run \"a\" {\n  command = plan\n}\n"}}'
  denied
  [[ "$output" == *"mock_provider"* ]]
}

@test "content: command = apply is denied on write and on edit" {
  hook check-test-content.sh '{"tool_name":"Write","tool_input":{"file_path":"modules/alpha/tests/main.tftest.hcl","content":"mock_provider \"azurerm\" {}\nrun \"a\" {\n  command = apply\n}\n"}}'
  denied
  hook check-test-content.sh '{"tool_name":"Edit","tool_input":{"file_path":"modules/alpha/tests/main.tftest.hcl","old_string":"command = plan","new_string":"  command = apply"}}'
  denied
  hook check-test-content.sh '{"tool_name":"MultiEdit","tool_input":{"file_path":"modules/alpha/tests/main.tftest.hcl","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"command = apply"}]}}'
  denied
}

@test "content: a real provider block is denied" {
  hook check-test-content.sh '{"tool_name":"Write","tool_input":{"file_path":"modules/alpha/tests/main.tftest.hcl","content":"provider \"azurerm\" {\n  features {}\n}\nmock_provider \"external\" {}\n"}}'
  denied
  [[ "$output" == *"real provider"* ]]
}

@test "content: a proper test file passes; non-test files are ignored" {
  hook check-test-content.sh '{"tool_name":"Write","tool_input":{"file_path":"modules/alpha/tests/main.tftest.hcl","content":"mock_provider \"azurerm\" {}\n\nrun \"a\" {\n  command = plan\n  assert {\n    condition = true\n    error_message = \"x\"\n  }\n}\n"}}'
  allowed
  hook check-test-content.sh '{"tool_name":"Edit","tool_input":{"file_path":"modules/alpha/tests/main.tftest.hcl","old_string":"x","new_string":"run \"b\" {\n  command = plan\n}"}}'
  allowed
  hook check-test-content.sh '{"tool_name":"Write","tool_input":{"file_path":"agent-out/report.json","content":"command = apply"}}'
  allowed
}

# --- guard-read-path -------------------------------------------------------

@test "read: .git, the runner temp dir and credential files are denied" {
  for p in .git/config "$FIXTURE/.git/HEAD" /home/runner/work/_temp/x /home/runner/.claude.json /home/runner/.netrc /home/runner/.git-credentials /home/runner/.ssh/id_ed25519; do
    hook guard-read-path.sh "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$p\"}}"
    denied
  done
  hook guard-read-path.sh '{"tool_name":"Grep","tool_input":{"pattern":"token","path":".git"}}'
  denied
  hook guard-read-path.sh '{"tool_name":"Glob","tool_input":{"pattern":".git/**/*","path":"."}}'
  denied
}

@test "read: repository content and the skills' reference files are allowed" {
  for p in modules/alpha/main.tf .claude/skills/tf-test-authoring/reference/patterns.md scripts/tf.sh .gitignore; do
    hook guard-read-path.sh "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$p\"}}"
    allowed
  done
  hook guard-read-path.sh '{"tool_name":"Grep","tool_input":{"pattern":"ftps_state","path":"modules"}}'
  allowed
  hook guard-read-path.sh '{"tool_name":"Glob","tool_input":{"pattern":"**/*.tftest.hcl"}}'
  allowed
}

# --- check-report-on-stop --------------------------------------------------

@test "stop: blocked when the report is missing, with instructions" {
  hook check-report-on-stop.sh '{"stop_hook_active":false}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"report.json is missing"* ]]
}

@test "stop: blocked when the report does not match the schema" {
  mkdir -p agent-out
  echo '{"decision":"maybe"}' > agent-out/report.json
  hook check-report-on-stop.sh '{"stop_hook_active":false}'
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"does not match"* ]]
}

@test "stop: allowed with a valid report, and always when already continuing" {
  mkdir -p agent-out
  cat > agent-out/report.json <<'EOF'
{"decision":"no_tests_needed","summary":"nothing to do","units":[],"tests_run":[],"findings":[],"skills_used":["tf-change-analysis"]}
EOF
  hook check-report-on-stop.sh '{"stop_hook_active":false}'
  allowed
  rm agent-out/report.json
  hook check-report-on-stop.sh '{"stop_hook_active":true}'
  allowed
}

# --- strip-git-credentials -------------------------------------------------

@test "session start: the token is removed from the origin url and auth headers are unset" {
  git remote add origin 'https://x-access-token:ghs_secret123@github.com/owner/repo.git'
  git config --local 'http.https://github.com/.extraheader' 'AUTHORIZATION: basic c2VjcmV0'
  inc="$FIXTURE/.git/extra.conf"
  git config --file "$inc" 'http.https://github.com/.extraheader' 'AUTHORIZATION: basic aW5jbHVkZWQ='
  git config --local --add include.path "$inc"
  git config --local credential.helper '/tmp/helper'
  hook strip-git-credentials.sh '{"cwd":"'"$FIXTURE"'"}'
  [ "$status" -eq 0 ]
  [ "$(git config --local --get remote.origin.url)" = "https://github.com/owner/repo.git" ]
  ! git config --local --get-regexp 'extraheader'
  ! git config --file "$inc" --get-regexp 'extraheader'
  ! git config --local --get credential.helper
  ! grep -rq 'ghs_secret123\|c2VjcmV0\|aW5jbHVkZWQ' .git/config "$inc"
}

@test "session start: ssh and plain https remotes are left alone" {
  git remote add origin 'git@github.com:owner/repo.git'
  hook strip-git-credentials.sh '{}'
  [ "$(git config --local --get remote.origin.url)" = "git@github.com:owner/repo.git" ]
  git remote set-url origin 'https://github.com/owner/repo.git'
  hook strip-git-credentials.sh '{}'
  [ "$(git config --local --get remote.origin.url)" = "https://github.com/owner/repo.git" ]
}
