#!/usr/bin/env bats
#
# BTS-510 AC-4 — cmd_index error-path guards.
# Both mktemp calls (accumulator + final-write intermediate) must be
# explicitly guarded with distinct stderr identifiers and a non-zero
# exit on failure. PATH shim selectively fails one call signature at a
# time.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/module-manifest.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  # Minimal source-dir fixture so cmd_index has something to walk.
  mkdir -p .ccanvil/scripts
  cat > .ccanvil/scripts/seed.sh <<'EOF'
# @manifest
# purpose: trivial seed
# input: none
# output: stdout (none)
# output: exit-codes 0 ok
# anchor: BTS-510-test
seed() { :; }
EOF
}

_install_shim() {
  # $1 = FAIL_MODE: "accumulator" or "final"
  local fail_mode="$1"
  local shim_dir="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/mktemp" <<EOF
#!/bin/bash
# accumulator → bare mktemp (no args)
# final → mktemp <template> (one positional containing XXXXXX)
case "$fail_mode" in
  accumulator)
    if [[ \$# -eq 0 ]]; then
      echo "shim: accumulator-mktemp deliberately failing" >&2
      exit 1
    fi
    ;;
  final)
    if [[ \$# -ge 1 && "\$1" == *.XXXXXX ]]; then
      echo "shim: final-write-mktemp deliberately failing" >&2
      exit 1
    fi
    ;;
esac
exec /usr/bin/mktemp "\$@"
EOF
  chmod +x "$shim_dir/mktemp"
  echo "$shim_dir"
}

@test "AC-4: accumulator mktemp failure → non-zero exit + accumulator stderr identifier" {
  shim_dir=$(_install_shim accumulator)
  run env PATH="$shim_dir:$PATH" bash "$SCRIPT" index
  [ "$status" -ne 0 ]
  [[ "$output" == *"accumulator-mktemp-failed"* ]] \
    || { echo "expected stderr to contain 'accumulator-mktemp-failed', got:" >&2; echo "$output" >&2; return 1; }
}

@test "AC-4: final-write mktemp failure → non-zero exit + final-write stderr identifier" {
  shim_dir=$(_install_shim final)
  run env PATH="$shim_dir:$PATH" bash "$SCRIPT" index
  [ "$status" -ne 0 ]
  [[ "$output" == *"final-write-mktemp-failed"* ]] \
    || { echo "expected stderr to contain 'final-write-mktemp-failed', got:" >&2; echo "$output" >&2; return 1; }
}

@test "AC-4 (success path regression): both mktemp calls succeed → cmd_index exits 0" {
  run bash "$SCRIPT" index
  [ "$status" -eq 0 ]
}
