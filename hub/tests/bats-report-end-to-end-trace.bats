#!/usr/bin/env bats

# BTS-560 — test-suite-run end-to-end trace.
#
# bats-report.sh emits ONE rooted OpenTelemetry trace per run: a `test-suite-run`
# root span with `manifest pre-warm`, `bats suite`, and `otel-flatten` phase
# spans beneath it.
#
# These tests mutate OTEL_SPAN_* / BTS_TELEMETRY_* env, so this file's OWN suite
# telemetry is force-disabled (same guard as otel-span.bats).
source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"
setup_file()    { CCANVIL_TELEMETRY_DISABLED=1 telemetry_setup_file; }
teardown_file() { CCANVIL_TELEMETRY_DISABLED=1 telemetry_teardown_file; }
teardown()      { CCANVIL_TELEMETRY_DISABLED=1 telemetry_teardown; }

load _helpers/bats-report-stub

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"
TELEMETRY_HELPER="$BATS_TEST_DIRNAME/_helpers/telemetry.bash"

# Fixed IDs so span-linkage assertions are exact-match.
TRACE_ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SUITE_SPAN_ID="bbbbbbbbbbbbbbbb"
RUN_SPAN_ID="cccccccccccccccc"

setup() {
  CCANVIL_TELEMETRY_DISABLED=1 telemetry_setup
  stub_bats_report_prewarm
  # Recording-stub otel-cli: one TAB-joined line per invocation.
  export OTEL_SPAN_STUB_OUT="$BATS_TEST_TMPDIR/otel-argv"
  : > "$OTEL_SPAN_STUB_OUT"
  cat > "$BATS_TEST_TMPDIR/otel-cli-stub" <<'STUB'
#!/usr/bin/env bash
{ for __a in "$@"; do printf '%s\t' "$__a"; done; printf '\n'; } >> "$OTEL_SPAN_STUB_OUT"
STUB
  chmod +x "$BATS_TEST_TMPDIR/otel-cli-stub"
  # Trivial (un-instrumented) stub suite.
  STUB_BATS="$BATS_TEST_TMPDIR/stub.bats"
  cat > "$STUB_BATS" <<'EOF'
#!/usr/bin/env bats
@test "pass one" { true; }
EOF
  export BATS_REPORT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # Keep the otel-flatten post-step off real state: a missing input makes it
  # fail fast (harmless), output goes to a temp path. The otel-flatten SPAN
  # still emits regardless of flatten success.
  export OTEL_FLATTEN_INPUT="$BATS_TEST_TMPDIR/no-such-raw-traces.jsonl"
  export OTEL_FLATTEN_OUTPUT="$BATS_TEST_TMPDIR/test-runs.jsonl"
}

# Run bats-report.sh with the recording stub forced live. $@ → bats-report.sh args.
_run_instrumented() {
  run env \
    OTEL_SPAN_CLI="$BATS_TEST_TMPDIR/otel-cli-stub" \
    OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
    OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
    OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
    BTS_RUN_ID="run-bts560" \
    BTS_TELEMETRY_TRACE_ID="$TRACE_ID" \
    BTS_TELEMETRY_SUITE_SPAN_ID="$SUITE_SPAN_ID" \
    BTS_TELEMETRY_RUN_SPAN_ID="$RUN_SPAN_ID" \
    BATS_REPORT_STATE_DIR="$BATS_REPORT_STATE_DIR" \
    bash "$SCRIPT" "$@"
}

# Echo the recorded otel-cli invocation line whose --name value equals $1.
_span_line() {
  grep -F -- "$(printf '\t--name\t%s\t' "$1")" "$OTEL_SPAN_STUB_OUT" | head -n1
}

# Echo the value following --<flag> on a TAB-joined argv line. Empty if absent.
_flag_val() {
  printf '%s' "$1" | awk -F'\t' -v f="$2" \
    '{for(i=1;i<NF;i++) if($i==f){print $(i+1); exit}}'
}

# =========================================================================
# AC-1 — the test-suite-run root span
# =========================================================================

@test "AC-1: emits one test-suite-run root span — ccanvil-test, traced, no parent" {
  _run_instrumented "$STUB_BATS"
  [ "$status" -eq 0 ]
  local line
  line=$(_span_line "test-suite-run")
  [ -n "$line" ]
  [ "$(_flag_val "$line" --service)" = "ccanvil-test" ]
  [ "$(_flag_val "$line" --force-trace-id)" = "$TRACE_ID" ]
  [ "$(_flag_val "$line" --force-span-id)" = "$RUN_SPAN_ID" ]
  # Root span — no parent.
  [ -z "$(_flag_val "$line" --force-parent-span-id)" ]
}

# =========================================================================
# AC-4 — the bats suite span re-parents under the root
# =========================================================================

@test "AC-4: bats suite span sets parent = root span id; keeps its own span id" {
  _run_instrumented "$STUB_BATS"
  [ "$status" -eq 0 ]
  local line
  line=$(_span_line "bats suite (run-bts560)")
  [ -n "$line" ]
  [ "$(_flag_val "$line" --force-parent-span-id)" = "$RUN_SPAN_ID" ]
  [ "$(_flag_val "$line" --force-span-id)" = "$SUITE_SPAN_ID" ]
}

