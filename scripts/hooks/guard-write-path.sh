#!/usr/bin/env bash
# PreToolUse hook for Write / Edit / MultiEdit: the test agent may only write
# test files and its report.
#
# The CI guard rejects a *commit* that touches anything else; this hook stops
# the *write* itself, so a prompt-injected agent cannot rewrite scripts/tf.sh
# and run it, plant a .tf with a data "external" program, or edit its own
# instructions and hooks. Allowed:
#   modules/<unit>/tests/<name>.tftest.hcl
#   stacks/<unit>/tests/<name>.tftest.hcl
#   agent-out/report.json
set -euo pipefail
# shellcheck source=scripts/hooks/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
agent_session_or_exit
read_input

tool="$(input_get '.tool_name')"
path="$(input_get '.tool_input.file_path')"
[[ -n "$path" ]] || deny_tool "$tool without a file_path is not allowed."

rel="$(relative_path "$path")"
[[ -n "$rel" ]] || deny_tool "Refusing to write outside the repository or through '..': $path"

case "$rel" in
  modules/*/tests/*.tftest.hcl|stacks/*/tests/*.tftest.hcl)
    # exactly one directory level for the unit and one file name
    unit="${rel#*/}"; unit="${unit%%/*}"
    file="${rel##*/}"
    [[ "$rel" == "modules/$unit/tests/$file" || "$rel" == "stacks/$unit/tests/$file" ]] \
      || deny_tool "Test files live directly in <unit>/tests/: $rel"
    exit 0 ;;
  agent-out/report.json)
    exit 0 ;;
esac

deny_tool "The test agent may only write modules/*/tests/*.tftest.hcl, stacks/*/tests/*.tftest.hcl and agent-out/report.json. If the infrastructure code needs a change, report it as a finding instead. Refused: $rel"
