#!/usr/bin/env bats
# BTS-497 Step 14 — --no-telemetry escape hatch on bats-report.sh.
#
# Purpose: substrate self-tests (and any caller that wants the bats suite
# to run without the OTel stack) can opt out cleanly via a single flag.
# Effect: (a) sets CCANVIL_TELEMETRY_DISABLED=1 so the bats helper no-ops
# per-test emission; (b) skips the post-run flatten step entirely so a
# missing/empty raw-traces.jsonl does NOT propagate exit 78.

load _helpers/bats-report-stub

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"

setup() {
  stub_bats_report_prewarm
  STUB="$BATS_TEST_TMPDIR/stub.bats"
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bats
@test "pass one" { true; }
@test "pass two" { true; }
EOF
  export BATS_REPORT_STATE_DIR="$BATS_TEST_TMPDIR/state"
}

# =========================================================================
# --no-telemetry skips flatten even when input is missing
# =========================================================================

@test "Step-14: --no-telemetry + --parallel + missing raw-traces.jsonl → exit 0 (flatten skipped)" {
  # Without --no-telemetry, this would exit 78 (flatten failure on missing input).
  OTEL_FLATTEN_INPUT=/nonexistent.jsonl run bash "$SCRIPT" --no-telemetry --parallel "$STUB"
  [ "$status" -eq 0 ]
  # Confirm normal stdout shape preserved (PASS line present).
  echo "$output" | grep -qE '^PASS: '
}

@test "Step-14: --no-telemetry sets CCANVIL_TELEMETRY_DISABLED for child bats (helper no-op)" {
  # If the helper were active, it would try to curl the Collector and fail.
  # Under --no-telemetry the helper short-circuits → bats runs cleanly.
  run bash "$SCRIPT" --no-telemetry --parallel "$STUB"
  [ "$status" -eq 0 ]
}

@test "Step-14: --no-telemetry tolerated in non-parallel mode (no-op since no flatten anyway)" {
  run bash "$SCRIPT" --no-telemetry "$STUB"
  [ "$status" -eq 0 ]
}

@test "Step-14: --no-telemetry composes with other flags (--parallel --json)" {
  run bash "$SCRIPT" --no-telemetry --parallel --json "$STUB"
  [ "$status" -eq 0 ]
  # JSON envelope must still emit cleanly.
  echo "$output" | jq -e '.' >/dev/null
}

# =========================================================================
# Negative: without --no-telemetry, missing raw-traces.jsonl exits 78
# =========================================================================

@test "Step-14: WITHOUT --no-telemetry, missing raw-traces propagates 78 (regression guard)" {
  OTEL_FLATTEN_INPUT=/nonexistent.jsonl run bash "$SCRIPT" --parallel "$STUB"
  [ "$status" -eq 78 ]
}
