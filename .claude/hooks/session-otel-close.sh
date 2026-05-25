#!/usr/bin/env bash
# BTS-544 — SessionEnd hook that emits the rooted ccanvil-session span.
# Reads .ccanvil/state/session-trace.json (written by session-otel-open.sh),
# emits ONE span with the stored trace/span IDs (no parent → rooted) and
# duration = end_epoch - started_at_epoch, then removes the state file.
#
# Pairs with .claude/hooks/session-otel-open.sh (BTS-544) and the existing
# session-boundary.sh (BTS-206).
#
# Failure mode: WARN to stderr, exit 0. Never blocks session end.

# @manifest
# purpose: SessionEnd hook that emits the rooted ccanvil-session span. Reads .ccanvil/state/session-trace.json (written by session-otel-open.sh), captures end_epoch via `date +%s.%N`, emits ONE OTel span via otel-span.sh (service=ccanvil-session, no parent → rooted) with trace_id/span_id pinned from the state file and attrs session.id + git.sha + (optional) claude_session_id, then removes the state file so the next SessionStart's reaper does not re-fire. Duration is implicit (end - started_at_epoch); both endpoints are epoch-second floats so otel-cli receives no unit conversion. Pairs with session-otel-open.sh; depends on otel-span.sh (BTS-543).
# input: env CLAUDE_PROJECT_DIR (falls back to PWD)
# input: env CCANVIL_TELEMETRY_DISABLED (force-skip telemetry; state file still cleaned up)
# input: env OTEL_SPAN_CLI (otel-cli binary path; test seam)
# input: file .ccanvil/state/session-trace.json
# output: OTel span (when telemetry live) — service=ccanvil-session, rooted (no parent), attrs include session.id + git.sha + claude_session_id (omit-when-empty)
# output: side-effect: removes-state-file
# output: exit-code 0 always
# output: stderr on failure: WARN with reason
# output: durable failure log: .ccanvil/state/hook-failures.log
# caller: .claude/settings.json
# depends-on: jq
# depends-on: date
# depends-on: git
# depends-on: otel-cli
# side-effect: emits-otel-spans
# side-effect: removes-state-file
# side-effect: writes-stderr-warn-on-failure
# failure-mode: state-missing | exit=0 | visible=stderr-WARN+hook-failures-log | mitigation=verify-open-hook-ran
# failure-mode: state-malformed | exit=0 | visible=stderr-WARN+hook-failures-log | mitigation=inspect-state-file
# failure-mode: telemetry-skipped | exit=0 | visible=stderr-WARN+hook-failures-log | mitigation=start-the-observability-stack
# contract: never-blocks-session-end
# contract: rooted-span-no-parent
# contract: omit-claude_session_id-when-empty
# contract: state-file-removed-on-success
# anchor: BTS-544 (origin)
# anchor: BTS-542 (umbrella)

set +e

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.ccanvil/state"
STATE_FILE="$STATE_DIR/session-trace.json"

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
  echo "WARN: session-otel-close: missing otel-span.sh helper" >&2
  _hook_record_failure "session-otel-close" "missing-helper" "otel-span.sh not found at $OTEL_SPAN_HELPER"
  exit 0
fi

if [[ ! -f "$STATE_FILE" ]]; then
  # @failure-mode: state-missing
  # @side-effect: writes-stderr-warn-on-failure
  echo "WARN: session-otel-close: state file missing — open hook never ran or already closed" >&2
  _hook_record_failure "session-otel-close" "state-missing" "no state file at $STATE_FILE"
  exit 0
fi

trace_id="$(jq -r '.trace_id // ""' < "$STATE_FILE" 2>/dev/null)"
root_span_id="$(jq -r '.root_span_id // ""' < "$STATE_FILE" 2>/dev/null)"
started_at_epoch="$(jq -r '.started_at_epoch // ""' < "$STATE_FILE" 2>/dev/null)"
session_id="$(jq -r '.session_id // ""' < "$STATE_FILE" 2>/dev/null)"
claude_session_id="$(jq -r '.claude_session_id // ""' < "$STATE_FILE" 2>/dev/null)"

if [[ -z "$trace_id" || -z "$root_span_id" || -z "$started_at_epoch" || -z "$session_id" ]]; then
  # @failure-mode: state-malformed
  echo "WARN: session-otel-close: state file malformed" >&2
  _hook_record_failure "session-otel-close" "state-malformed" "missing required field in $STATE_FILE"
  exit 0
fi

end_epoch="$(date +%s.%N 2>/dev/null || date +%s)"
git_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

# BTS-544 AC-7: telemetry-live gate. otel_span_emit itself is silent on a
# down Collector / missing otel-cli; surface the skip explicitly for
# diagnostic visibility (WARN + hook-failures.log entry).
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
  echo "WARN: session-otel-close: telemetry skipped ($reason)" >&2
  _hook_record_failure "session-otel-close" "telemetry-skipped" "$reason"
else
  attrs="session.id=$(otel_span_sanitize "$session_id"),git.sha=$(otel_span_sanitize "$git_sha")"
  if [[ -n "$claude_session_id" ]]; then
    attrs="${attrs},claude_session_id=$(otel_span_sanitize "$claude_session_id")"
  fi
  # @side-effect: emits-otel-spans
  otel_span_emit \
    --service ccanvil-session \
    --name ccanvil-session \
    --start "$started_at_epoch" \
    --end "$end_epoch" \
    --status unset \
    --trace-id "$trace_id" \
    --span-id "$root_span_id" \
    --attrs "$attrs" \
    --timeout 5s
fi

# @side-effect: removes-state-file
rm -f "$STATE_FILE" 2>/dev/null

exit 0
