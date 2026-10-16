#!/usr/bin/env bash
# Hermetic Terraform wrapper used by the test agent, by CI and by humans.
#
# Why a wrapper:
#   * `terraform test` executes code that lives in the repository (for example
#     the `external` data source in modules/function-app runs a shell script).
#     A pull request can change that code, so Terraform must never see the
#     secrets of the process that launched it. The wrapper starts Terraform
#     with a minimal, explicit environment (`env -i`).
#   * The agent gets one fixed, auditable entry point instead of arbitrary
#     `terraform ...` invocations, which keeps the allowed-tools list short.
#   * Every caller (agent, CI, developer) runs Terraform with the same flags.
#
# Usage:
#   scripts/tf.sh init     <unit>
#   scripts/tf.sh fmt      <unit>            # check only, exits 3 on diff
#   scripts/tf.sh fmt-fix  <unit>            # rewrite files in place
#   scripts/tf.sh validate <unit>
#   scripts/tf.sh test     <unit> [-filter=tests/x.tftest.hcl] [-verbose] [-junit-xml=FILE]
#
# <unit> is a path relative to the repository root, e.g. modules/network or
# stacks/data-platform. It must stay inside the repository.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/tf.sh init     <unit>
  scripts/tf.sh fmt      <unit>            # check only, exits 3 on diff
  scripts/tf.sh fmt-fix  <unit>            # rewrite files in place
  scripts/tf.sh validate <unit>
  scripts/tf.sh test     <unit> [-filter=tests/x.tftest.hcl] [-verbose] [-junit-xml=FILE]

<unit> is a path relative to the repository root, e.g. modules/network.
EOF
}

die() {
  echo "tf.sh: $*" >&2
  exit 2
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

[[ $# -ge 2 ]] || { usage >&2; exit 2; }

cmd="$1"
unit="$2"
shift 2

case "$cmd" in
  init|fmt|fmt-fix|validate|test) ;;
  *) die "unknown command '$cmd'" ;;
esac

# --- Resolve and validate the unit path -------------------------------------
[[ "$unit" != /* ]] || die "unit must be a path relative to the repository root"
[[ "$unit" != *..* ]] || die "unit must not contain '..'"
unit="${unit%/}"
unit_dir="$REPO_ROOT/$unit"
[[ -d "$unit_dir" ]] || die "no such directory: $unit"
resolved="$(cd "$unit_dir" && pwd -P)"
[[ "$resolved" == "$REPO_ROOT/"* ]] || die "unit escapes the repository: $unit"
compgen -G "$unit_dir/*.tf" > /dev/null || die "no .tf files in $unit"

# --- Validate pass-through arguments ----------------------------------------
# Only a handful of flags are meaningful for `terraform test`; everything else
# is rejected so the wrapper cannot be used to run arbitrary Terraform options.
extra=()
for arg in "$@"; do
  case "$cmd:$arg" in
    test:-verbose) extra+=("$arg") ;;
    test:-filter=*) extra+=("$arg") ;;
    test:-junit-xml=*) extra+=("$arg") ;;
    *) die "argument '$arg' is not allowed for '$cmd'" ;;
  esac
done

# --- Minimal environment -----------------------------------------------------
# Keep PATH so the terraform binary is found, HOME for the CLI config dir and
# the plugin cache, and a few Terraform knobs. Nothing else is inherited:
# no cloud credentials, no API keys, no GitHub tokens.
clean_env=(
  "PATH=${PATH}"
  "HOME=${TF_WRAPPER_HOME:-${HOME:-/tmp}}"
  "TMPDIR=${TMPDIR:-/tmp}"
  "TF_IN_AUTOMATION=1"
  "TF_INPUT=0"
  "CHECKPOINT_DISABLE=1"
  "TF_CLI_ARGS=-no-color"
)
# Optional, non-secret variables that are passed through when set:
#   * plugin cache / CLI config so CI can reuse downloaded providers,
#   * proxy and CA settings so corporate and sandboxed networks keep working.
passthrough=(
  TF_PLUGIN_CACHE_DIR TF_CLI_CONFIG_FILE
  HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy
  SSL_CERT_FILE SSL_CERT_DIR
)
for name in "${passthrough[@]}"; do
  if [[ -n "${!name:-}" ]]; then
    clean_env+=("${name}=${!name}")
  fi
done

run_tf() {
  env -i "${clean_env[@]}" terraform -chdir="$unit_dir" "$@"
}

init_unit() {
  # -backend=false: no state backend, no credentials. The lock file, when it
  # exists, is honoured but never rewritten by callers of this wrapper.
  local lock_mode="readonly"
  [[ -f "$unit_dir/.terraform.lock.hcl" ]] || lock_mode="readonly-or-create"
  if [[ "$lock_mode" == "readonly" ]]; then
    run_tf init -backend=false -input=false -lockfile=readonly > /dev/null
  else
    run_tf init -backend=false -input=false > /dev/null
  fi
}

case "$cmd" in
  init)
    init_unit
    echo "initialised $unit"
    ;;
  fmt)
    # `fmt -check` exits 3 when files would change; `-recursive` covers tests/.
    run_tf fmt -check -diff -recursive
    ;;
  fmt-fix)
    run_tf fmt -recursive
    ;;
  validate)
    init_unit
    run_tf validate
    ;;
  test)
    init_unit
    run_tf test ${extra[@]+"${extra[@]}"}
    ;;
esac
