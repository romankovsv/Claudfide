#!/usr/bin/env bash
# PreToolUse hook for Read / Grep / Glob: keep the agent out of places that
# hold credentials or runner internals.
#
# The session-start hook strips the push token from .git/config, so this is
# the second layer: .git/ (remote URLs, credential helpers, hooks), the
# runner's temp directory (where actions/checkout keeps its auth header),
# ~/.claude.json and the usual credential files are never readable by the
# agent. The repository content it needs — including the skills' reference
# files under .claude/skills/ — is all outside these paths.
set -euo pipefail
# shellcheck source=scripts/hooks/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
agent_session_or_exit
read_input

tool="$(input_get '.tool_name')"
case "$tool" in
  Read) target="$(input_get '.tool_input.file_path')" ;;
  Grep) target="$(input_get '.tool_input.path')"; pattern="$(input_get '.tool_input.glob')" ;;
  Glob) target="$(input_get '.tool_input.path')"; pattern="$(input_get '.tool_input.pattern')" ;;
  *) exit 0 ;;
esac

forbidden() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  case "/$p/" in
    */.git/*|*/_temp/*|*/.config/*|*/.ssh/*) return 0 ;;
  esac
  [[ "$p" == *"/.git" || "$p" == ".git" ]] && return 0
  [[ "$p" == *".claude.json"* || "$p" == *".netrc"* || "$p" == *".git-credentials"* ]] && return 0
  return 1
}

if forbidden "$target"; then
  deny_tool "The test agent does not read $target: it holds credentials or tool state, not infrastructure code."
fi
if [[ -n "${pattern:-}" ]] && forbidden "$pattern"; then
  deny_tool "The test agent does not search $pattern: it holds credentials or tool state, not infrastructure code."
fi
exit 0
