#!/usr/bin/env bats

# BTS-497 telemetry hooks.
source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"
setup_file()    { telemetry_setup_file; }
teardown_file() { telemetry_teardown_file; }
teardown()      { telemetry_teardown; }
# BTS-497 Step 11 — bats telemetry helper foundation.
#
# Helper file: hub/tests/_helpers/telemetry.bash
# Public functions tested here:
#   telemetry_setup_file    (AC-2 healthcheck, AC-5 otel-cli check, span server)
#   telemetry_teardown_file (cleanup)
#
# Attribute resolution + per-test emission tests live in Step 12.
# Live span round-trip lives in Step 12.

HELPER="$BATS_TEST_DIRNAME/_helpers/telemetry.bash"

setup() {
  [ -f "$HELPER" ] || skip "telemetry helper not yet created"
  # Isolate BATS_FILE_TMPDIR — bats normally sets it but a sub-bats invocation
  # gets its own; here we use a fresh dir per test.
  export BATS_FILE_TMPDIR="$BATS_TEST_TMPDIR/file"
  mkdir -p "$BATS_FILE_TMPDIR"
  telemetry_setup
}

# =========================================================================
# Disabled-mode no-op (substrate self-tests via --no-telemetry)
# =========================================================================

@test "AC-7: CCANVIL_TELEMETRY_DISABLED=1 → setup_file is a no-op (returns 0)" {
  # The disabled flag must short-circuit before any curl/otel-cli probe.
  # PATH state is irrelevant to the assertion (helper must return 0
  # regardless of whether tools are present), so don't shadow it.
  CCANVIL_TELEMETRY_DISABLED=1 run bash -c "source '$HELPER' && telemetry_setup_file"
  [ "$status" -eq 0 ]
}

# =========================================================================
# AC-5 — otel-cli missing → exit non-zero + actionable message
# =========================================================================

@test "AC-5: missing otel-cli → setup_file exits non-zero + names install command" {
  # The helper short-circuits when CCANVIL_TELEMETRY_DISABLED is set
  # (its --no-telemetry escape hatch), bypassing the otel-cli check this
  # test asserts. Skip when running under --no-telemetry / DISABLED so the
  # test stays meaningful in the mode where the assertion can fire.
  [ -n "${CCANVIL_TELEMETRY_DISABLED:-}" ] && skip "incompatible with --no-telemetry (helper short-circuits before otel-cli check)"
  # PATH inside the bash subshell is shadowed so `command -v otel-cli`
  # fails. /bin/bash via absolute path so the subshell is reachable
  # regardless of outer PATH state. Unset DISABLED in the subshell since
  # the production behavior we're testing is the active-mode error path.
  run /bin/bash -c "unset CCANVIL_TELEMETRY_DISABLED; PATH=/nonexistent; source '$HELPER' && telemetry_setup_file"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'otel-cli'
  echo "$output" | grep -qE 'brew install.*otel-cli'
}

# =========================================================================
# AC-2 — unreachable Collector → setup_file exits non-zero
# =========================================================================

@test "AC-2: unreachable Collector → setup_file exits non-zero + names start command" {
  # Same rationale as AC-5: helper short-circuits under DISABLED.
  [ -n "${CCANVIL_TELEMETRY_DISABLED:-}" ] && skip "incompatible with --no-telemetry (helper short-circuits before Collector check)"
  # Point at a port that's certainly closed. Unset DISABLED in subshell.
  run bash -c "unset CCANVIL_TELEMETRY_DISABLED; CCANVIL_TELEMETRY_URL=http://127.0.0.1:1; source '$HELPER' && telemetry_setup_file"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'Collector|healthcheck'
  echo "$output" | grep -qE 'docker compose'
}

# =========================================================================
# Public-surface assertions: functions defined, attribute env vars exported
# =========================================================================

