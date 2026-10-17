#!/usr/bin/env bash
# Set a commit status on the pull request's branch tip.
#
# The agent pushes with the workflow's own token, so its push starts no new
# workflow run and the tip commit would otherwise carry no checks at all.
# The report job therefore attaches the verification, guard and agent
# results to the exact commit they refer to, as commit statuses. Required
# status checks on the base branch can name these contexts.
#
# Usage:
#   scripts/post-status.sh <owner/repo> <sha> <context> <state> <description> [target_url]
#   state: success | failure | error | pending
# Requires: gh CLI authenticated (GH_TOKEN / GITHUB_TOKEN with statuses: write).
set -euo pipefail

die() { echo "post-status.sh: $*" >&2; exit 2; }
[[ $# -eq 5 || $# -eq 6 ]] || die "usage: post-status.sh <owner/repo> <sha> <context> <state> <description> [target_url]"
repo="$1" sha="$2" context="$3" state="$4" description="$5" target_url="${6:-}"

case "$state" in
  success|failure|error|pending) ;;
  *) die "state must be success, failure, error or pending (got: $state)" ;;
esac
[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || die "not a commit sha: $sha"
command -v gh > /dev/null || die "gh CLI is required"

# GitHub truncates descriptions longer than 140 characters; keep them short.
description="${description:0:140}"

args=(--method POST "repos/$repo/statuses/$sha" -f "state=$state" -f "context=$context" -f "description=$description")
[[ -n "$target_url" ]] && args+=(-f "target_url=$target_url")

gh api "${args[@]}" > /dev/null
echo "status $context=$state on ${sha:0:7}"
