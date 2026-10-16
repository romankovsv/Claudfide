#!/usr/bin/env bash
# Run the tf-test-engineer agent locally with the same definition CI uses.
#
# Usage:
#   scripts/run-agent-local.sh                 # analyse current branch vs main
#   scripts/run-agent-local.sh --base develop  # different base branch
#   scripts/run-agent-local.sh --all           # full coverage pass over every unit
#   scripts/run-agent-local.sh --interactive   # open an interactive session instead of -p
#
# Requires the Claude Code CLI (`claude`) authenticated, Terraform and jq.
# Headless runs write the structured report to .tf-test-agent/report.json and
# the full transcript to .tf-test-agent/run.json. Nothing is pushed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

base="main" mode="pr" interactive=false
budget="${TF_TEST_AGENT_BUDGET_USD:-5}"
max_turns="${TF_TEST_AGENT_MAX_TURNS:-120}"
model="${TF_TEST_AGENT_MODEL:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) shift; base="$1" ;;
    --all) mode="full" ;;
    --interactive) interactive=true ;;
    *) echo "run-agent-local.sh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

for tool in claude terraform jq git; do
  command -v "$tool" > /dev/null || { echo "run-agent-local.sh: $tool is required" >&2; exit 2; }
done

out=".tf-test-agent"
mkdir -p "$out"
prompt="$(scripts/agent-prompt.sh --mode "$mode" --base "$base" --head HEAD)"

# The allow-list mirrors the CI workflow: file tools, the Terraform wrapper,
# and the git commands needed to commit. No network tools, no raw terraform.
allowed_tools='Read,Grep,Glob,Edit,Write,Skill,Bash(scripts/tf.sh:*),Bash(scripts/changed-modules.sh:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git add:*),Bash(git commit:*),Bash(git rev-parse:*)'

args=(--agent tf-test-engineer --allowedTools "$allowed_tools")
[[ -n "$model" ]] && args+=(--model "$model")

if [[ "$interactive" == true ]]; then
  exec claude "${args[@]}" "$prompt"
fi

echo "run-agent-local.sh: mode=$mode base=$base budget=\$$budget max_turns=$max_turns" >&2
claude -p "${args[@]}" \
  --permission-mode acceptEdits \
  --max-turns "$max_turns" \
  --max-budget-usd "$budget" \
  --json-schema "$(cat scripts/report.schema.json)" \
  --output-format json \
  "$prompt" > "$out/run.json" || rc=$?

if jq -e '.structured_output' "$out/run.json" > /dev/null 2>&1; then
  jq '.structured_output' "$out/run.json" > "$out/report.json"
  echo "run-agent-local.sh: report written to $out/report.json" >&2
  jq -r '.decision + " — " + .summary' "$out/report.json" >&2
else
  echo "run-agent-local.sh: no structured report in $out/run.json" >&2
fi
exit "${rc:-0}"
