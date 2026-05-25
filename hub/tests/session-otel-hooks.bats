#!/usr/bin/env bats

# BTS-544 — drift-guards for the session-otel SessionStart open + SessionEnd
# close hooks. These tests mutate OTEL_SPAN_* env aggressively, so this
# file's own suite telemetry is force-disabled (mirror bats-report-end-to-
# end-trace.bats).

bats_require_minimum_version 1.5.0

source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"
setup_file()    { CCANVIL_TELEMETRY_DISABLED=1 telemetry_setup_file; }
teardown_file() { CCANVIL_TELEMETRY_DISABLED=1 telemetry_teardown_file; }
teardown()      { CCANVIL_TELEMETRY_DISABLED=1 telemetry_teardown; }

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
OPEN_HOOK="$REPO_ROOT/.claude/hooks/session-otel-open.sh"
CLOSE_HOOK="$REPO_ROOT/.claude/hooks/session-otel-close.sh"

# Fixed IDs so span-linkage assertions are exact-match.
FIXED_TRACE_ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
FIXED_ROOT_SPAN_ID="bbbbbbbbbbbbbbbb"

setup() {
  TMPDIR_BATS=$(mktemp -d)
  CCANVIL_TELEMETRY_DISABLED=1 telemetry_setup

  # Per-test recording stub for otel-cli. Each invocation appends one
  # TAB-joined argv line to $OTEL_SPAN_STUB_OUT.
  export OTEL_SPAN_STUB_OUT="$TMPDIR_BATS/otel-argv"
  : > "$OTEL_SPAN_STUB_OUT"
  cat > "$TMPDIR_BATS/otel-cli-stub" <<'STUB'
#!/usr/bin/env bash
{ for __a in "$@"; do printf '%s\t' "$__a"; done; printf '\n'; } >> "$OTEL_SPAN_STUB_OUT"
STUB
  chmod +x "$TMPDIR_BATS/otel-cli-stub"
}

teardown() {
  CCANVIL_TELEMETRY_DISABLED=1 telemetry_teardown
  [[ -n "${TMPDIR_BATS:-}" ]] && ALLOW_DESTRUCTIVE=1 rm -rf "$TMPDIR_BATS"
}

# =========================================================================
# AC-2 — open writes state file (normal path)
# =========================================================================

@test "AC-2: open writes state file with valid shape; zero spans at open" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  # session-boundary.sh ran first in the real chain; pre-seed the post-bump
  # counter so the open hook can read it.
  echo "74" > "$fx/.ccanvil/state/session-counter"

  payload='{"hook_event_name":"SessionStart","session_id":"abc-uuid","source":"startup"}'
  CLAUDE_PROJECT_DIR="$fx" \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
  OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run bash "$OPEN_HOOK" <<<"$payload"

  [ "$status" -eq 0 ]
  [ -f "$fx/.ccanvil/state/session-trace.json" ]

  state="$(cat "$fx/.ccanvil/state/session-trace.json")"
  echo "$state" | jq -e '.trace_id        | test("^[0-9a-f]{32}$")'
  echo "$state" | jq -e '.root_span_id    | test("^[0-9a-f]{16}$")'
  echo "$state" | jq -e '.started_at_epoch | test("^[0-9]+\\.[0-9]+$")'
  echo "$state" | jq -e '.session_id      | test("^74-[0-9]+$")'
  echo "$state" | jq -e '.claude_session_id == "abc-uuid"'

  # ZERO span emissions at open time (the root emits at close).
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
}

# =========================================================================
# AC-2 edge — empty / malformed stdin → claude_session_id=""
# =========================================================================

@test "AC-2 edge: empty stdin → claude_session_id=\"\", exit 0, zero spans" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  echo "74" > "$fx/.ccanvil/state/session-counter"

  CLAUDE_PROJECT_DIR="$fx" \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
  OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run bash "$OPEN_HOOK" < /dev/null

  [ "$status" -eq 0 ]
  [ -f "$fx/.ccanvil/state/session-trace.json" ]
  echo "$(cat "$fx/.ccanvil/state/session-trace.json")" | jq -e '.claude_session_id == ""'
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
}

