#!/usr/bin/env bash
# PreToolUse hook for Write / Edit / MultiEdit on *.tftest.hcl: house rules
# that must hold before a test file touches disk.
#
#   - tests never apply: `command = apply` is refused (mock providers cannot
#     apply azurerm resources, and apply is the one thing that could create
#     something real);
#   - tests never configure a real provider: a `provider "..."` block is
#     refused — a test file must use mock_provider;
#   - a whole new file (Write) must declare a mock_provider.
#
# Edits only carry the changed text, so only the first two rules apply to
# them. Everything else about test quality is the verify job's business.
set -euo pipefail
# shellcheck source=scripts/hooks/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
agent_session_or_exit
read_input

tool="$(input_get '.tool_name')"
path="$(input_get '.tool_input.file_path')"
[[ "$path" == *.tftest.hcl ]] || exit 0

case "$tool" in
  Write)      text="$(input_get '.tool_input.content')" ;;
  Edit)       text="$(input_get '.tool_input.new_string')" ;;
  MultiEdit)  text="$(printf '%s' "$HOOK_INPUT" | jq -r '[.tool_input.edits[]?.new_string // empty] | join("\n")')" ;;
  *)          exit 0 ;;
esac

if printf '%s' "$text" | grep -Eq '^[[:space:]]*command[[:space:]]*=[[:space:]]*apply'; then
  deny_tool "Tests in this repository use command = plan only; apply is never run, even against mocks."
fi
if printf '%s' "$text" | grep -Eq '^[[:space:]]*provider[[:space:]]+"'; then
  deny_tool "Test files must not configure a real provider; use mock_provider \"azurerm\" {} (and mock_provider \"external\" {} where needed)."
fi
if [[ "$tool" == "Write" ]] && ! printf '%s' "$text" | grep -Eq '^[[:space:]]*mock_provider[[:space:]]+"'; then
  deny_tool "A test file must declare mock_provider (tests run without cloud credentials)."
fi
exit 0
