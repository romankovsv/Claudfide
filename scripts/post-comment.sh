#!/usr/bin/env bash
# Create or update a single "sticky" comment on a pull request.
#
# The comment is identified by a marker line (the first line of the body).
# Updating in place keeps the PR conversation readable when the workflow
# runs on every push.
#
# Usage:
#   scripts/post-comment.sh <owner/repo> <pr_number> <body_file>
# Requires: gh CLI authenticated (GH_TOKEN / GITHUB_TOKEN with pull-requests: write).
set -euo pipefail

die() { echo "post-comment.sh: $*" >&2; exit 2; }
[[ $# -eq 3 ]] || die "usage: post-comment.sh <owner/repo> <pr_number> <body_file>"
repo="$1" pr="$2" body_file="$3"
[[ -s "$body_file" ]] || die "body file is empty: $body_file"
command -v gh > /dev/null || die "gh CLI is required"

marker="$(head -n 1 "$body_file")"
[[ "$marker" == "<!--"*"-->" ]] || die "body must start with an HTML marker comment"

existing_id="$(gh api --paginate "repos/$repo/issues/$pr/comments" \
  --jq ".[] | select(.body | startswith(\"$marker\")) | .id" | head -n 1 || true)"

if [[ -n "$existing_id" ]]; then
  gh api --method PATCH "repos/$repo/issues/comments/$existing_id" -F body=@"$body_file" > /dev/null
  echo "updated comment $existing_id on $repo#$pr"
else
  gh api --method POST "repos/$repo/issues/$pr/comments" -F body=@"$body_file" > /dev/null
  echo "created comment on $repo#$pr"
fi
