#!/usr/bin/env bash
# Deterministic change analysis for the Terraform test agent.
#
# Lists the Terraform units (modules/<name>, stacks/<name>) touched between two
# git revisions, classifies every changed file, and reports whether the unit
# already has tests. The agent reads this JSON instead of interpreting raw
# diffs, which keeps the "which modules changed" question out of the LLM.
#
# Usage:
#   scripts/changed-modules.sh <base_ref> [head_ref]   # diff mode (merge-base)
#   scripts/changed-modules.sh --all                   # every unit, no diff
#
# Output (JSON):
# {
#   "mode": "diff" | "all",
#   "base": "<sha>", "head": "<sha>",            # diff mode only
#   "units": [
#     {
#       "path": "modules/network",
#       "kind": "module" | "stack",
#       "has_tests": true,
#       "test_files": ["modules/network/tests/main.tftest.hcl"],
#       "tf_changed": true,          # any .tf/.tfvars/script changed
#       "tests_changed": false,      # any .tftest.hcl changed
#       "change_kinds": ["code", "variables"],
#       "files": [ {"path": "...", "status": "M", "category": "code"} ]
#     }
#   ],
#   "other_files": ["README.md"]                    # changed files outside units
# }
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

die() { echo "changed-modules.sh: $*" >&2; exit 2; }
command -v jq > /dev/null || die "jq is required"

# Classify a repository-relative path inside a unit.
categorize() {
  local rel="$1"
  case "$rel" in
    tests/*.tftest.hcl) echo "test" ;;
    *.tftest.hcl)       echo "test" ;;
    variables.tf)       echo "variables" ;;
    outputs.tf)         echo "outputs" ;;
    versions.tf)        echo "versions" ;;
    provider.tf|providers.tf) echo "provider" ;;
    envs/*.tfvars|*.tfvars)   echo "tfvars" ;;
    *.tf)               echo "code" ;;
    scripts/*)          echo "script" ;;
    .terraform.lock.hcl) echo "lock" ;;
    *)                  echo "other" ;;
  esac
}

# Emit the JSON object describing one unit; the file list is passed as JSON.
unit_json() {
  local unit="$1" files_json="$2"
  local kind="module"
  [[ "$unit" == stacks/* ]] && kind="stack"
  local tests_json="[]"
  if compgen -G "$unit/tests/*.tftest.hcl" > /dev/null; then
    tests_json="$(printf '%s\n' "$unit"/tests/*.tftest.hcl | jq -R . | jq -s .)"
  fi
  jq -n \
    --arg path "$unit" \
    --arg kind "$kind" \
    --argjson tests "$tests_json" \
    --argjson files "$files_json" \
    '{
      path: $path,
      kind: $kind,
      has_tests: ($tests | length > 0),
      test_files: $tests,
      tf_changed: ([$files[] | select(.category != "test" and .category != "other")] | length > 0),
      tests_changed: ([$files[] | select(.category == "test")] | length > 0),
      change_kinds: ([$files[].category] | unique),
      files: $files
    }'
}

list_all_units() {
  local u
  for u in modules/*/ stacks/*/; do
    [[ -d "$u" ]] || continue
    u="${u%/}"
    compgen -G "$u/*.tf" > /dev/null || continue
    echo "$u"
  done
}

if [[ "${1:-}" == "--all" ]]; then
  units_json="[]"
  while IFS= read -r u; do
    units_json="$(jq -n --argjson acc "$units_json" --argjson item "$(unit_json "$u" '[]')" '$acc + [$item]')"
  done < <(list_all_units)
  jq -n --argjson units "$units_json" '{mode: "all", units: $units, other_files: []}'
  exit 0
fi

[[ $# -ge 1 ]] || die "usage: changed-modules.sh <base_ref> [head_ref] | --all"
base_ref="$1"
head_ref="${2:-HEAD}"

base_sha="$(git rev-parse --verify "${base_ref}^{commit}" 2> /dev/null)" || die "unknown base ref: $base_ref"
head_sha="$(git rev-parse --verify "${head_ref}^{commit}" 2> /dev/null)" || die "unknown head ref: $head_ref"
merge_base="$(git merge-base "$base_sha" "$head_sha")" || die "no merge base between $base_ref and $head_ref"

# name-status with renames collapsed to the new path.
declare -A unit_files=()
other_files=()
while IFS=$'\t' read -r status path newpath; do
  [[ -n "$status" ]] || continue
  case "$status" in
    R*|C*) path="$newpath"; status="${status:0:1}" ;;
  esac
  if [[ "$path" =~ ^((modules|stacks)/[^/]+)/(.+)$ ]]; then
    unit="${BASH_REMATCH[1]}"
    rel="${BASH_REMATCH[3]}"
    cat="$(categorize "$rel")"
    entry="$(jq -n --arg p "$path" --arg s "$status" --arg c "$cat" '{path: $p, status: $s, category: $c}')"
    unit_files["$unit"]="${unit_files[$unit]:-}${entry}"$'\n'
  else
    other_files+=("$path")
  fi
done < <(git diff --name-status "$merge_base" "$head_sha" --)

units_json="[]"
for unit in $(printf '%s\n' "${!unit_files[@]}" | sort); do
  files_json="$(printf '%s' "${unit_files[$unit]}" | jq -s .)"
  if [[ -d "$unit" ]]; then
    item="$(unit_json "$unit" "$files_json")"
  else
    # The unit was deleted in this change set.
    item="$(jq -n --arg path "$unit" --argjson files "$files_json" \
      '{path: $path, kind: (if ($path | startswith("stacks/")) then "stack" else "module" end),
        deleted: true, has_tests: false, test_files: [], tf_changed: true, tests_changed: false,
        change_kinds: ([$files[].category] | unique), files: $files}')"
  fi
  units_json="$(jq -n --argjson acc "$units_json" --argjson item "$item" '$acc + [$item]')"
done

other_json="$(printf '%s\n' ${other_files[@]+"${other_files[@]}"} | sed '/^$/d' | jq -R . | jq -s .)"

jq -n \
  --arg base "$base_sha" --arg head "$head_sha" \
  --argjson units "$units_json" --argjson other "$other_json" \
  '{mode: "diff", base: $base, head: $head, units: $units, other_files: $other}'
