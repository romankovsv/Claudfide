# Shared helpers for the bats suites in tests/scripts.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd -P)"
export REPO_ROOT

# Create a throw-away git repository that mimics the layout of this one
# (scripts/ copied, a few modules, one with tests) and `cd` into it.
make_fixture_repo() {
  FIXTURE="$(mktemp -d "${BATS_TEST_TMPDIR}/fixture.XXXXXX")"
  export FIXTURE
  mkdir -p "$FIXTURE/scripts" "$FIXTURE/modules/alpha/tests" "$FIXTURE/modules/beta" "$FIXTURE/stacks/platform"
  cp "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/scripts/*.json "$REPO_ROOT"/scripts/*.py "$FIXTURE/scripts/"
  cat > "$FIXTURE/modules/alpha/main.tf" <<'EOF'
resource "null_resource" "a" {}
EOF
  cat > "$FIXTURE/modules/alpha/variables.tf" <<'EOF'
variable "name" { type = string }
EOF
  cat > "$FIXTURE/modules/alpha/tests/main.tftest.hcl" <<'EOF'
run "a" { command = plan }
EOF
  cat > "$FIXTURE/modules/alpha/.terraform.lock.hcl" <<'EOF'
# lock
EOF
  cat > "$FIXTURE/modules/beta/main.tf" <<'EOF'
resource "null_resource" "b" {}
EOF
  cat > "$FIXTURE/stacks/platform/main.tf" <<'EOF'
module "alpha" { source = "../../modules/alpha" name = "x" }
EOF
  echo "# fixture" > "$FIXTURE/README.md"
  git -C "$FIXTURE" init -q -b main
  git -C "$FIXTURE" -c user.name=fixture -c user.email=f@x commit -q --allow-empty -m "root" > /dev/null
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" -c user.name=fixture -c user.email=f@x commit -qm "base" > /dev/null
  cd "$FIXTURE" || return 1
}

fixture_commit() {
  git add -A
  git -c user.name="${FIXTURE_AUTHOR:-fixture}" -c user.email=f@x commit -qm "$1" > /dev/null
}

# install_fake_terraform [units whose tests fail] [units whose fmt fails]
# Puts a fake `terraform` first on PATH. It logs every call (arguments and
# environment) to $FAKE_TF_LOG and behaves per the two space-separated lists.
install_fake_terraform() {
  local fail_units="${1:-}" fmt_fail_units="${2:-}"
  FAKE_BIN="$(mktemp -d "${BATS_TEST_TMPDIR}/fakebin.XXXXXX")"
  export FAKE_BIN
  export FAKE_TF_LOG="$FAKE_BIN/calls.log"
  cat > "$FAKE_BIN/terraform" <<EOF
#!/usr/bin/env bash
# fake terraform for tests
log="$FAKE_TF_LOG"
fail_units=" $fail_units "
fmt_fail_units=" $fmt_fail_units "
EOF
  cat >> "$FAKE_BIN/terraform" <<'EOF'
echo "ARGS: $*" >> "$log"
env | sort >> "$log"
chdir=""
for a in "$@"; do case "$a" in -chdir=*) chdir="${a#-chdir=}";; esac; done
unit="$(basename "$(dirname "$chdir")")/$(basename "$chdir")"
sub=""
for a in "$@"; do case "$a" in -chdir=*) ;; *) sub="$a"; break;; esac; done
case "$sub" in
  init) exit 0 ;;
  fmt)
    case "$fmt_fail_units" in *" $unit "*) echo "main.tf"; exit 3;; esac
    exit 0 ;;
  validate) echo "Success! The configuration is valid."; exit 0 ;;
  test)
    for a in "$@"; do case "$a" in -junit-xml=*) echo "<testsuites/>" > "${a#-junit-xml=}";; esac; done
    case "$fail_units" in *" $unit "*) echo "Failure! 1 passed, 1 failed."; exit 1;; esac
    echo "Success! 2 passed, 0 failed."; exit 0 ;;
  *) echo "fake terraform: unexpected $sub" >&2; exit 9 ;;
esac
EOF
  chmod +x "$FAKE_BIN/terraform"
  export PATH="$FAKE_BIN:$PATH"
}