@test "AC-2 edge: malformed JSON stdin → claude_session_id=\"\", exit 0" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  echo "74" > "$fx/.ccanvil/state/session-counter"

  CLAUDE_PROJECT_DIR="$fx" \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
  OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run bash "$OPEN_HOOK" <<<"not json at all"

  [ "$status" -eq 0 ]
  [ -f "$fx/.ccanvil/state/session-trace.json" ]
  echo "$(cat "$fx/.ccanvil/state/session-trace.json")" | jq -e '.claude_session_id == ""'
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
}

# =========================================================================
# AC-3 — close hook emits rooted ccanvil-session span
# =========================================================================

# Pre-seed a known session-trace.json fixture into $1.
_seed_state() {
  local fx="$1"
  # No colon in default — preserve explicit "" passed by the omit-when-empty test.
  local claude_id="${2-claude-uuid-7777}"
  mkdir -p "$fx/.ccanvil/state"
  jq -n \
    --arg trace_id "$FIXED_TRACE_ID" \
    --arg root_span_id "$FIXED_ROOT_SPAN_ID" \
    --arg started_at_epoch "1779648721.123456000" \
    --arg session_id "74-1779648721" \
    --arg claude_session_id "$claude_id" \
    '{trace_id:$trace_id, root_span_id:$root_span_id, started_at_epoch:$started_at_epoch, session_id:$session_id, claude_session_id:$claude_session_id}' \
    > "$fx/.ccanvil/state/session-trace.json"
}

@test "AC-3: close emits exactly one rooted ccanvil-session span; state file removed" {
  set -e
  fx="$TMPDIR_BATS"
  _seed_state "$fx"

  CLAUDE_PROJECT_DIR="$fx" \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
  OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run bash "$CLOSE_HOOK" < /dev/null

  [ "$status" -eq 0 ]
  # State file removed on success.
  [ ! -f "$fx/.ccanvil/state/session-trace.json" ]
  # Exactly ONE recorded invocation.
  [ "$(wc -l < "$OTEL_SPAN_STUB_OUT" | tr -d ' ')" = "1" ]

  line="$(cat "$OTEL_SPAN_STUB_OUT")"
  # Service + name.
  echo "$line" | grep -qF $'\t--service\tccanvil-session\t'
  echo "$line" | grep -qF $'\t--name\tccanvil-session\t'
  # Trace + root span IDs match the state file.
  echo "$line" | grep -qF $'\t--force-trace-id\t'"$FIXED_TRACE_ID"$'\t'
  echo "$line" | grep -qF $'\t--force-span-id\t'"$FIXED_ROOT_SPAN_ID"$'\t'
  # NO parent → rooted.
  ! echo "$line" | grep -qF $'\t--force-parent-span-id\t'
  # Attrs include session.id, git.sha, claude_session_id.
  echo "$line" | grep -qF "session.id=74-1779648721"
  echo "$line" | grep -qF "git.sha="
  echo "$line" | grep -qF "claude_session_id=claude-uuid-7777"
}

@test "AC-3: omit-when-empty — empty claude_session_id drops the attr entirely" {
  set -e
  fx="$TMPDIR_BATS"
  _seed_state "$fx" ""   # empty claude_session_id

  CLAUDE_PROJECT_DIR="$fx" \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
  OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run bash "$CLOSE_HOOK" < /dev/null

  [ "$status" -eq 0 ]
  line="$(cat "$OTEL_SPAN_STUB_OUT")"
  # session.id + git.sha still present.
  echo "$line" | grep -qF "session.id=74-1779648721"
  echo "$line" | grep -qF "git.sha="
  # claude_session_id MUST NOT appear (fixed-string match — no BRE \|).
  ! echo "$line" | grep -qF "claude_session_id"
}

# =========================================================================
# AC-4 — reaper for abnormal exit
# =========================================================================

