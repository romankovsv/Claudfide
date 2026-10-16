#!/usr/bin/env bash
# Independent verification of the repository's Terraform code and tests.
#
# Runs, for every module and stack (or the units given with --units):
#   1. terraform fmt -check
#   2. terraform validate
#   3. terraform test            (only where tests/*.tftest.hcl exist)
# through scripts/tf.sh, so no cloud credentials or secrets are involved.
#
# CI runs this in a job that has no LLM and no secrets: it is the oracle that
# decides whether what the agent committed is actually green. Humans run it
# with `make verify`.
#
# Usage:
#   scripts/verify.sh [--units "modules/a modules/b"] [--out DIR]
#
# Writes to DIR (default .verify-out):
#   summary.md     markdown table for PR comments / step summaries
#   summary.json   machine-readable results
#   <unit>.log     full terraform output per unit
#   <unit>.xml     JUnit report of terraform test, where tests ran
# Exit code: 0 when everything passed, 1 otherwise.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

out_dir=".verify-out"
units=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --units) shift; read -r -a units <<< "$1" ;;
    --out) shift; out_dir="$1" ;;
    *) echo "verify.sh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ ${#units[@]} -eq 0 ]]; then
  for u in modules/*/ stacks/*/; do
    [[ -d "$u" ]] || continue
    u="${u%/}"
    compgen -G "$u/*.tf" > /dev/null || continue
    units+=("$u")
  done
fi

mkdir -p "$out_dir"
results="[]"
overall=0

record() {
  # record <unit> <step> <status> <detail>
  results="$(jq -n --argjson acc "$results" \
    --arg unit "$1" --arg step "$2" --arg status "$3" --arg detail "$4" \
    '$acc + [{unit: $unit, step: $step, status: $status, detail: $detail}]')"
}

run_step() {
  # run_step <unit> <step> <log> <cmd...>; returns the command's exit code
  local unit="$1" step="$2" log="$3"
  shift 3
  {
    echo "### $step: $unit"
    echo "\$ $*"
  } >> "$log"
  local rc=0
  "$@" >> "$log" 2>&1 || rc=$?
  echo "(exit $rc)" >> "$log"
  return $rc
}

for unit in "${units[@]}"; do
  slug="${unit//\//_}"
  log="$out_dir/$slug.log"
  : > "$log"

  if run_step "$unit" fmt "$log" scripts/tf.sh fmt "$unit"; then
    record "$unit" fmt pass ""
  else
    record "$unit" fmt fail "files need terraform fmt"
    overall=1
  fi

  if run_step "$unit" validate "$log" scripts/tf.sh validate "$unit"; then
    record "$unit" validate pass ""
  else
    record "$unit" validate fail "terraform validate failed"
    overall=1
  fi

  if compgen -G "$unit/tests/*.tftest.hcl" > /dev/null; then
    junit="$out_dir/$slug.xml"
    if run_step "$unit" test "$log" scripts/tf.sh test "$unit" "-junit-xml=$junit"; then
      summary="$(grep -E '^Success! [0-9]+ passed' "$log" | tail -1 || true)"
      record "$unit" test pass "${summary:-passed}"
    else
      summary="$(grep -E '^Failure! [0-9]+ passed' "$log" | tail -1 || true)"
      record "$unit" test fail "${summary:-terraform test failed}"
      overall=1
    fi
  else
    record "$unit" test skipped "no tests/*.tftest.hcl"
  fi
done

jq -n --argjson results "$results" --argjson ok "$([[ $overall -eq 0 ]] && echo true || echo false)" \
  '{ok: $ok, results: $results}' > "$out_dir/summary.json"

{
  echo "| Unit | fmt | validate | test |"
  echo "|---|---|---|---|"
  jq -r '
    def icon: if . == "pass" then "✅" elif . == "fail" then "❌" elif . == "skipped" then "➖" else . end;
    . as $root
    | ([$root.results[] | .unit] | unique)[]
    | . as $u
    | [ $u,
        ($root.results[] | select(.unit == $u and .step == "fmt") | .status | icon),
        ($root.results[] | select(.unit == $u and .step == "validate") | .status | icon),
        ($root.results[] | select(.unit == $u and .step == "test") | (.status | icon) + " " + .detail) ]
    | "| " + join(" | ") + " |"
  ' "$out_dir/summary.json"
  echo
  if [[ $overall -eq 0 ]]; then
    echo "**Result: all checks passed.**"
  else
    echo "**Result: FAILED** — see the logs attached to the workflow run."
  fi
} > "$out_dir/summary.md"

cat "$out_dir/summary.md"

# Inside GitHub Actions, surface the tail of every failing log as an error
# annotation, so the cause is visible on the pull request without opening
# the raw logs.
if [[ $overall -ne 0 && "${GITHUB_ACTIONS:-}" == "true" ]]; then
  jq -r '.results[] | select(.status == "fail") | .unit + "\t" + .step' "$out_dir/summary.json" |
    while IFS=$'\t' read -r unit step; do
      tail_text="$(tail -n 25 "$out_dir/${unit//\//_}.log" | sed 's/%/%25/g' | tr -d '\r' | sed ':a;N;$!ba;s/\n/%0A/g')"
      echo "::error title=${step} failed for ${unit}::${tail_text}"
    done
fi
exit $overall
