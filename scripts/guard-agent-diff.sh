#!/usr/bin/env bash
# Guard: the test agent may only add or change Terraform test files.
#
# The agent's instructions say "tests only", but instructions are not
# enforcement. This script compares the pull request head before the agent
# ran with the branch tip after it ran and fails when any file outside the
# allowed set was touched. CI runs it as a required check, so a run in which
# the agent (or anything impersonating it) edited infrastructure code, the
# workflow, or its own instructions cannot be merged unnoticed.
#
# Usage:
#   scripts/guard-agent-diff.sh <before_sha> <after_sha>
#
# Exit codes: 0 clean, 1 violation, 2 usage/error.
set -euo pipefail

die() { echo "guard-agent-diff.sh: $*" >&2; exit 2; }

[[ $# -eq 2 ]] || die "usage: guard-agent-diff.sh <before_sha> <after_sha>"
before="$1"
after="$2"

git rev-parse --verify "${before}^{commit}" > /dev/null 2>&1 || die "unknown revision: $before"
git rev-parse --verify "${after}^{commit}" > /dev/null 2>&1 || die "unknown revision: $after"

# Allowed: test files inside a module or stack. Nothing else.
ALLOWED_RE='^(modules|stacks)/[^/]+/tests/[^/]+\.tftest\.hcl$'

if [[ "$(git rev-parse "$before")" == "$(git rev-parse "$after")" ]]; then
  echo "guard: no commits were added by the agent"
  exit 0
fi

if ! git merge-base --is-ancestor "$before" "$after"; then
  echo "guard: VIOLATION — $after does not descend from $before (history was rewritten)" >&2
  exit 1
fi

mapfile -t changed < <(git diff --name-only "$before" "$after" --)
violations=()
for f in "${changed[@]}"; do
  [[ "$f" =~ $ALLOWED_RE ]] || violations+=("$f")
done

echo "guard: ${#changed[@]} file(s) changed between ${before:0:7} and ${after:0:7}"
for f in "${changed[@]}"; do echo "  $f"; done

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "guard: VIOLATION — files outside **/tests/*.tftest.hcl were modified:" >&2
  for f in "${violations[@]}"; do echo "  $f" >&2; done
  exit 1
fi

echo "guard: OK — only test files were touched"
