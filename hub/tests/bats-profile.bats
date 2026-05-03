#!/usr/bin/env bats
# BTS-282 — bats-profile.sh: PATH-shim profiler for bats runs.

bats_require_minimum_version 1.5.0

PROFILE="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-profile.sh"

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
# AC-5: missing-target error path
# ----------------------------------------------------------------------------

@test "AC-5: missing bats target exits 2 with ERROR on stderr" {
  run --separate-stderr bash "$PROFILE" /no/such/path-${RANDOM}.bats
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "ERROR" ]]
  [[ "$stderr" =~ "not found" ]]
}

# ----------------------------------------------------------------------------
# AC-3: --top validation
# ----------------------------------------------------------------------------

@test "AC-3: --top 0 exits 2" {
  seed_bats "$WORK/x.bats" 'TESTZ "n" { :; }'
  run --separate-stderr bash "$PROFILE" --top 0 "$WORK/x.bats"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "ERROR" ]]
}

@test "AC-3: --top non-integer exits 2" {
  seed_bats "$WORK/x.bats" 'TESTZ "n" { :; }'
  run --separate-stderr bash "$PROFILE" --top abc "$WORK/x.bats"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "ERROR" ]]
}

# ----------------------------------------------------------------------------
# AC-4: --wrap target validation
# ----------------------------------------------------------------------------

@test "AC-4: --wrap with unresolvable script exits 2" {
  seed_bats "$WORK/x.bats" 'TESTZ "n" { :; }'
  run --separate-stderr bash "$PROFILE" --wrap nope-${RANDOM}.sh "$WORK/x.bats"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "not found" ]]
}

@test "AC-4: --wrap with default substrate scripts is accepted" {
  seed_bats "$WORK/x.bats" 'TESTZ "n" { :; }'
  run --separate-stderr bash "$PROFILE" --wrap docs-check.sh,module-manifest.sh "$WORK/x.bats"
  [ "$status" -eq 0 ]
}

# ----------------------------------------------------------------------------
# AC-1 + AC-2: passthrough fixture + JSON aggregation shape
# ----------------------------------------------------------------------------

FIXTURE="$BATS_TEST_DIRNAME/fixtures/bats-profile-passthrough.bats"

@test "AC-1: wrapped + unwrapped runs report identical exit code + ok/not-ok counts + tail-3" {
  set -e
  [ -f "$FIXTURE" ]

  # Direct (unwrapped) run via bats.
  run bats "$FIXTURE"
  direct_status=$status
  direct_output="$output"

  # Wrapped run via bats-profile.sh.
  run bash "$PROFILE" "$FIXTURE"
  wrapped_status=$status
  wrapped_output="$output"

  [ "$direct_status" -eq "$wrapped_status" ]

  # Pass/fail counts match.
  d_ok=$(echo "$direct_output" | grep -cE '^ok ' || true)
  w_ok=$(echo "$wrapped_output" | grep -cE '^ok ' || true)
  [ "$d_ok" = "$w_ok" ]
  d_not_ok=$(echo "$direct_output" | grep -cE '^not ok ' || true)
  w_not_ok=$(echo "$wrapped_output" | grep -cE '^not ok ' || true)
  [ "$d_not_ok" = "$w_not_ok" ]
}

@test "AC-2: --json output is an array of {cmd, verb, count, total_ms, mean_ms}" {
  set -e
  [ -f "$FIXTURE" ]
  run bash "$PROFILE" "$FIXTURE"
  [ "$status" -eq 0 ]
  # Last line of output is the JSON array (bats output precedes it).
  json=$(echo "$output" | awk '/^\[/{flag=1} flag' )
  echo "$json" | jq -e 'type == "array"'
  echo "$json" | jq -e 'all(has("cmd") and has("verb") and has("count") and has("total_ms") and has("mean_ms"))'
  # Sorted by total_ms desc.
  echo "$json" | jq -e '. as $a | ($a | length <= 1) or all(range(0; ($a|length)-1) as $i | $a[$i].total_ms >= $a[$i+1].total_ms)'
}

@test "AC-2: aggregation includes docs-check.sh row when fixture invokes it" {
  set -e
  [ -f "$FIXTURE" ]
  run bash "$PROFILE" "$FIXTURE"
  [ "$status" -eq 0 ]
  json=$(echo "$output" | awk '/^\[/{flag=1} flag' )
  echo "$json" | jq -e 'any(.cmd == "docs-check.sh")'
}

# ----------------------------------------------------------------------------
# AC-3: --top N caps row count
# ----------------------------------------------------------------------------

@test "AC-3: --top 1 caps row count to 1" {
  set -e
  [ -f "$FIXTURE" ]
  run bash "$PROFILE" --top 1 "$FIXTURE"
  [ "$status" -eq 0 ]
  json=$(echo "$output" | awk '/^\[/{flag=1} flag' )
  echo "$json" | jq -e 'length <= 1'
}