# =========================================================================
# AC-7 — file spans still nest under the bats suite span
# =========================================================================

@test "AC-7: file spans still set parent = the bats suite span id" {
  local wired="$BATS_TEST_TMPDIR/wired.bats"
  cat > "$wired" <<EOF
#!/usr/bin/env bats
source "$TELEMETRY_HELPER"
setup_file()    { telemetry_setup_file; }
teardown_file() { telemetry_teardown_file; }
teardown()      { telemetry_teardown; }
@test "wired pass" { true; }
EOF
  _run_instrumented "$wired"
  [ "$status" -eq 0 ]
  local line
  line=$(_span_line "file: wired.bats")
  [ -n "$line" ]
  [ "$(_flag_val "$line" --force-parent-span-id)" = "$SUITE_SPAN_ID" ]
  [ "$(_flag_val "$line" --force-trace-id)" = "$TRACE_ID" ]
}

# =========================================================================
# AC-3 — the manifest pre-warm phase span
# =========================================================================

@test "AC-3: manifest pre-warm is a span parented under the root" {
  # The pre-warm runs `.ccanvil/scripts/module-manifest.sh validate` (CWD-relative).
  # Run bats-report.sh from a temp project dir with a fast stub so the pre-warm
  # block executes quickly; BTS_MANIFEST_VALIDATE_CACHE is unset so it fires.
  local proj="$BATS_TEST_TMPDIR/prewarm-proj"
  mkdir -p "$proj/.ccanvil/scripts"
  cat > "$proj/.ccanvil/scripts/module-manifest.sh" <<'MM'
#!/usr/bin/env bash
echo '{"coverage":{"covered":0,"total":0},"drift":[],"status":"ok"}'
MM
  chmod +x "$proj/.ccanvil/scripts/module-manifest.sh"
  run env -u BTS_MANIFEST_VALIDATE_CACHE \
    OTEL_SPAN_CLI="$BATS_TEST_TMPDIR/otel-cli-stub" \
    OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
    OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
    OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
    BTS_RUN_ID="run-bts560" \
    BTS_TELEMETRY_TRACE_ID="$TRACE_ID" \
    BTS_TELEMETRY_SUITE_SPAN_ID="$SUITE_SPAN_ID" \
    BTS_TELEMETRY_RUN_SPAN_ID="$RUN_SPAN_ID" \
    BATS_REPORT_STATE_DIR="$BATS_REPORT_STATE_DIR" \
    bash -c 'cd "$1" || exit 1; shift; exec bash "$@"' _ "$proj" "$SCRIPT" "$STUB_BATS"
  [ "$status" -eq 0 ]
  local line
  line=$(_span_line "manifest pre-warm")
  [ -n "$line" ]
  [ "$(_flag_val "$line" --force-parent-span-id)" = "$RUN_SPAN_ID" ]
  [ "$(_flag_val "$line" --force-trace-id)" = "$TRACE_ID" ]
}

# =========================================================================
# AC-5 — the otel-flatten phase span (parallel mode only)
# =========================================================================

@test "AC-5: parallel run emits an otel-flatten span parented under the root" {
  # No exit-code assertion: the harness points OTEL_FLATTEN_INPUT at a
  # nonexistent file, so flatten fails and the script exits 78. AC-5 is about
  # the span emitting, not flatten success — assert only the span.
  _run_instrumented --parallel "$STUB_BATS"
  local line
  line=$(_span_line "otel-flatten")
  [ -n "$line" ]
  [ "$(_flag_val "$line" --force-parent-span-id)" = "$RUN_SPAN_ID" ]
  [ "$(_flag_val "$line" --force-trace-id)" = "$TRACE_ID" ]
}

@test "AC-5: serial run emits no otel-flatten span" {
  _run_instrumented "$STUB_BATS"
  [ "$status" -eq 0 ]
  [ -z "$(_span_line "otel-flatten")" ]
}

# Run bats-report.sh so ALL phases fire — pre-warm (temp proj with a fast
# module-manifest.sh stub), bats suite, and the otel-flatten step (--parallel).
# $1 — optional bats target (defaults to the bare stub suite).
_run_full_run() {
  local proj="$BATS_TEST_TMPDIR/full-proj"
  mkdir -p "$proj/.ccanvil/scripts"
  cat > "$proj/.ccanvil/scripts/module-manifest.sh" <<'MM'
#!/usr/bin/env bash
echo '{"coverage":{"covered":0,"total":0},"drift":[],"status":"ok"}'
MM
  chmod +x "$proj/.ccanvil/scripts/module-manifest.sh"
  run env -u BTS_MANIFEST_VALIDATE_CACHE \
    OTEL_SPAN_CLI="$BATS_TEST_TMPDIR/otel-cli-stub" \
    OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
    OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
    OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
    BTS_RUN_ID="run-bts560" \
    BTS_TELEMETRY_TRACE_ID="$TRACE_ID" \
    BTS_TELEMETRY_SUITE_SPAN_ID="$SUITE_SPAN_ID" \
    BTS_TELEMETRY_RUN_SPAN_ID="$RUN_SPAN_ID" \
    BATS_REPORT_STATE_DIR="$BATS_REPORT_STATE_DIR" \
    bash -c 'cd "$1" || exit 1; shift; exec bash "$@"' _ "$proj" "$SCRIPT" --parallel "${1:-$STUB_BATS}"
}

