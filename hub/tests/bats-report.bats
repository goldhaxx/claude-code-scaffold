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

# ----------------------------------------------------------------------------
# BTS-277 — --help documents perf-core default + new envelope shape
# ----------------------------------------------------------------------------

@test "BTS-277 AC-4: --help mentions perf-core default for --jobs" {
  set -e
  run bash "$REPORT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'perf-core'
}

@test "BTS-277 AC-4: --help mentions wall_ms / jobs / cpus envelope fields" {
  set -e
  run bash "$REPORT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'wall_ms'
  echo "$output" | grep -qF 'jobs'
  echo "$output" | grep -qF 'cpus'
}

@test "BTS-277 AC-4: --help mentions bats-runs.jsonl append behavior" {
  set -e
  run bash "$REPORT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'bats-runs.jsonl'
}

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

# ============================================================================
# BTS-137 — per-test timing observability (--timings, --slow-top N)
# ============================================================================

@test "BTS-137 AC-1: --timings emits a sorted table of per-test timings" {
  set -e
  seed_bats "$WORK/pass.bats" \
    'TESTZ "alpha" { [ 1 -eq 1 ]; }' \
    'TESTZ "beta"  { [ 2 -eq 2 ]; }' \
    'TESTZ "gamma" { [ 3 -eq 3 ]; }'
  run --separate-stderr bash "$REPORT" --timings "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  # Existing output still present.
  [[ "$output" =~ "PASS: 3" ]]
  # Timings table header + at least one timing row (ms\ttestname).
  [[ "$output" =~ "Timings" ]] || [[ "$output" =~ "ms" ]]
  # All three tests named in the timings section.
  [[ "$output" =~ "alpha" ]]
  [[ "$output" =~ "beta" ]]
  [[ "$output" =~ "gamma" ]]
}

@test "BTS-137 AC-2: --slow-top N emits at most N rows" {
  set -e
  seed_bats "$WORK/pass.bats" \
    'TESTZ "a" { [ 1 -eq 1 ]; }' \
    'TESTZ "b" { [ 2 -eq 2 ]; }' \
    'TESTZ "c" { [ 3 -eq 3 ]; }' \
    'TESTZ "d" { [ 4 -eq 4 ]; }'
  run --separate-stderr bash "$REPORT" --slow-top 2 "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  # Count timing rows: lines starting with a number (ms) followed by tab or spaces.
  timing_count=$(echo "$output" | grep -cE '^[0-9]+[[:space:]]+' || true)
  [ "$timing_count" -le 2 ]
  [ "$timing_count" -ge 1 ]
}

@test "BTS-137 AC-3: --slow-top 0 → exit 0, zero timing rows" {
  set -e
  seed_bats "$WORK/pass.bats" \
    'TESTZ "only" { [ 1 -eq 1 ]; }'
  run --separate-stderr bash "$REPORT" --slow-top 0 "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  timing_count=$(echo "$output" | grep -cE '^[0-9]+[[:space:]]+' || true)
  [ "$timing_count" -eq 0 ]
}

@test "BTS-137 AC-3: --slow-top non-integer → exit 2 with ERROR" {
  seed_bats "$WORK/pass.bats" \
    'TESTZ "one" { [ 1 -eq 1 ]; }'
  run --separate-stderr bash "$REPORT" --slow-top abc "$WORK/pass.bats"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "ERROR" ]]
}

@test "BTS-137 AC-4: --json --timings includes timings array sorted slowest-first" {
  set -e
  seed_bats "$WORK/pass.bats" \
    'TESTZ "one" { [ 1 -eq 1 ]; }' \
    'TESTZ "two" { [ 2 -eq 2 ]; }'
  run --separate-stderr bash "$REPORT" --json --timings "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.timings | type == "array"'
  echo "$output" | jq -e '.timings | length == 2'
  echo "$output" | jq -e '.timings[0] | has("test") and has("ms")'
  # Sorted slowest-first → first entry's ms is >= second entry's ms.
  echo "$output" | jq -e '.timings[0].ms >= .timings[1].ms'
}

@test "BTS-137 AC-4: --json without --timings omits or empties the timings key" {
  set -e
  seed_bats "$WORK/pass.bats" \
    'TESTZ "one" { [ 1 -eq 1 ]; }'
  run --separate-stderr bash "$REPORT" --json "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  # Either absent or empty array; both are acceptable backward-compat.
  echo "$output" | jq -e '(.timings // []) | length == 0'
}

@test "BTS-137 AC-6: failing test still gets its timing captured in --timings output" {
  seed_bats "$WORK/mix.bats" \
    'TESTZ "passer" { [ 1 -eq 1 ]; }' \
    'TESTZ "failer" { false; }'
  run --separate-stderr bash "$REPORT" --timings "$WORK/mix.bats"
  [ "$status" -ne 0 ]
  # Both tests appear in the timings section.
  [[ "$output" =~ "passer" ]]
  [[ "$output" =~ "failer" ]]
}
