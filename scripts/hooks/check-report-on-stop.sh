#!/usr/bin/env bash
# Stop hook: the test agent may not finish without a valid report.
#
# When the agent ends its turn and agent-out/report.json is missing or does
# not match scripts/report.schema.json, the stop is blocked once with the
# validator's message, so the agent writes the report itself instead of the
# CI job failing on it afterwards. `stop_hook_active` is true when the agent
# is already continuing because of this hook; then it may stop, whatever the
# state, so a broken report cannot loop forever.
set -euo pipefail
# shellcheck source=scripts/hooks/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
agent_session_or_exit
read_input

[[ "$(input_get '.stop_hook_active')" == "true" ]] && exit 0

root="$(project_dir)"
report="$root/agent-out/report.json"
validator="$root/scripts/validate-report.py"

if [[ ! -s "$report" ]]; then
  block_stop "agent-out/report.json is missing. Write it with the Write tool as JSON matching scripts/report.schema.json (decision, summary, units, tests_run, findings, skills_used), then end your turn."
fi

if ! msg="$(python3 "$validator" "$report" 2>&1)"; then
  block_stop "agent-out/report.json does not match scripts/report.schema.json: ${msg} Fix the report with the Write tool, then end your turn."
fi
exit 0
