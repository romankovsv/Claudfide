#!/usr/bin/env bats
# Tests for scripts/render-report.sh, scripts/post-comment.sh and
# scripts/agent-prompt.sh — the deterministic reporting path.

load helpers

setup() {
  make_fixture_repo
  cat > report.json <<'EOF'
{
  "decision": "tests_updated",
  "summary": "The change added a variable; the test now covers its validation.",
  "units": [
    {"path": "modules/alpha", "change_kind": "variables", "action": "updated",
     "test_files": ["modules/alpha/tests/main.tftest.hcl"], "reason": "new validation block"}
  ],
  "tests_run": [{"unit": "modules/alpha", "result": "pass", "passed": 4, "failed": 0}],
  "findings": [
    {"severity": "high", "unit": "modules/alpha", "file": "modules/alpha/main.tf", "line": 12,
     "title": "FTPS is wide open", "detail": "ftps_state is AllAllowed.", "recommendation": "Set Disabled."}
  ],
  "skills_used": ["tf-change-analysis", "tf-test-authoring"],
  "limitations": "Mock provider only."
}
EOF
  printf '| Unit | fmt | validate | test |\n|---|---|---|---|\n| modules/alpha | ✅ | ✅ | ✅ Success! 4 passed, 0 failed. |\n' > verify.md
}

@test "report json validates against the schema" {
  python3 - <<'EOF'
import json, sys
schema = json.load(open("scripts/report.schema.json"))
report = json.load(open("report.json"))
# minimal structural check without external deps: required keys and enums
for key in schema["required"]:
    assert key in report, key
assert report["decision"] in schema["properties"]["decision"]["enum"]
for f in report["findings"]:
    assert f["severity"] in schema["properties"]["findings"]["items"]["properties"]["severity"]["enum"]
EOF
}

@test "renders a complete report with marker, decision, findings and verification" {
  run scripts/render-report.sh --report report.json --verify verify.md --status success --run-url https://x/run/1 --head 0123456789abcdef
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "<!-- tf-test-agent-report -->" ]
  [[ "$output" == *"tests updated"* ]]
  [[ "$output" == *"| \`modules/alpha\` | variables | updated | new validation block |"* ]]
  [[ "$output" == *"🔴 high"* ]]
  [[ "$output" == *"FTPS is wide open"* ]]
  [[ "$output" == *"modules/alpha/main.tf:12"* ]]
  [[ "$output" == *"Independent verification"* ]]
  [[ "$output" == *"4 passed, 0 failed"* ]]
  [[ "$output" == *"0123456"* ]]
  [[ "$output" == *"https://x/run/1"* ]]
  [[ "$output" == *"tf-change-analysis"* ]]
}

@test "renders a fallback when the agent failed" {
  run scripts/render-report.sh --status failure --verify verify.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not complete"* ]]
  [[ "$output" == *"Independent verification"* ]]
}

@test "renders a fallback when the agent was skipped and no verification exists" {
  run scripts/render-report.sh --status skipped
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not run"* ]]
  [[ "$output" == *"not available"* ]]
}

@test "shows the gate's reason when the agent was skipped" {
  run scripts/render-report.sh --status skipped --reason "head commit abc1234 was made by the agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not run for this event: head commit abc1234 was made by the agent."* ]]
  [[ "$output" == *"verification only"* ]]
}

@test "ignores a malformed report file" {
  echo '{"nope": true}' > bad.json
  run scripts/render-report.sh --report bad.json --status success
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not return a readable report"* ]]
}

@test "includes the guard output when given" {
  echo "guard: OK — only test files were touched" > guard.txt
  run scripts/render-report.sh --report report.json --guard guard.txt --status success
  [[ "$output" == *"Scope guard"* ]]
  [[ "$output" == *"only test files were touched"* ]]
}

@test "post-comment creates a comment when none carries the marker" {
  install_fake_gh "[]"
  scripts/render-report.sh --report report.json --status success > body.md
  run scripts/post-comment.sh owner/repo 7 body.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"created comment"* ]]
  grep -q "POST repos/owner/repo/issues/7/comments" "$FAKE_GH_LOG"
}

