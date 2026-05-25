#!/usr/bin/env bash
# BTS-544 — SessionStart hook that establishes the session trace state.
# Writes .ccanvil/state/session-trace.json with the trace_id + root_span_id
# + started_at_epoch + session_id + claude_session_id; the SessionEnd close
# hook reads this file and emits the rooted ccanvil-session span.
#
# Pairs with .claude/hooks/session-boundary.sh (BTS-206), which MUST run
# first in the SessionStart hooks array to bump the session counter that
# this hook then reads.
#
# Failure mode: WARN to stderr, exit 0. Never blocks session start.

# @manifest
# purpose: SessionStart hook that establishes the rooted ccanvil-session trace state. Generates a 32-hex trace_id + 16-hex root_span_id; captures started_at_epoch via `date +%s.%N`; reads the post-bump session-counter (session-boundary.sh ran first in the array); extracts the Claude Code session UUID from the stdin JSON payload via `jq -r '.session_id // ""'`; atomic mktemp+mv writes .ccanvil/state/session-trace.json. If a state file already exists (prior SessionEnd never fired), emits one best-effort "reaper" ccanvil-session span carrying reaper=true + stale session.id BEFORE overwriting. Pairs with session-otel-close.sh; depends on otel-span.sh (BTS-543).
# input: env CLAUDE_PROJECT_DIR (falls back to PWD)
# input: env CCANVIL_TELEMETRY_DISABLED (force-skip telemetry; state file still written)
# input: env OTEL_SPAN_CLI (otel-cli binary path; test seam)
# input: stdin JSON payload (Claude Code SessionStart event with .session_id UUID)
# input: file .ccanvil/state/session-counter (integer, post-bump value)
# output: file .ccanvil/state/session-trace.json (JSON {trace_id, root_span_id, started_at_epoch, session_id, claude_session_id})
# output: OTel span (reaper case only) — service=ccanvil-session, attrs include reaper=true
# output: exit-code 0 always
# output: stderr on failure: WARN with reason
# output: durable failure log: .ccanvil/state/hook-failures.log
# caller: .claude/settings.json
# depends-on: jq
# depends-on: date
# depends-on: mktemp
# depends-on: git
# depends-on: otel-cli
# side-effect: writes-state-file
# side-effect: emits-otel-spans
# side-effect: writes-stderr-warn-on-failure
# failure-mode: state-write-failure | exit=0 | visible=stderr-WARN+hook-failures-log | mitigation=verify-state-dir-writable
# failure-mode: telemetry-skipped | exit=0 | visible=stderr-WARN+hook-failures-log | mitigation=start-the-observability-stack
# contract: never-blocks-session-start
# contract: atomic-write-via-mktemp-mv
# contract: reaper-emits-before-state-overwrite
# contract: omit-claude_session_id-when-empty
# anchor: BTS-544 (origin)
# anchor: BTS-542 (umbrella)

set +e

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.ccanvil/state"
STATE_FILE="$STATE_DIR/session-trace.json"
COUNTER_PATH="$STATE_DIR/session-counter"

HELPER="$(dirname "${BASH_SOURCE[0]}")/_lib/record-failure.sh"
if [[ -f "$HELPER" ]]; then
  source "$HELPER"
else
  _hook_record_failure() { :; }
fi

OTEL_SPAN_HELPER="$(dirname "${BASH_SOURCE[0]}")/../../.ccanvil/observability/otel-span.sh"
if [[ -f "$OTEL_SPAN_HELPER" ]]; then
  source "$OTEL_SPAN_HELPER"
else
  echo "WARN: session-otel-open: missing otel-span.sh helper" >&2
  _hook_record_failure "session-otel-open" "missing-helper" "otel-span.sh not found at $OTEL_SPAN_HELPER"
  exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null || {
  echo "WARN: session-otel-open: cannot create $STATE_DIR" >&2
  _hook_record_failure "session-otel-open" "mkdir-state-dir" "cannot create $STATE_DIR"
  exit 0
}

# Read the SessionStart stdin payload once. Empty / malformed / closed fd 0
# all degrade to claude_session_id="" via jq's `// ""` default.
payload="$(cat - 2>/dev/null || true)"
claude_session_id="$(jq -r '.session_id // ""' 2>/dev/null <<<"$payload" || echo "")"

