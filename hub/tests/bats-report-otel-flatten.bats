#!/usr/bin/env bats
# BTS-497 Step 13 — bats-report.sh invokes otel-flatten.sh post-run with
# AC-12d exit-code precedence:
#
#   parallel + flatten ok  + bats=0 → exit 0
#   parallel + flatten ok  + bats=1 → exit 1
#   parallel + flatten fail+ bats=0 → exit 78  (flatten wins)
#   parallel + flatten fail+ bats=1 → exit 78  (flatten wins)
#   no --parallel                   → flatten skipped, exit bats_rc
#
# Telemetry is disabled in setup so bats runs without needing a live
# Collector; OTEL_FLATTEN_INPUT is overridden to a fixture so flatten
# runs deterministically against known data.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/raw-traces-sample.jsonl"

setup() {
  STUB="$BATS_TEST_TMPDIR/stub.bats"
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bats
@test "pass one" { true; }
@test "pass two" { true; }
EOF

  STUB_FAIL="$BATS_TEST_TMPDIR/stub-fail.bats"
  cat > "$STUB_FAIL" <<'EOF'
#!/usr/bin/env bats
@test "deliberate fail" { false; }
EOF

  # Helper not sourced — disable telemetry so bats runs unconditionally.
  export CCANVIL_TELEMETRY_DISABLED=1
  export BATS_REPORT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export OTEL_FLATTEN_OUTPUT="$BATS_TEST_TMPDIR/test-runs.jsonl"

  # Skip the BTS-281 module-manifest pre-warm. Each bats-report.sh call would
  # otherwise spend ~7 min validating the full hub allowlist — irrelevant to
  # this test surface and would multiply by 6× invocations.
  local stub_cache="$BATS_TEST_TMPDIR/manifest-cache.json"
  echo '{"coverage":{"covered":0,"total":0},"drift":[],"status":"ok"}' > "$stub_cache"
  export BTS_MANIFEST_VALIDATE_CACHE="$stub_cache"
}

# =========================================================================
# Matrix: parallel × flatten outcome × bats outcome
# =========================================================================

@test "AC-12d: --parallel + flatten ok + bats=0 → exit 0" {
  # Fixture run-abc has 3 spans; override BTS_RUN_ID to match so flatten succeeds.
  BTS_RUN_ID=run-abc OTEL_FLATTEN_INPUT="$FIXTURE" \
    run bash "$SCRIPT" --parallel "$STUB"
  [ "$status" -eq 0 ]
}

@test "AC-12d: --parallel + flatten ok + bats=1 → exit 1 (bats_rc preserved)" {
  BTS_RUN_ID=run-abc OTEL_FLATTEN_INPUT="$FIXTURE" \
    run bash "$SCRIPT" --parallel "$STUB_FAIL"
  [ "$status" -eq 1 ]
  # bats_rc still visible in human stdout (PASS / FAIL summary).
  echo "$output" | grep -qE '^FAIL:|FAIL: 1'
}

@test "AC-12d: --parallel + flatten fail + bats=0 → exit 78 (flatten wins)" {
  # Non-existent run.id → flatten exits 78 (no spans for run.id).
  BTS_RUN_ID=does-not-exist OTEL_FLATTEN_INPUT="$FIXTURE" \
    run bash "$SCRIPT" --parallel "$STUB"
  [ "$status" -eq 78 ]
  # The flatten error message must reach stderr.
  echo "$output" | grep -qE 'no spans|ERROR'
}

@test "AC-12d: --parallel + flatten fail + bats=1 → exit 78 (flatten wins over bats_rc)" {
  BTS_RUN_ID=does-not-exist OTEL_FLATTEN_INPUT="$FIXTURE" \
    run bash "$SCRIPT" --parallel "$STUB_FAIL"
  [ "$status" -eq 78 ]
}

@test "AC-12d: no --parallel → flatten skipped, exit follows bats_rc only" {
  # Even with a bogus OTEL_FLATTEN_INPUT, single-file (non-parallel) mode
  # must not invoke flatten — exit must reflect bats_rc, not 78.
  BTS_RUN_ID=does-not-exist OTEL_FLATTEN_INPUT=/nonexistent.jsonl \
    run bash "$SCRIPT" "$STUB"
  [ "$status" -eq 0 ]
}

@test "AC-12d: bats_rc visible in bats-runs.jsonl envelope even on exit 78" {
  # When flatten fails and we propagate 78, the bats-runs.jsonl record
  # must still show the underlying raw_exit (bats's actual return).
  BTS_RUN_ID=does-not-exist OTEL_FLATTEN_INPUT="$FIXTURE" \
    run bash "$SCRIPT" --parallel "$STUB_FAIL"
  [ "$status" -eq 78 ]
  local jsonl="$BATS_REPORT_STATE_DIR/bats-runs.jsonl"
  [ -f "$jsonl" ]
  # Last entry should have raw_exit=1 (bats failed) regardless of overall exit.
  tail -n1 "$jsonl" | jq -e '.raw_exit == 1' >/dev/null
}