# =========================================================================
# AC-2 / AC-6 — cross-cutting: root covers every phase; one trace
# =========================================================================

@test "AC-2: the root span's window covers every phase span" {
  _run_full_run
  local root prewarm suite flatten
  root=$(_span_line "test-suite-run")
  prewarm=$(_span_line "manifest pre-warm")
  suite=$(_span_line "bats suite (run-bts560)")
  flatten=$(_span_line "otel-flatten")
  [ -n "$root" ]
  [ -n "$prewarm" ]
  [ -n "$suite" ]
  [ -n "$flatten" ]
  local root_start root_end
  root_start=$(_flag_val "$root" --start)
  root_end=$(_flag_val "$root" --end)
  # root.start is at or before every phase start — pre-warm AND the bats suite.
  awk -v a="$root_start" -v b="$(_flag_val "$prewarm" --start)" 'BEGIN{exit !(a<=b)}'
  awk -v a="$root_start" -v b="$(_flag_val "$suite" --start)" 'BEGIN{exit !(a<=b)}'
  # root.end is at or after every phase end.
  awk -v a="$root_end" -v b="$(_flag_val "$prewarm" --end)" 'BEGIN{exit !(a>=b)}'
  awk -v a="$root_end" -v b="$(_flag_val "$suite" --end)" 'BEGIN{exit !(a>=b)}'
  awk -v a="$root_end" -v b="$(_flag_val "$flatten" --end)" 'BEGIN{exit !(a>=b)}'
}

@test "AC-6: root + phase spans + file/test spans all share one trace_id" {
  local wired="$BATS_TEST_TMPDIR/wired6.bats"
  cat > "$wired" <<EOF
#!/usr/bin/env bats
source "$TELEMETRY_HELPER"
setup_file()    { telemetry_setup_file; }
teardown_file() { telemetry_teardown_file; }
teardown()      { telemetry_teardown; }
@test "wired pass" { true; }
EOF
  _run_full_run "$wired"
  local total traced
  total=$(grep -c '' "$OTEL_SPAN_STUB_OUT")
  traced=$(grep -cF -- "$(printf '\t--force-trace-id\t%s\t' "$TRACE_ID")" "$OTEL_SPAN_STUB_OUT")
  [ "$total" -ge 4 ]
  [ "$traced" -eq "$total" ]
  [ -n "$(_span_line "test-suite-run")" ]
  [ -n "$(_span_line "manifest pre-warm")" ]
  [ -n "$(_span_line "bats suite (run-bts560)")" ]
  [ -n "$(_span_line "otel-flatten")" ]
}

# =========================================================================
# AC-8 / AC-9 — edge: graceful skip + pre-warm skipped
# =========================================================================

@test "AC-8: --no-telemetry emits zero spans; suite exit code unchanged" {
  _run_instrumented --no-telemetry "$STUB_BATS"
  [ "$status" -eq 0 ]
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
}

@test "AC-8: an unreachable Collector degrades to a silent no-op" {
  # Unset any inherited init pin (`env -u`) so otel-span.sh actually probes the
  # (dead) Collector, finds it unreachable, and every otel_span_emit no-ops.
  run env -u OTEL_SPAN_INIT_DONE -u OTEL_SPAN_LIVE \
    OTEL_SPAN_CLI="$BATS_TEST_TMPDIR/otel-cli-stub" \
    CCANVIL_TELEMETRY_URL="http://127.0.0.1:1" \
    OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
    BTS_RUN_ID="run-bts560" \
    BTS_TELEMETRY_TRACE_ID="$TRACE_ID" \
    BTS_TELEMETRY_SUITE_SPAN_ID="$SUITE_SPAN_ID" \
    BTS_TELEMETRY_RUN_SPAN_ID="$RUN_SPAN_ID" \
    BATS_REPORT_STATE_DIR="$BATS_REPORT_STATE_DIR" \
    bash "$SCRIPT" "$STUB_BATS"
  [ "$status" -eq 0 ]
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
}

@test "AC-9: pre-warm skipped — no pre-warm span; root + suite still traced" {
  # setup() ran stub_bats_report_prewarm → BTS_MANIFEST_VALIDATE_CACHE is set,
  # so bats-report.sh skips the pre-warm block entirely.
  _run_instrumented "$STUB_BATS"
  [ "$status" -eq 0 ]
  [ -z "$(_span_line "manifest pre-warm")" ]
  [ -n "$(_span_line "test-suite-run")" ]
  [ -n "$(_span_line "bats suite (run-bts560)")" ]
}
