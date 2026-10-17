#!/usr/bin/env bash
# Decide whether the agent job may run for a pull request event.
#
# The agent must never run on its own commit: its push re-triggers the
# workflow, and GitHub attributes that run to a bot actor (observed:
# `github-actions[bot]`, not `claude[bot]`). Approving or re-running such a
# run changes the actor again, so the actor alone is not a reliable signal.
# This script combines every signal in one deterministic, testable place:
#
#   - draft pull requests and the `tf-tests:skip` label opt out,
#   - any actor or triggering actor ending in `[bot]` opts out,
#   - a head commit authored by the agent (`claude[bot]`) opts out.
#
# Usage:
#   scripts/agent-gate.sh --actor NAME --triggering-actor NAME \
#       --draft true|false --labels '["a","b"]' --head SHA
#
# Prints `run_agent=true|false` and `reason=...`, ready for $GITHUB_OUTPUT.
set -euo pipefail

actor="" triggering_actor="" draft="false" labels="[]" head="HEAD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor) shift; actor="$1" ;;
    --triggering-actor) shift; triggering_actor="$1" ;;
    --draft) shift; draft="$1" ;;
    --labels) shift; labels="$1" ;;
    --head) shift; head="$1" ;;
    *) echo "agent-gate.sh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

decide() {
  printf 'run_agent=%s\nreason=%s\n' "$1" "$2"
  exit 0
}

if ! printf '%s' "$labels" | jq -e 'type == "array"' > /dev/null 2>&1; then
  echo "agent-gate.sh: --labels must be a JSON array, got: $labels" >&2
  exit 2
fi

[[ "$draft" == "true" ]] && decide false "draft pull request"

if printf '%s' "$labels" | jq -e 'index("tf-tests:skip") != null' > /dev/null; then
  decide false "label tf-tests:skip is set"
fi

for a in "$actor" "$triggering_actor"; do
  [[ "$a" == *"[bot]" ]] && decide false "triggered by a bot actor ($a)"
done

author_name="$(git log -1 --format=%an "$head")"
author_email="$(git log -1 --format=%ae "$head")"
if [[ "$author_name" == "claude[bot]" || "$author_email" == *"claude[bot]@users.noreply.github.com" ]]; then
  decide false "head commit $(git rev-parse --short "$head") was made by the agent"
fi

decide true "pushed by ${actor:-a human}"
