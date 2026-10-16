#!/usr/bin/env bash
# Render the pull request comment of the Terraform test agent.
#
# Inputs are files, so the comment can be assembled by a plain CI step even
# when the agent itself failed, timed out or ran out of budget:
#   --report FILE     JSON produced by the agent (scripts/report.schema.json)
#   --verify FILE     summary.md written by scripts/verify.sh (optional)
#   --guard FILE      text output of scripts/guard-agent-diff.sh (optional)
#   --status TEXT     agent step status: success | failure | skipped | cancelled
#   --run-url URL     link to the workflow run
#   --head SHA        commit the results refer to
#   --marker NAME     marker id (default tf-test-agent-report). CI uses a second
#                     marker, tf-test-agent-verify, for runs in which the agent
#                     was skipped, so the agent's report is not overwritten by
#                     the verification of its own commit.
#
# The comment starts with a hidden marker so post-comment.sh can update it in
# place instead of adding a new comment on every push.
set -euo pipefail

marker_name="tf-test-agent-report"
report="" verify="" guard="" status="unknown" run_url="" head=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) shift; report="$1" ;;
    --verify) shift; verify="$1" ;;
    --guard) shift; guard="$1" ;;
    --status) shift; status="$1" ;;
    --run-url) shift; run_url="$1" ;;
    --head) shift; head="$1" ;;
    --marker) shift; marker_name="$1" ;;
    *) echo "render-report.sh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

echo "<!-- ${marker_name} -->"
if [[ "$status" == "skipped" ]]; then
  echo "## 🧪 Terraform test agent — verification only"
else
  echo "## 🧪 Terraform test agent"
fi
echo
[[ -n "$head" ]] && echo "Results for commit \`${head:0:7}\`. "
[[ -n "$run_url" ]] && echo "[Workflow run]($run_url)"
echo

valid_report=false
if [[ -n "$report" && -s "$report" ]] && jq -e 'type == "object" and has("decision")' "$report" > /dev/null 2>&1; then
  valid_report=true
fi

if [[ "$valid_report" == true ]]; then
  jq -r '
    def badge: {tests_created: "🟢 tests created", tests_updated: "🟢 tests updated",
                no_tests_needed: "⚪ no test changes needed", blocked: "🔴 blocked"}[.] // .;
    def sev: {high: "🔴 high", medium: "🟠 medium", low: "🟡 low", info: "🔵 info"}[.] // .;
    "**Decision:** " + (.decision | badge),
    "",
    .summary,
    "",
    "### Units",
    "| Unit | Change | Action | Reason |",
    "|---|---|---|---|",
    (.units[] | "| `\(.path)` | \(.change_kind) | \(.action) | \(.reason) |"),
    "",
    "### Agent test runs (self-reported, see verification below)",
    "| Unit | Result | Passed | Failed | Notes |",
    "|---|---|---|---|---|",
    (if (.tests_run | length) == 0 then "| – | not run | | | |" else
      (.tests_run[] | "| `\(.unit)` | \(.result) | \(.passed) | \(.failed) | \(.notes // "") |") end),
    "",
    (if (.findings | length) == 0 then "### Findings\n_No findings for reviewers._"
     else
      "### Findings for reviewers",
      "_The agent reports; it never changes infrastructure code. Decisions stay with you._",
      "",
      (.findings[] |
        "- **" + (.severity | sev) + "** · `" + .unit + "`" +
        (if .file then " · `" + .file + (if .line then ":" + (.line|tostring) else "" end) + "`" else "" end) +
        " — **" + .title + "**\n  " + .detail +
        (if .recommendation then "\n  _Suggestion:_ " + .recommendation else "" end))
     end),
    "",
    (if .limitations then "### Limitations\n" + .limitations else empty end),
    "",
    "_Skills used: " + ((.skills_used // []) | map("`" + . + "`") | join(", ")) + "_"
  ' "$report"
else
  case "$status" in
    success)   echo "⚠️ The agent finished but did not return a readable report." ;;
    skipped)   echo "⏭️ The agent did not run for this event (bot commit, draft PR, or \`tf-tests:skip\` label)." ;;
    cancelled) echo "⏹️ The agent run was cancelled (superseded by a newer push)." ;;
    *)         echo "❌ The agent did not complete (status: \`$status\`). Nothing was committed on its behalf; check the workflow log." ;;
  esac
fi

echo
echo "### Independent verification (no LLM, no secrets)"
if [[ -n "$verify" && -s "$verify" ]]; then
  cat "$verify"
else
  echo "_Verification results are not available for this run._"
fi

if [[ -n "$guard" && -s "$guard" ]]; then
  echo
  echo "<details><summary>Scope guard</summary>"
  echo
  echo '```'
  cat "$guard"
  echo '```'
  echo "</details>"
fi