@test "post-comment updates the existing marked comment" {
  install_fake_gh '[{"id": 1, "body": "unrelated"}, {"id": 42, "body": "<!-- tf-test-agent-report -->\nold"}]'
  scripts/render-report.sh --report report.json --status success > body.md
  run scripts/post-comment.sh owner/repo 7 body.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated comment 42"* ]]
  grep -q "PATCH repos/owner/repo/issues/comments/42" "$FAKE_GH_LOG"
}

@test "post-comment refuses a body without marker" {
  echo "no marker" > body.md
  run scripts/post-comment.sh owner/repo 7 body.md
  [ "$status" -eq 2 ]
}

@test "agent-prompt pr mode embeds the change analysis and CI footer" {
  git checkout -q -b feature
  echo '# x' >> modules/alpha/main.tf
  fixture_commit "change"
  run scripts/agent-prompt.sh --mode pr --base main --head HEAD --pr 5 --repo owner/repo --ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode: pr"* ]]
  [[ "$output" == *"Pull request: 5"* ]]
  [[ "$output" == *'"path": "modules/alpha"'* ]]
  [[ "$output" == *"Do not push: the workflow pushes"* ]]
}

@test "agent-prompt full mode lists all units and local footer" {
  run scripts/agent-prompt.sh --mode full
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode: full"* ]]
  [[ "$output" == *'"path": "modules/beta"'* ]]
  [[ "$output" == *"do NOT push"* ]]
}

@test "post-status sets a commit status on the given sha with all fields" {
  install_fake_gh "[]"
  run scripts/post-status.sh owner/repo 0123456789abcdef0123456789abcdef01234567 tf-test-agent/verify success "all checks passed" https://example.test/run/1
  [ "$status" -eq 0 ]
  [[ "$output" == *"tf-test-agent/verify=success on 0123456"* ]]
  grep -q "POST repos/owner/repo/statuses/0123456789abcdef0123456789abcdef01234567 state=success context=tf-test-agent/verify description=all checks passed target_url=https://example.test/run/1" "$FAKE_GH_LOG"
}

@test "post-status works without a target url and truncates long descriptions" {
  install_fake_gh "[]"
  long="$(printf 'x%.0s' $(seq 1 200))"
  run scripts/post-status.sh owner/repo abcdef1 tf-test-agent/guard failure "$long"
  [ "$status" -eq 0 ]
  ! grep -q "target_url" "$FAKE_GH_LOG"
  desc="$(grep -o 'description=x*' "$FAKE_GH_LOG" | head -1)"
  [ "${#desc}" -eq $((12 + 140)) ]
}

@test "post-status rejects an unknown state and a non-sha" {
  install_fake_gh "[]"
  run scripts/post-status.sh owner/repo abcdef1 ctx maybe "d"
  [ "$status" -eq 2 ]
  run scripts/post-status.sh owner/repo not-a-sha ctx success "d"
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_GH_LOG" ]
}

# --- helpers local to this file --------------------------------------------

install_fake_gh() {
  local comments_json="$1"
  FAKE_GH_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/gh.XXXXXX")"
  export FAKE_GH_LOG="$FAKE_GH_DIR/calls.log"
  printf '%s' "$comments_json" > "$FAKE_GH_DIR/comments.json"
  cat > "$FAKE_GH_DIR/gh" <<EOF
#!/usr/bin/env bash
log="$FAKE_GH_LOG"
comments="$FAKE_GH_DIR/comments.json"
EOF
  cat >> "$FAKE_GH_DIR/gh" <<'EOF'
method="GET"; path=""; jqexpr=""; fields=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    --method) method="${args[$((i+1))]}"; i=$((i+1)) ;;
    --jq) jqexpr="${args[$((i+1))]}"; i=$((i+1)) ;;
    --paginate|api) ;;
    -F) i=$((i+1)) ;;
    -f) fields="$fields ${args[$((i+1))]}"; i=$((i+1)) ;;
    *) [[ -z "$path" ]] && path="${args[$i]}" ;;
  esac
done
echo "$method $path$fields" >> "$log"
if [[ "$method" == "GET" ]]; then
  if [[ -n "$jqexpr" ]]; then jq -r "$jqexpr" "$comments"; else cat "$comments"; fi
else
  echo '{"id": 99}'
fi
EOF
  chmod +x "$FAKE_GH_DIR/gh"
  export PATH="$FAKE_GH_DIR:$PATH"
}
