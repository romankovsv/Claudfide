#!/usr/bin/env bats
# Tests for scripts/transcript-summary.sh and scripts/validate-report.py.

load helpers

setup() {
  make_fixture_repo
  cat > exec.json <<'EOF'
[
 {"type":"system","subtype":"init"},
 {"type":"assistant","message":{"content":[{"type":"text","text":"Analysing | the change."},{"type":"tool_use","name":"Bash","input":{"command":"scripts/changed-modules.sh main HEAD"}}]}},
 {"type":"user","message":{"content":[{"type":"tool_result","content":"SECRET-OUTPUT-MUST-NOT-APPEAR"}]}},
 {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"modules/alpha/main.tf"}}]}},
 {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"tf-test-authoring"}}]}},
 {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"modules/alpha/tests/main.tftest.hcl","content":"x"}}]}},
 {"type":"assistant","message":{"content":[{"type":"text","text":"Done."}]}},
 {"type":"result","subtype":"success","num_turns":7,"total_cost_usd":0.1234,"duration_ms":45000,"is_error":false,"permission_denials":[{"tool_name":"Bash","tool_input":{"command":"cat modules/*/main.tf"}}],"result":"ok"}
]
EOF
}

@test "summarises tool calls, text, denials and the result" {
  run scripts/transcript-summary.sh exec.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"| 1 | \`💬\` | Analysing \\| the change. |"* ]]
  [[ "$output" == *"| 2 | \`Bash\` | scripts/changed-modules.sh main HEAD |"* ]]
  [[ "$output" == *"| 3 | \`Read\` | modules/alpha/main.tf |"* ]]
  [[ "$output" == *"| 4 | \`Skill\` | tf-test-authoring |"* ]]
  [[ "$output" == *"Permission denials"* ]]
  [[ "$output" == *"cat modules/*/main.tf"* ]]
  [[ "$output" == *"**Result:** success · 7 turns · \$0.12 · 45 s"* ]]
  [[ "$output" != *"SECRET-OUTPUT-MUST-NOT-APPEAR"* ]]
}

@test "accepts JSON lines as well as an array" {
  jq -c '.[]' exec.json > exec.jsonl
  run scripts/transcript-summary.sh exec.jsonl
  [ "$status" -eq 0 ]
  [[ "$output" == *"| 2 | \`Bash\` |"* ]]
}

@test "caps the number of listed steps" {
  run scripts/transcript-summary.sh exec.json --max-tools 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"| 2 | \`Bash\` |"* ]]
  [[ "$output" != *"| 3 | \`Read\` |"* ]]
  [[ "$output" == *"more steps not shown"* ]]
}

@test "handles a missing or empty transcript" {
  run scripts/transcript-summary.sh nope.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"No transcript"* ]]
}

@test "validate-report accepts a valid report" {
  cat > report.json <<'EOF'
{"decision":"no_tests_needed","summary":"s","units":[{"path":"modules/alpha","change_kind":"format_only","action":"unchanged","reason":"r"}],
 "tests_run":[{"unit":"modules/alpha","result":"pass","passed":3,"failed":0}],"findings":[],"skills_used":["tf-change-analysis"]}
EOF
  run python3 scripts/validate-report.py report.json
  [ "$status" -eq 0 ]
}

@test "validate-report rejects wrong enums, types, missing and extra keys" {
  cat > bad.json <<'EOF'
{"decision":"maybe","summary":1,"units":[{"path":"x","change_kind":"resources","action":"created"}],
 "tests_run":[{"unit":"u","result":"pass","passed":-1,"failed":true}],"findings":[{"severity":"high","unit":"u","title":"t"}],"skills_used":"x","extra":1}
EOF
  run python3 scripts/validate-report.py bad.json
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision"* ]]
  [[ "$output" == *"expected string"* ]]
  [[ "$output" == *"missing required key 'reason'"* ]]
  [[ "$output" == *"below the minimum"* ]]
  [[ "$output" == *"expected integer, got boolean"* ]]
  [[ "$output" == *"missing required key 'detail'"* ]]
  [[ "$output" == *"unexpected key 'extra'"* ]]
}

@test "validate-report rejects unreadable input" {
  echo '{not json' > broken.json
  run python3 scripts/validate-report.py broken.json
  [ "$status" -eq 1 ]
  run python3 scripts/validate-report.py
  [ "$status" -eq 2 ]
}

@test "render-report embeds the transcript when given" {
  scripts/transcript-summary.sh exec.json > transcript.md
  run scripts/render-report.sh --status failure --transcript transcript.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"What the agent did"* ]]
  [[ "$output" == *"scripts/changed-modules.sh main HEAD"* ]]
}
