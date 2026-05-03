#!/usr/bin/env bats
# BTS-277 — bats-report.sh JSON envelope gains wall_ms / jobs / cpus
# (AC-2) and appends each run to .ccanvil/state/bats-runs.jsonl (AC-3).

bats_require_minimum_version 1.5.0

REPORT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"

setup() {
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
# AC-2: wall_ms / jobs / cpus envelope fields
# ----------------------------------------------------------------------------

@test "AC-2: --json envelope contains wall_ms (integer >= 0)" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  BATS_REPORT_STATE_DIR="$WORK/state" \
  run --separate-stderr bash "$REPORT" --json "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.wall_ms | type == "number"'
  echo "$output" | jq -e '.wall_ms >= 0'
}

@test "AC-2: --json envelope contains cpus (integer >= 1)" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  BATS_REPORT_STATE_DIR="$WORK/state" \
  run --separate-stderr bash "$REPORT" --json "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.cpus | type == "number"'
  echo "$output" | jq -e '.cpus >= 1'
}

@test "AC-2: --json without --parallel reports jobs == 1" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  BATS_REPORT_STATE_DIR="$WORK/state" \
  run --separate-stderr bash "$REPORT" --json "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.jobs == 1'
}

@test "AC-2: --json --parallel reports jobs == perf-core override" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  BATS_REPORT_HAS_PARALLEL=1 \
  BATS_REPORT_PERF_CORES=12 \
  BATS_REPORT_STATE_DIR="$WORK/state" \
  run --separate-stderr bash "$REPORT" --json --parallel "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.jobs == 12'
}

@test "AC-2: existing envelope fields remain present and shaped" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  BATS_REPORT_STATE_DIR="$WORK/state" \
  run --separate-stderr bash "$REPORT" --json "$WORK/pass.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == 1'
  echo "$output" | jq -e '.not_ok == 0'
  echo "$output" | jq -e '.total == 1'
  echo "$output" | jq -e '.tail | type == "string"'
  echo "$output" | jq -e '.raw_exit == 0'
  echo "$output" | jq -e '.timings | type == "array"'
}

# ----------------------------------------------------------------------------
# AC-3: append to .ccanvil/state/bats-runs.jsonl
# ----------------------------------------------------------------------------

@test "AC-3: each run appends one entry to bats-runs.jsonl (delta == 2 over two runs)" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  state_dir="$WORK/state"
  jsonl="$state_dir/bats-runs.jsonl"
  # Pre-condition: file may or may not exist; treat absent as 0 lines.
  before=0
  [[ -f "$jsonl" ]] && before=$(wc -l < "$jsonl" | tr -d ' ')

  BATS_REPORT_STATE_DIR="$state_dir" bash "$REPORT" --json "$WORK/pass.bats" >/dev/null
  BATS_REPORT_STATE_DIR="$state_dir" bash "$REPORT" --json "$WORK/pass.bats" >/dev/null

  [ -f "$jsonl" ]
  after=$(wc -l < "$jsonl" | tr -d ' ')
  delta=$((after - before))
  [ "$delta" -eq 2 ]
}

@test "AC-3: jsonl entry has the documented shape" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  state_dir="$WORK/state"
  BATS_REPORT_STATE_DIR="$state_dir" bash "$REPORT" --json "$WORK/pass.bats" >/dev/null
  jsonl="$state_dir/bats-runs.jsonl"
  [ -f "$jsonl" ]
  line=$(tail -n 1 "$jsonl")
  echo "$line" | jq -e '.epoch | type == "number"'
  echo "$line" | jq -e '.wall_ms | type == "number"'
  echo "$line" | jq -e '.ok == 1'
  echo "$line" | jq -e '.not_ok == 0'
  echo "$line" | jq -e '.total == 1'
  echo "$line" | jq -e '.jobs | type == "number"'
  echo "$line" | jq -e '.cpus | type == "number"'
  echo "$line" | jq -e '.raw_exit == 0'
  echo "$line" | jq -e '.parallel | type == "boolean"'
}

@test "AC-3: parallel field reflects whether --parallel was passed" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  state_dir="$WORK/state"

  BATS_REPORT_STATE_DIR="$state_dir" bash "$REPORT" --json "$WORK/pass.bats" >/dev/null
  BATS_REPORT_HAS_PARALLEL=1 BATS_REPORT_PERF_CORES=4 BATS_REPORT_STATE_DIR="$state_dir" \
    bash "$REPORT" --json --parallel "$WORK/pass.bats" >/dev/null

  jsonl="$state_dir/bats-runs.jsonl"
  serial_line=$(sed -n '1p' "$jsonl")
  parallel_line=$(sed -n '2p' "$jsonl")
  echo "$serial_line" | jq -e '.parallel == false'
  echo "$parallel_line" | jq -e '.parallel == true'
  echo "$parallel_line" | jq -e '.jobs == 4'
}

@test "AC-3: epochs are monotonically non-decreasing across two runs" {
  set -e
  seed_bats "$WORK/pass.bats" 'TESTZ "one" { [ 1 -eq 1 ]; }'
  state_dir="$WORK/state"
  BATS_REPORT_STATE_DIR="$state_dir" bash "$REPORT" --json "$WORK/pass.bats" >/dev/null
  BATS_REPORT_STATE_DIR="$state_dir" bash "$REPORT" --json "$WORK/pass.bats" >/dev/null
  jsonl="$state_dir/bats-runs.jsonl"
  e1=$(sed -n '1p' "$jsonl" | jq -r '.epoch')
  e2=$(sed -n '2p' "$jsonl" | jq -r '.epoch')
  [ "$e2" -ge "$e1" ]
}
