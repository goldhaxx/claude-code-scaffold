#!/usr/bin/env bats
# BTS-497 Step 7 — AC-11: bats-report.sh --parallel surfaces the
# parallelization config in human stdout, immediately above the
# existing PASS / FAIL / TOTAL summary line.
#
# Closes the operator-flagged 2026-05-16 visibility gap — previously
# jobs/cpus/wall_ms only landed in --json mode and bats-runs.jsonl.

load _helpers/bats-report-stub

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"

# Minimal stub bats file: 2 trivial passing tests.
setup() {
  stub_bats_report_prewarm
  STUB="$BATS_TEST_TMPDIR/stub.bats"
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bats
@test "stub one" { true; }
@test "stub two" { true; }
EOF
  export BATS_REPORT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$BATS_REPORT_STATE_DIR"

  # BTS-497 Step 13: bats-report.sh now invokes otel-flatten.sh after every
  # --parallel run. AC-11 tests don't care about flatten — give it a
  # working path against the existing fixture so it succeeds and exits 0.
  # (Step 14 will land the --no-telemetry flag for a cleaner opt-out.)
  export BTS_RUN_ID=run-abc
  export OTEL_FLATTEN_INPUT="$BATS_TEST_DIRNAME/fixtures/raw-traces-sample.jsonl"
  export OTEL_FLATTEN_OUTPUT="$BATS_TEST_TMPDIR/test-runs.jsonl"
}

# =========================================================================
# AC-11: human-stdout config line under --parallel
# =========================================================================

@test "AC-11: --parallel human stdout contains 'parallel: jobs=N cpus=M wall=Ts' line" {
  run bash "$SCRIPT" --parallel "$STUB"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^parallel: jobs=[0-9]+ cpus=[0-9]+ wall=[0-9]+\.[0-9]+s$'
}

@test "AC-11: config line appears IMMEDIATELY above the 'PASS:' summary line" {
  run bash "$SCRIPT" --parallel "$STUB"
  [ "$status" -eq 0 ]
  # Extract just the config line and the line that follows it.
  # awk: when we hit the config line, print it + the next line.
  local pair
  pair=$(echo "$output" | awk '/^parallel: jobs=/ { print; getline; print }')
  echo "$pair" | head -1 | grep -qE '^parallel: jobs='
  echo "$pair" | tail -1 | grep -qE '^PASS: '
}

# =========================================================================
# AC-11: --json mode is unchanged (no `parallel:` line bleeding in)
# =========================================================================

@test "AC-11: --json mode emits valid JSON (no leading 'parallel:' line)" {
  run bash "$SCRIPT" --parallel --json "$STUB"
  [ "$status" -eq 0 ]
  # First non-empty line of output must parse as JSON.
  echo "$output" | jq -e '.' >/dev/null
  # Explicitly: no line beginning with 'parallel:' in JSON-mode output.
  ! echo "$output" | grep -qE '^parallel: '
}

# =========================================================================
# Negative case: non-parallel mode does NOT emit the config line
# (AC-11 phrasing scopes the line to the --parallel case)
# =========================================================================

@test "AC-11: non-parallel mode does NOT emit the 'parallel:' line" {
  run bash "$SCRIPT" "$STUB"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE '^parallel: jobs='
}