@test "AC-4: stale state at SessionStart triggers reaper; state overwritten" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  # Pre-seed counter (post-bump value session-boundary.sh would have written).
  echo "75" > "$fx/.ccanvil/state/session-counter"
  # Pre-seed a STALE session-trace.json — prior session never closed.
  STALE_TRACE="ffffffffffffffffffffffffffffffff"
  STALE_SPAN="ffffffffffffffff"
  jq -n \
    --arg trace_id "$STALE_TRACE" \
    --arg root_span_id "$STALE_SPAN" \
    --arg started_at_epoch "1779000000.111111000" \
    --arg session_id "99-1234567890" \
    --arg claude_session_id "stale-uuid-aaa" \
    '{trace_id:$trace_id, root_span_id:$root_span_id, started_at_epoch:$started_at_epoch, session_id:$session_id, claude_session_id:$claude_session_id}' \
    > "$fx/.ccanvil/state/session-trace.json"

  payload='{"hook_event_name":"SessionStart","session_id":"new-uuid-bbb","source":"startup"}'
  CLAUDE_PROJECT_DIR="$fx" \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
  OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run bash "$OPEN_HOOK" <<<"$payload"

  [ "$status" -eq 0 ]
  # Exactly ONE recorded invocation — the reaper. The new-session-open itself
  # does NOT emit at this stage (only the close hook does).
  [ "$(wc -l < "$OTEL_SPAN_STUB_OUT" | tr -d ' ')" = "1" ]

  line="$(cat "$OTEL_SPAN_STUB_OUT")"
  echo "$line" | grep -qF $'\t--service\tccanvil-session\t'
  echo "$line" | grep -qF $'\t--name\tccanvil-session\t'
  echo "$line" | grep -qF $'\t--force-trace-id\t'"$STALE_TRACE"$'\t'
  echo "$line" | grep -qF $'\t--force-span-id\t'"$STALE_SPAN"$'\t'
  ! echo "$line" | grep -qF $'\t--force-parent-span-id\t'
  echo "$line" | grep -qF "reaper=true"
  echo "$line" | grep -qF "session.id=99-1234567890"
  echo "$line" | grep -qF "claude_session_id=stale-uuid-aaa"

  # State file overwritten with the NEW session's fields.
  state="$(cat "$fx/.ccanvil/state/session-trace.json")"
  echo "$state" | jq -e '.trace_id != "'"$STALE_TRACE"$'"'
  echo "$state" | jq -e '.session_id | test("^75-[0-9]+$")'
  echo "$state" | jq -e '.claude_session_id == "new-uuid-bbb"'
}

# =========================================================================
# AC-6 — settings.json wiring
# =========================================================================

@test "AC-6: settings.json wires both SessionStart hooks (order-sensitive) + SessionEnd" {
  set -e
  settings="$REPO_ROOT/.claude/settings.json"
  [ -f "$settings" ]

  # SessionStart: exactly 2 entries; counter bumper FIRST, otel-open SECOND.
  [ "$(jq '.hooks.SessionStart | length' "$settings")" = "2" ]
  jq -r '.hooks.SessionStart[0].hooks[0].command' "$settings" | grep -qF "session-boundary.sh"
  jq -r '.hooks.SessionStart[1].hooks[0].command' "$settings" | grep -qF "session-otel-open.sh"

  # SessionEnd: exactly 1 entry; otel-close.
  [ "$(jq '.hooks.SessionEnd | length' "$settings")" = "1" ]
  jq -r '.hooks.SessionEnd[0].hooks[0].command' "$settings" | grep -qF "session-otel-close.sh"
}

# =========================================================================
# AC-7 — graceful-skip in 3 modes (telemetry-disabled, otel-cli missing,
# Collector unreachable). The close hook always wants to emit; the open
# hook only wants to emit when the reaper fires.
# =========================================================================

@test "AC-7: close hook with CCANVIL_TELEMETRY_DISABLED — no span, WARN, JSONL, state removed" {
  set -e
  fx="$TMPDIR_BATS"
  _seed_state "$fx"

  CLAUDE_PROJECT_DIR="$fx" \
  CCANVIL_TELEMETRY_DISABLED=1 \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run --separate-stderr bash "$CLOSE_HOOK" < /dev/null

  [ "$status" -eq 0 ]
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
  [ ! -f "$fx/.ccanvil/state/session-trace.json" ]   # state still cleaned up
  echo "$stderr" | grep -qF "WARN:"
  [ -f "$fx/.ccanvil/state/hook-failures.log" ]
  jq -e -s 'any(.step == "telemetry-skipped")' < "$fx/.ccanvil/state/hook-failures.log"
}

