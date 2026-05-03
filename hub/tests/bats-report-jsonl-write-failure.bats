#!/usr/bin/env bats
# BTS-277 — bats-report.sh emits a WARN to stderr when the jsonl append
# can't be written, without flipping the exit code.

bats_require_minimum_version 1.5.0

REPORT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"

setup() {
  WORK=$(mktemp -d)
}

teardown() {
  # Restore write permissions so cleanup doesn't fail.
  if [[ -d "$WORK/state" ]]; then
    chmod -R u+w "$WORK/state" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}

seed_bats() {
  local dest="$1"
  shift
  local content
  content=$(printf '%s\n' "$@")
  printf '%s' "${content//TESTZ/@test}" > "$dest"
}

@test "AC-5: unwritable state-dir prints WARN to stderr but does not fail the run" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  mkdir -p "$WORK/state"
  chmod -w "$WORK/state"

  BATS_REPORT_STATE_DIR="$WORK/state" \
  run --separate-stderr bash "$REPORT" --json "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  # stderr carries the warn; stdout still emits the JSON envelope.
  [[ "$stderr" =~ "WARN: bats-runs.jsonl append skipped" ]]
  echo "$output" | jq -e '.ok == 1'
  echo "$output" | jq -e '.total == 1'
}

@test "AC-5: WARN does not flip exit code on failing-suite path either" {
  seed_bats "$WORK/fail.bats" 'TESTZ "boom" { [ 1 -eq 0 ]; }'
  mkdir -p "$WORK/state"
  chmod -w "$WORK/state"

  BATS_REPORT_STATE_DIR="$WORK/state" \
  run --separate-stderr bash "$REPORT" --json "$WORK/fail.bats"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "WARN: bats-runs.jsonl append skipped" ]]
  # Suite failure mirrored — not the WARN substituting.
  echo "$output" | jq -e '.not_ok == 1'
  echo "$output" | jq -e '.raw_exit != 0'
}
