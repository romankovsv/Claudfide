#!/usr/bin/env bash
# SessionStart hook: the test agent's session holds no git credentials.
#
# In CI, claude-code-action writes its token into the origin URL
# (https://x-access-token:<token>@github.com/...) before Claude starts, and
# actions/checkout may leave an Authorization header in .git/config or in an
# included file. The agent never pushes — the workflow pushes its commits
# after the guard — so none of that is needed while the agent runs. This hook
# removes it: the origin URL loses its credential part, every
# http.*.extraheader entry is unset (local config and included files) and a
# repository-local credential helper is dropped. Only the local repository
# configuration is touched; SSH and plain URLs are left as they are.
set -euo pipefail
# shellcheck source=scripts/hooks/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
agent_session_or_exit
read_input

root="$(project_dir)"
git -C "$root" rev-parse --git-dir > /dev/null 2>&1 || exit 0

url="$(git -C "$root" config --local --get remote.origin.url 2>/dev/null || true)"
if [[ "$url" =~ ^(https?://)[^/@]+@(.*)$ ]]; then
  git -C "$root" remote set-url origin "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  echo "strip-git-credentials: removed the credential from remote.origin.url" >&2
fi

# Authorization headers: in the local config and in every included file.
while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  git -C "$root" config --local --unset-all "$key" || true
done < <(git -C "$root" config --local --name-only --get-regexp '^http\..*\.extraheader$' 2>/dev/null || true)
while IFS= read -r inc; do
  [[ -n "$inc" && -f "$inc" ]] || continue
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    git config --file "$inc" --unset-all "$key" || true
  done < <(git config --file "$inc" --name-only --get-regexp '^http\..*\.extraheader$' 2>/dev/null || true)
done < <(git -C "$root" config --local --get-all include.path 2>/dev/null || true)

git -C "$root" config --local --unset-all credential.helper 2>/dev/null || true
exit 0
