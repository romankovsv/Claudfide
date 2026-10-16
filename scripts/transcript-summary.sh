#!/usr/bin/env bash
# Summarise a Claude Code execution transcript for humans.
#
# Accepts the stream-json output of Claude Code (a JSON array or JSON lines of
# messages: system / assistant / user / result) and prints markdown with the
# sequence of tool calls, the assistant's own text, permission denials and the
# final result. CI writes it to the step summary and, when the agent failed,
# into the pull request so reviewers can see what happened without opening
# raw logs. Tool *outputs* are left out on purpose: they can be large and are
# not needed to understand the agent's decisions.
#
# Usage: scripts/transcript-summary.sh <execution_file> [--max-tools N]
set -euo pipefail

[[ $# -ge 1 ]] || { echo "usage: transcript-summary.sh <execution_file> [--max-tools N]" >&2; exit 2; }
file="$1"
max_tools=80
[[ "${2:-}" == "--max-tools" && -n "${3:-}" ]] && max_tools="$3"
[[ -s "$file" ]] || { echo "_No transcript available._"; exit 0; }

# Normalise: array or JSON lines -> one message per line.
if jq -e 'type == "array"' "$file" > /dev/null 2>&1; then
  messages="$(jq -c '.[]' "$file")"
else
  messages="$(jq -c . "$file" 2> /dev/null || true)"
fi
[[ -n "$messages" ]] || { echo "_Transcript is not valid JSON._"; exit 0; }

echo "### Agent transcript"
echo
echo "| # | Step | Detail |"
echo "|---|---|---|"
printf '%s\n' "$messages" | jq -r --argjson max "$max_tools" '
  def trunc(n): if length > n then .[0:n] + "…" else . end;
  def cell: gsub("\\|"; "\\|") | gsub("\n"; " ") | gsub("\r"; "");
  select(.type == "assistant")
  | .message.content[]?
  | if .type == "tool_use" then
      "tool\t" + .name + "\t" + ((.input.command // .input.file_path // .input.pattern // .input.skill // (.input | tostring)) | tostring | cell | trunc(140))
    elif .type == "text" and (.text | length) > 0 then
      "text\t💬\t" + (.text | cell | trunc(200))
    else empty end
' | awk -F'\t' -v max="$max_tools" 'NR <= max { printf "| %d | `%s` | %s |\n", NR, $2, $3 } END { if (NR > max) printf "| … | | %d more steps not shown |\n", NR - max }'
echo

denials="$(printf '%s\n' "$messages" | jq -r '
  select(.type == "result") | (.permission_denials // [])[]
  | "- `" + .tool_name + "`: " + ((.tool_input.command // (.tool_input | tostring)) | tostring | .[0:120])
')"
if [[ -n "$denials" ]]; then
  echo "**Permission denials** (tools outside the allow-list; the agent had to use another way):"
  echo "$denials"
  echo
fi

printf '%s\n' "$messages" | jq -r '
  select(.type == "result")
  | "**Result:** " + (.subtype // "unknown")
    + (if .num_turns then " · " + (.num_turns|tostring) + " turns" else "" end)
    + (if .total_cost_usd then " · $" + ((.total_cost_usd * 100 | round) / 100 | tostring) else "" end)
    + (if .duration_ms then " · " + ((.duration_ms / 1000 | round) | tostring) + " s" else "" end)
    + (if .is_error == true then " · **error**" else "" end)
'
