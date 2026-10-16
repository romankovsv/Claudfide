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
# Run `claude` interactively in this directory once and accept the workspace
# trust dialog; until then Claude Code ignores .claude/settings.json allow
# rules (the explicit --allowedTools below still apply).
# The agent writes its report to agent-out/report.json; headless runs also
# keep the transcript in agent-out/run.jsonl and a summary in
# agent-out/transcript.md. Nothing is pushed.
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

out="agent-out"
mkdir -p "$out"
rm -f "$out/report.json"
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
  --output-format stream-json --verbose \
  "$prompt" > "$out/run.jsonl" || rc=$?

scripts/transcript-summary.sh "$out/run.jsonl" > "$out/transcript.md" || true
if [[ -s "$out/report.json" ]] && python3 scripts/validate-report.py "$out/report.json" >&2; then
  jq -r '.decision + " — " + .summary' "$out/report.json" >&2
else
  echo "run-agent-local.sh: no valid report in $out/report.json (see $out/transcript.md)" >&2
  rc="${rc:-1}"
fi
exit "${rc:-0}"
