#!/usr/bin/env bash
# Shared helpers for the Claude Code hooks of the test agent.
#
# Every hook starts with `agent_session_or_exit`: the hooks only act in a
# session of the test agent (TF_TEST_AGENT=1, set by the workflow and by
# scripts/run-agent-local.sh). A human using Claude Code in this repository
# is not restricted by them.
#
# Hook input is JSON on stdin (tool_name, tool_input, cwd, ...). Hooks block
# by printing a JSON decision and exiting 0; exiting 2 would also block but
# gives Claude only the stderr text. See https://code.claude.com/docs/en/hooks.

agent_session_or_exit() {
  [[ "${TF_TEST_AGENT:-}" == "1" ]] || exit 0
  command -v jq > /dev/null || { echo "hook: jq is required" >&2; exit 0; }
}

# Read all of stdin into $HOOK_INPUT.
read_input() {
  HOOK_INPUT="$(cat)"
  [[ -n "$HOOK_INPUT" ]] || HOOK_INPUT='{}'
}

# jq over the hook input: input_get '.tool_input.file_path'
input_get() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty"
}

# Project root: Claude Code exports CLAUDE_PROJECT_DIR for hooks; fall back
# to the cwd in the input, then to the working directory.
project_dir() {
  local d="${CLAUDE_PROJECT_DIR:-}"
  [[ -n "$d" ]] || d="$(input_get '.cwd')"
  [[ -n "$d" ]] || d="$PWD"
  printf '%s' "${d%/}"
}

# Turn a tool path into a path relative to the project root, without
# resolving symlinks. Prints nothing when the path escapes the project.
relative_path() {
  local p="$1" root
  root="$(project_dir)"
  if [[ "$p" == /* ]]; then
    [[ "$p" == "$root/"* ]] || return 0
    p="${p#"$root"/}"
  fi
  p="${p#./}"
  # any ".." component means we cannot reason about the target
  case "/$p/" in */../*) return 0 ;; esac
  printf '%s' "$p"
}

deny_tool() {
  jq -cn --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

block_stop() {
  jq -cn --arg reason "$1" '{decision: "block", reason: $reason}'
  exit 0
}