# Read post-bump counter (session-boundary.sh ran first in the array).
counter=0
if [[ -f "$COUNTER_PATH" ]]; then
  raw=$(tr -d '[:space:]' < "$COUNTER_PATH" 2>/dev/null || echo "")
  [[ "$raw" =~ ^[0-9]+$ ]] && counter="$raw"
fi

started_at_epoch="$(date +%s.%N 2>/dev/null || date +%s)"
epoch_seconds="${started_at_epoch%%.*}"
session_id="${counter}-${epoch_seconds}"

trace_id="$(otel_span_new_trace_id)"
root_span_id="$(otel_span_new_span_id)"

# BTS-544 AC-4: reaper for abnormal exit. If a session-trace.json already
# exists, the previous SessionEnd never fired — emit a best-effort rooted
# span for that stale trace BEFORE overwriting the state file. The reaper
# span carries reaper=true so observers can distinguish it.
if [[ -f "$STATE_FILE" ]]; then
  stale_trace_id="$(jq -r '.trace_id // ""' < "$STATE_FILE" 2>/dev/null)"
  stale_root_span_id="$(jq -r '.root_span_id // ""' < "$STATE_FILE" 2>/dev/null)"
  stale_started_at="$(jq -r '.started_at_epoch // ""' < "$STATE_FILE" 2>/dev/null)"
  stale_session_id="$(jq -r '.session_id // ""' < "$STATE_FILE" 2>/dev/null)"
  stale_claude_id="$(jq -r '.claude_session_id // ""' < "$STATE_FILE" 2>/dev/null)"
  if [[ -n "$stale_trace_id" && -n "$stale_root_span_id" && -n "$stale_started_at" && -n "$stale_session_id" ]]; then
    # BTS-544 AC-7: telemetry-live gate for the reaper emission.
    otel_span_init
    if [[ "${OTEL_SPAN_LIVE:-0}" != "1" ]]; then
      reason="unknown"
      if [[ -n "${CCANVIL_TELEMETRY_DISABLED:-}" ]]; then
        reason="telemetry-disabled-env"
      elif ! command -v "${OTEL_SPAN_CLI:-otel-cli}" >/dev/null 2>&1; then
        reason="otel-cli-missing"
      else
        reason="collector-unreachable"
      fi
      # @failure-mode: telemetry-skipped
      echo "WARN: session-otel-open: reaper skipped ($reason)" >&2
      _hook_record_failure "session-otel-open" "telemetry-skipped" "$reason"
    else
      reaper_end="$(date +%s.%N 2>/dev/null || date +%s)"
      reaper_git_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
      reaper_attrs="reaper=true,session.id=$(otel_span_sanitize "$stale_session_id"),git.sha=$(otel_span_sanitize "$reaper_git_sha")"
      if [[ -n "$stale_claude_id" ]]; then
        reaper_attrs="${reaper_attrs},claude_session_id=$(otel_span_sanitize "$stale_claude_id")"
      fi
      # @side-effect: emits-otel-spans
      otel_span_emit \
        --service ccanvil-session \
        --name ccanvil-session \
        --start "$stale_started_at" \
        --end "$reaper_end" \
        --status unset \
        --trace-id "$stale_trace_id" \
        --span-id "$stale_root_span_id" \
        --attrs "$reaper_attrs" \
        --timeout 5s
    fi
  fi
fi

tmp=$(mktemp "$STATE_DIR/.session-trace.XXXXXX" 2>/dev/null) || {
  # @failure-mode: state-write-failure
  # @side-effect: writes-stderr-warn-on-failure
  echo "WARN: session-otel-open: cannot mktemp state file" >&2
  _hook_record_failure "session-otel-open" "mktemp-state" "cannot create temp state file"
  exit 0
}
# @side-effect: writes-state-file
jq -n \
  --arg trace_id "$trace_id" \
  --arg root_span_id "$root_span_id" \
  --arg started_at_epoch "$started_at_epoch" \
  --arg session_id "$session_id" \
  --arg claude_session_id "$claude_session_id" \
  '{trace_id:$trace_id, root_span_id:$root_span_id, started_at_epoch:$started_at_epoch, session_id:$session_id, claude_session_id:$claude_session_id}' \
  > "$tmp" 2>/dev/null && \
  mv "$tmp" "$STATE_FILE" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null
    echo "WARN: session-otel-open: state file write failed" >&2
    _hook_record_failure "session-otel-open" "state-write" "write or mv failed"
    exit 0
  }

exit 0