@test "AC-7: close hook with OTEL_SPAN_CLI=/nonexistent — no span, WARN, JSONL" {
  set -e
  fx="$TMPDIR_BATS"
  _seed_state "$fx"

  CLAUDE_PROJECT_DIR="$fx" \
  OTEL_SPAN_CLI="/nonexistent/otel-cli-binary" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run --separate-stderr bash "$CLOSE_HOOK" < /dev/null

  [ "$status" -eq 0 ]
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
  echo "$stderr" | grep -qF "WARN:"
  jq -e -s 'any(.step == "telemetry-skipped")' < "$fx/.ccanvil/state/hook-failures.log"
}

@test "AC-7: close hook with unreachable Collector — no span, WARN, JSONL" {
  set -e
  fx="$TMPDIR_BATS"
  _seed_state "$fx"

  CLAUDE_PROJECT_DIR="$fx" \
  CCANVIL_TELEMETRY_URL="http://127.0.0.1:1" \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run --separate-stderr bash "$CLOSE_HOOK" < /dev/null

  [ "$status" -eq 0 ]
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
  echo "$stderr" | grep -qF "WARN:"
  jq -e -s 'any(.step == "telemetry-skipped")' < "$fx/.ccanvil/state/hook-failures.log"
}

@test "AC-7: open-reaper with CCANVIL_TELEMETRY_DISABLED — no span, WARN, state overwritten" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  echo "76" > "$fx/.ccanvil/state/session-counter"
  jq -n \
    --arg trace_id "ffffffffffffffffffffffffffffffff" \
    --arg root_span_id "ffffffffffffffff" \
    --arg started_at_epoch "1779000000.0" \
    --arg session_id "99-1234567890" \
    --arg claude_session_id "" \
    '{trace_id:$trace_id, root_span_id:$root_span_id, started_at_epoch:$started_at_epoch, session_id:$session_id, claude_session_id:$claude_session_id}' \
    > "$fx/.ccanvil/state/session-trace.json"

  CLAUDE_PROJECT_DIR="$fx" \
  CCANVIL_TELEMETRY_DISABLED=1 \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run --separate-stderr bash "$OPEN_HOOK" <<<'{"session_id":"new-uuid"}'

  [ "$status" -eq 0 ]
  [ ! -s "$OTEL_SPAN_STUB_OUT" ]
  echo "$stderr" | grep -qF "WARN:"
  jq -e -s 'any(.step == "telemetry-skipped")' < "$fx/.ccanvil/state/hook-failures.log"
  # State overwritten regardless of telemetry skip.
  echo "$(cat "$fx/.ccanvil/state/session-trace.json")" | jq -e '.trace_id != "ffffffffffffffffffffffffffffffff"'
}

@test "AC-3: duration end >= start (close emits a non-negative interval)" {
  set -e
  fx="$TMPDIR_BATS"
  _seed_state "$fx"

  CLAUDE_PROJECT_DIR="$fx" \
  OTEL_SPAN_CLI="$TMPDIR_BATS/otel-cli-stub" \
  OTEL_SPAN_INIT_DONE=1 OTEL_SPAN_LIVE=1 \
  OTEL_SPAN_ENDPOINT="http://127.0.0.1:4318" \
  OTEL_SPAN_STUB_OUT="$OTEL_SPAN_STUB_OUT" \
  run bash "$CLOSE_HOOK" < /dev/null

  [ "$status" -eq 0 ]
  line="$(cat "$OTEL_SPAN_STUB_OUT")"
  # Pull --start / --end values from TAB-joined argv.
  start_v="$(printf '%s' "$line" | awk -F'\t' '{for(i=1;i<NF;i++) if($i=="--start"){print $(i+1); exit}}')"
  end_v="$(printf   '%s' "$line" | awk -F'\t' '{for(i=1;i<NF;i++) if($i=="--end")  {print $(i+1); exit}}')"
  [ -n "$start_v" ]
  [ -n "$end_v" ]
  # awk float compare: end >= start, exit 0 on truth, 1 on falsity.
  awk -v s="$start_v" -v e="$end_v" 'BEGIN{exit !(e+0 >= s+0)}'
}
