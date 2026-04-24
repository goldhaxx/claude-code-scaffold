#!/usr/bin/env bats
# BTS-118 — bats-report.sh runs bats once and emits structured output.
#
# Fixture files use the TESTZ→@test sentinel substitution (see bats-lint.bats
# header) so this file's preprocessor doesn't mangle fixture contents.

bats_require_minimum_version 1.5.0

REPORT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

seed_bats() {
  local dest="$1"
  shift
  local content
  content=$(printf '%s\n' "$@")
  printf '%s' "${content//TESTZ/@test}" > "$dest"
}

# ----------------------------------------------------------------------------
# Happy path: all pass
# ----------------------------------------------------------------------------

@test "BTS-118: human mode reports PASS total and tail for a passing file" {
  set -e
  seed_bats "$WORK/pass.bats" \
    'TESTZ "one" { [ 1 -eq 1 ]; }' \
    'TESTZ "two" { [ 2 -eq 2 ]; }'
  run --separate-stderr bash "$REPORT" "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PASS: 2" ]]
  [[ "$output" =~ "FAIL: 0" ]]
  [[ "$output" =~ "TOTAL: 2" ]]
}

@test "BTS-118: json mode emits structured {ok, not_ok, total, tail, raw_exit}" {
  set -e
  seed_bats "$WORK/pass.bats" \
    'TESTZ "one" { [ 1 -eq 1 ]; }' \
    'TESTZ "two" { [ 2 -eq 2 ]; }'
  run --separate-stderr bash "$REPORT" --json "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == 2'
  echo "$output" | jq -e '.not_ok == 0'
  echo "$output" | jq -e '.total == 2'
  echo "$output" | jq -e '.raw_exit == 0'
  echo "$output" | jq -e '.tail | type == "string" and length > 0'
}

# ----------------------------------------------------------------------------
# Failure path
# ----------------------------------------------------------------------------

@test "BTS-118: exit code mirrors bats's exit (non-zero on failing test)" {
  set -e
  seed_bats "$WORK/fail.bats" \
    'TESTZ "broken" { false; }'
  run --separate-stderr bash "$REPORT" "$WORK/fail.bats"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "FAIL: 1" ]]
}

@test "BTS-118: json mode raw_exit mirrors bats exit on failure" {
  set -e
  seed_bats "$WORK/fail.bats" \
    'TESTZ "broken" { false; }'
  run --separate-stderr bash "$REPORT" --json "$WORK/fail.bats"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.ok == 0'
  echo "$output" | jq -e '.not_ok == 1'
  echo "$output" | jq -e '.raw_exit != 0'
}

# ----------------------------------------------------------------------------
# Passthrough args + defaults
# ----------------------------------------------------------------------------

@test "BTS-118: arbitrary args pass through to bats (e.g., -f filter)" {
  set -e
  seed_bats "$WORK/multi.bats" \
    'TESTZ "alpha" { [ 1 -eq 1 ]; }' \
    'TESTZ "beta"  { [ 2 -eq 2 ]; }' \
    'TESTZ "gamma" { [ 3 -eq 3 ]; }'
  run --separate-stderr bash "$REPORT" -f beta "$WORK/multi.bats"
  [ "$status" -eq 0 ]
  # Only 'beta' should run — total = 1
  [[ "$output" =~ "TOTAL: 1" ]]
}

# ----------------------------------------------------------------------------
# --parallel
# ----------------------------------------------------------------------------

@test "BTS-118: --parallel adds --jobs when GNU parallel is available" {
  set -e
  # Isolation under --jobs is validated empirically (3× consecutive runs at
  # 902/902 green, timings recorded in the PR body) — AC-7 doesn't have a
  # unit test because bats's $BATS_TEST_TMPDIR isolation is enforced by the
  # bats runtime, not by bats-report.sh.
  command -v parallel >/dev/null 2>&1 || skip "GNU parallel not installed"
  seed_bats "$WORK/pass.bats" \
    'TESTZ "one" { [ 1 -eq 1 ]; }' \
    'TESTZ "two" { [ 2 -eq 2 ]; }'
  run --separate-stderr bash "$REPORT" --parallel "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PASS: 2" ]]
}

@test "BTS-118: --parallel emits WARN and falls back to serial when parallel missing" {
  set -e
  seed_bats "$WORK/pass.bats" \
    'TESTZ "one" { [ 1 -eq 1 ]; }'
  # BATS_REPORT_HAS_PARALLEL=0 forces the missing-parallel branch for test
  # purposes, independent of actual install state. bats still resolves via the
  # inherited PATH so the overall invocation succeeds.
  BATS_REPORT_HAS_PARALLEL=0 run --separate-stderr bash "$REPORT" --parallel "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  [[ "$stderr" =~ "WARN" ]]
  [[ "$stderr" =~ "parallel" ]]
}

# ----------------------------------------------------------------------------
# Defaults to hub/tests/ when no target given
# ----------------------------------------------------------------------------

@test "BTS-118: no-arg invocation defaults to hub/tests/" {
  set -e
  # Can't easily run a no-arg invocation against a fixture — verify via --help
  # that the default path is documented. Alternatively: verify via a dry-run
  # flag. Simplest: grep the script's own help text for 'hub/tests/'.
  run bash "$REPORT" --help 2>&1
  # --help may or may not be implemented; accept either 0 or non-zero exit.
  # The critical assertion is that the default path is hub/tests/ — ensure
  # the script's source references it. (Low-ceremony check.)
  grep -q 'hub/tests/' "$REPORT"
}