@test "AC-7: helper defines telemetry_setup_file + telemetry_teardown_file + telemetry_setup + telemetry_teardown" {
  source "$HELPER"
  declare -F telemetry_setup_file >/dev/null
  declare -F telemetry_teardown_file >/dev/null
  declare -F telemetry_setup >/dev/null
  declare -F telemetry_teardown >/dev/null
}

# =========================================================================
# Idempotent disable: teardown is also a no-op under DISABLED
# =========================================================================

@test "AC-7: CCANVIL_TELEMETRY_DISABLED=1 → teardown_file is a no-op (returns 0)" {
  CCANVIL_TELEMETRY_DISABLED=1 run bash -c "source '$HELPER' && telemetry_teardown_file"
  [ "$status" -eq 0 ]
}

# =========================================================================
# BTS-504 follow-up: otel-cli invoked with --start/--end so span timeline
# reflects actual test wall time (was point-in-time → all spans <1ms).
# =========================================================================

@test "BTS-504 follow-up: telemetry_teardown invokes otel-cli with --start AND --end (non-zero duration)" {
  [ -n "${CCANVIL_TELEMETRY_DISABLED:-}" ] && skip "incompatible with --no-telemetry"
  # Shim otel-cli to log its args, exit 0 without contacting any endpoint.
  local shim_dir="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/otel-cli" <<'SHIM'
#!/bin/bash
echo "$@" > "${BATS_TEST_TMPDIR}/otel-cli.argv"
exit 0
SHIM
  chmod +x "$shim_dir/otel-cli"
  # Run telemetry_setup + 100ms sleep + telemetry_teardown in a subshell.
  PATH="$shim_dir:$PATH" \
  BATS_TEST_DESCRIPTION="regression: span has measurable duration" \
  BATS_TEST_COMPLETED=1 \
  BATS_TEST_FILENAME="$BATS_TEST_DIRNAME/telemetry-helper.bats" \
  bash -c "source '$HELPER' && telemetry_setup && sleep 0.1 && telemetry_teardown"
  # Verify shim was called AND captured --start/--end with a measurable delta.
  [ -f "$BATS_TEST_TMPDIR/otel-cli.argv" ]
  local argv; argv=$(cat "$BATS_TEST_TMPDIR/otel-cli.argv")
  echo "$argv" | grep -qE -- '--start'
  echo "$argv" | grep -qE -- '--end'
  # Extract start/end epochs; compute delta in milliseconds.
  local start end
  start=$(echo "$argv" | awk -F '--start ' '{print $2}' | awk '{print $1}')
  end=$(echo "$argv"   | awk -F '--end '   '{print $2}' | awk '{print $1}')
  # Use awk for floating-point arithmetic — bash arithmetic can't do floats.
  local delta_ms
  delta_ms=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%d", (e - s) * 1000 }')
  # Sleep 0.1s + overhead → expect delta_ms >= 80 (allow some slack for
  # CI / shim startup variance).
  [ "$delta_ms" -ge 80 ] \
    || { echo "delta_ms=$delta_ms (expected >=80); argv=$argv" >&2; return 1; }
}

# =========================================================================
# Step 12 — attribute resolution (no live deps)
# =========================================================================

@test "AC-6: single-file mode (PARALLEL_JOBSLOT unset) → worker.id=0" {
  source "$HELPER"
  unset PARALLEL_JOBSLOT
  _telemetry_cache_invariants
  [ "$BTS_TELEMETRY_WORKER_ID" = "0" ]
}

@test "AC-1: parallel mode → worker.id reflects PARALLEL_JOBSLOT" {
  source "$HELPER"
  PARALLEL_JOBSLOT=7 _telemetry_cache_invariants
  [ "$BTS_TELEMETRY_WORKER_ID" = "7" ]
}

@test "AC-1: run.id format is <epoch>-<pid> when BTS_RUN_ID unset" {
  source "$HELPER"
  unset BTS_RUN_ID
  _telemetry_cache_invariants
  echo "$BTS_TELEMETRY_RUN_ID" | grep -qE '^[0-9]+-[0-9]+$'
}

