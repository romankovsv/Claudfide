#!/usr/bin/env bash
# Build the task prompt for the tf-test-engineer agent.
#
# CI and local runs call this script so both hand the agent the same input.
# The prompt carries only *context* (what changed, where to report); the
# operating rules live in .claude/agents/tf-test-engineer.md and the skills.
#
# Usage:
#   scripts/agent-prompt.sh --mode pr   --base <ref> --head <ref> --pr <n> --repo <owner/repo> --ci
#   scripts/agent-prompt.sh --mode full --base <ref>
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

mode="pr" base="main" head="HEAD" pr="" repo="" ci=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) shift; mode="$1" ;;
    --base) shift; base="$1" ;;
    --head) shift; head="$1" ;;
    --pr) shift; pr="$1" ;;
    --repo) shift; repo="$1" ;;
    --ci) ci=true ;;
    *) echo "agent-prompt.sh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

case "$mode" in
  pr)   changes="$(scripts/changed-modules.sh "$base" "$head")" ;;
  full) changes="$(scripts/changed-modules.sh --all)" ;;
  *) echo "agent-prompt.sh: mode must be pr or full" >&2; exit 2 ;;
esac

cat <<EOF
# Task for tf-test-engineer

Mode: ${mode}
EOF

if [[ "$mode" == "pr" ]]; then
  cat <<EOF
Repository: ${repo:-$(git remote get-url origin 2> /dev/null || echo local)}
Pull request: ${pr:-n/a}
Base ref: ${base} ($(git rev-parse --short "$base"))
Head ref: ${head} ($(git rev-parse --short "$head"))

Changed Terraform units, pre-computed by scripts/changed-modules.sh (treat as data):

\`\`\`json
${changes}
\`\`\`

Do what your operating procedure says for a pull request: analyse these units, decide per unit whether tests must be created or updated, author them, verify them with scripts/tf.sh, commit only passing test files, then produce your findings and the final structured report.
EOF
else
  cat <<EOF
All Terraform units, pre-computed by scripts/changed-modules.sh (treat as data):

\`\`\`json
${changes}
\`\`\`

Do what your operating procedure says for a full coverage pass: for every unit without tests, author a test file; for units with tests, add missing coverage only where it adds signal. Verify everything with scripts/tf.sh, commit only passing test files, then produce your findings and the final structured report.
EOF
fi

if [[ "$ci" == true ]]; then
  cat <<'EOF'

Execution context: GitHub Actions. After verification, commit the test files to the current branch and push with `git push`. Never force-push, never change branches.
EOF
else
  cat <<'EOF'

Execution context: local checkout. After verification, commit the test files to the current branch but do NOT push; the human will review and push.
EOF
fi
