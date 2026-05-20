#!/usr/bin/env bats

# BTS-497 telemetry hooks.
source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"
setup_file()    { telemetry_setup_file; }
teardown_file() { telemetry_teardown_file; }
teardown()      { telemetry_teardown; }

# BTS-543 — unit tests for the generic otel-span.sh helper library.
#
# Every test exercises otel-span.sh in isolation: no live OTel Collector is
# required (AC-11). Tests that need the "live" emission path force it via the
# helper's own idempotency seam (OTEL_SPAN_INIT_DONE=1 + OTEL_SPAN_LIVE=1) and
# point OTEL_SPAN_CLI at a stub that records its argv.

OTEL_SPAN="$BATS_TEST_DIRNAME/../../.ccanvil/observability/otel-span.sh"

setup() {
  telemetry_setup
  source "$OTEL_SPAN"
}

# Install an otel-cli stub that records its argv (one arg per line), and force
# the helper into the "live" state without a real Collector.
_force_live_with_stub() {
  export OTEL_SPAN_STUB_OUT="$BATS_TEST_TMPDIR/otel-argv"
  : > "$OTEL_SPAN_STUB_OUT"
  cat > "$BATS_TEST_TMPDIR/otel-cli-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$OTEL_SPAN_STUB_OUT"
STUB
  chmod +x "$BATS_TEST_TMPDIR/otel-cli-stub"
  export OTEL_SPAN_CLI="$BATS_TEST_TMPDIR/otel-cli-stub"
  unset CCANVIL_TELEMETRY_DISABLED
  export OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1
  export OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318"
}

# --- AC-1: public surface --------------------------------------------------

@test "AC-1: sourcing otel-span.sh defines all public functions" {
  for fn in otel_span_init otel_span_cache_invariants otel_span_new_trace_id \
            otel_span_new_span_id otel_span_sanitize otel_span_emit otel_span_run; do
    declare -F "$fn" >/dev/null || { echo "missing function: $fn" >&2; return 1; }
  done
}

# --- AC-2: ID generation ---------------------------------------------------

@test "AC-2: otel_span_new_trace_id emits 32 lowercase hex chars" {
  run otel_span_new_trace_id
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{32}$ ]]
}

@test "AC-2: otel_span_new_span_id emits 16 lowercase hex chars" {
  run otel_span_new_span_id
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{16}$ ]]
}

@test "AC-2: ID generation works when openssl is absent (fallback path)" {
  export OTEL_SPAN_NO_OPENSSL=1
  run otel_span_new_trace_id
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{32}$ ]]
  run otel_span_new_span_id
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{16}$ ]]
}

# --- AC-3: attribute sanitization -----------------------------------------

@test "AC-3: otel_span_sanitize replaces commas with semicolons" {
  run otel_span_sanitize "a,b,c"
  [ "$status" -eq 0 ]
  [ "$output" = "a;b;c" ]
}

@test "AC-3: otel_span_sanitize leaves comma-free input unchanged" {
  run otel_span_sanitize "no commas here"
  [ "$status" -eq 0 ]
  [ "$output" = "no commas here" ]
}

# --- AC-4: disabled gate ---------------------------------------------------

@test "AC-4: otel_span_emit is a no-op returning 0 when telemetry disabled" {
  export CCANVIL_TELEMETRY_DISABLED=1
  export OTEL_SPAN_CLI="$BATS_TEST_TMPDIR/should-not-run"
  cat > "$OTEL_SPAN_CLI" <<'STUB'
#!/usr/bin/env bash
echo ran > "$BATS_TEST_TMPDIR/ran-marker"
STUB
  chmod +x "$OTEL_SPAN_CLI"
  run otel_span_emit --service s --name n --start 1 --end 2 --attrs "k=v"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/ran-marker" ]
}

@test "AC-4: otel_span_run still runs the wrapped command when disabled" {
  export CCANVIL_TELEMETRY_DISABLED=1
  run otel_span_run --service s --name n --category test -- bash -c 'echo ran; exit 7'
  [ "$status" -eq 7 ]
  [[ "$output" == *ran* ]]
}

# --- AC-5: graceful skip when the Collector is unreachable ----------------

@test "AC-5: otel_span_emit returns 0 when the Collector is unreachable" {
  unset CCANVIL_TELEMETRY_DISABLED OTEL_SPAN_INIT_DONE OTEL_SPAN_LIVE
  # A port with nothing listening — the healthcheck probe fails.
  export CCANVIL_TELEMETRY_URL="http://127.0.0.1:1"
  run otel_span_emit --service s --name n --start 1 --end 2 --attrs "k=v"
  [ "$status" -eq 0 ]
}

# --- AC-6: otel_span_run wrap + time --------------------------------------

@test "AC-6: otel_span_run returns the wrapped command exit code (success)" {
  _force_live_with_stub
  run otel_span_run --service s --name n --category test -- bash -c 'exit 0'
  [ "$status" -eq 0 ]
}

@test "AC-6: otel_span_run returns the wrapped command exit code (failure)" {
  _force_live_with_stub
  run otel_span_run --service s --name n --category test -- bash -c 'exit 42'
  [ "$status" -eq 42 ]
}

@test "AC-6: otel_span_run emits a span carrying duration_ms and exit.code" {
  _force_live_with_stub
  run otel_span_run --service ccanvil-script --name demo --category manifest -- bash -c 'exit 5'
  [ "$status" -eq 5 ]
  grep -q 'exit.code=5' "$OTEL_SPAN_STUB_OUT"
  grep -q 'duration_ms=' "$OTEL_SPAN_STUB_OUT"
  grep -q 'script.category=manifest' "$OTEL_SPAN_STUB_OUT"
}

# --- otel_span_emit argv shape --------------------------------------------

@test "otel_span_emit builds an otel-cli argv with the core flags + forced IDs" {
  _force_live_with_stub
  run otel_span_emit --service ccanvil-test --name suite --start 10 --end 20 \
    --status error --attrs "suite.kind=bats" \
    --trace-id aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --span-id bbbbbbbbbbbbbbbb
  [ "$status" -eq 0 ]
  grep -qx 'span' "$OTEL_SPAN_STUB_OUT"
  grep -qx 'ccanvil-test' "$OTEL_SPAN_STUB_OUT"
  grep -qx 'http://127.0.0.1:4318' "$OTEL_SPAN_STUB_OUT"
  grep -qx -- '--force-trace-id' "$OTEL_SPAN_STUB_OUT"
  grep -qx 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$OTEL_SPAN_STUB_OUT"
  grep -qx -- '--force-span-id' "$OTEL_SPAN_STUB_OUT"
}

# --- invariant caching -----------------------------------------------------

@test "otel_span_cache_invariants exports git.sha, project root, run.id" {
  unset OTEL_SPAN_GIT_SHA OTEL_SPAN_PROJECT_ROOT OTEL_SPAN_RUN_ID
  otel_span_cache_invariants
  [ -n "$OTEL_SPAN_GIT_SHA" ]
  [ -n "$OTEL_SPAN_PROJECT_ROOT" ]
  [ -n "$OTEL_SPAN_RUN_ID" ]
}