@test "AC-1: BTS_RUN_ID inheritance — shared run.id across files" {
  source "$HELPER"
  BTS_RUN_ID="custom-suite-id" _telemetry_cache_invariants
  [ "$BTS_TELEMETRY_RUN_ID" = "custom-suite-id" ]
}

@test "AC-1: git.sha resolves to current HEAD (or 'unknown' outside git tree)" {
  source "$HELPER"
  _telemetry_cache_invariants
  echo "$BTS_TELEMETRY_GIT_SHA" | grep -qE '^([0-9a-f]{40}|unknown)$'
}

# =========================================================================
# Step 12 — attribute composition shape (AC-1 + AC-10 schema mirror)
# =========================================================================

@test "AC-1: compose_attrs builds the full 8-attribute set on pass (no error_excerpt)" {
  source "$HELPER"
  _telemetry_cache_invariants
  export BATS_TEST_DESCRIPTION="my test name"
  export BATS_TEST_FILENAME="$PWD/hub/tests/example.bats"
  local attrs
  attrs=$(_telemetry_compose_attrs "pass" "47" "")
  echo "$attrs" | grep -qE 'test\.name=my test name'
  echo "$attrs" | grep -qE 'test\.file=hub/tests/example\.bats'
  echo "$attrs" | grep -qE 'test\.outcome=pass'
  echo "$attrs" | grep -qE 'worker\.id=[0-9]+'
  echo "$attrs" | grep -qE 'runner\.kind=bats'
  echo "$attrs" | grep -qE 'run\.id='
  echo "$attrs" | grep -qE 'git\.sha='
  echo "$attrs" | grep -qE 'test\.duration_ms=47'
  # No error_excerpt on pass
  ! echo "$attrs" | grep -qE 'test\.error_excerpt='
}

@test "AC-1: compose_attrs includes test.error_excerpt on fail (truncated, commas→semicolons)" {
  source "$HELPER"
  _telemetry_cache_invariants
  export BATS_TEST_DESCRIPTION="fail test"
  export BATS_TEST_FILENAME="$PWD/hub/tests/example.bats"
  local attrs
  attrs=$(_telemetry_compose_attrs "fail" "100" "boom: expected 1, got 2")
  echo "$attrs" | grep -qE 'test\.outcome=fail'
  echo "$attrs" | grep -qE 'test\.error_excerpt=boom: expected 1; got 2'
}

@test "AC-1: compose_attrs preserves test.outcome=skip" {
  source "$HELPER"
  _telemetry_cache_invariants
  export BATS_TEST_DESCRIPTION="skipped test"
  export BATS_TEST_FILENAME="$PWD/hub/tests/example.bats"
  local attrs
  attrs=$(_telemetry_compose_attrs "skip" "5" "")
  echo "$attrs" | grep -qE 'test\.outcome=skip'
}

@test "AC-1: comma-in-test-name sanitized to semicolon (otel-cli --attrs delimiter)" {
  # Real bats test names frequently include commas — e.g.,
  # `AC-1: every state has {id, description}`. Without sanitization,
  # otel-cli treats the comma as an attribute separator and the span
  # drops silently.
  source "$HELPER"
  _telemetry_cache_invariants
  export BATS_TEST_DESCRIPTION="AC-1: legal_next_actions entries have {action, command, reason}"
  export BATS_TEST_FILENAME="$PWD/hub/tests/example.bats"
  local attrs
  attrs=$(_telemetry_compose_attrs "pass" "10" "")
  # The test.name must contain semicolons, not commas.
  echo "$attrs" | grep -qE 'test\.name=AC-1: legal_next_actions entries have \{action; command; reason\}'
  # And the only commas should be the inter-attribute separators (8 fixed
  # attrs + 0 optional = 7 separators).
  local comma_count
  comma_count=$(echo "$attrs" | tr -cd ',' | wc -c | tr -d ' ')
  [ "$comma_count" -eq 7 ]
}
