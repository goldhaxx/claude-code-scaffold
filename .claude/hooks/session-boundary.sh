#!/usr/bin/env bash
# BTS-206 — SessionStart hook. Bumps a persistent session counter and stamps
# an ISO-8601 local boundary so /stasis (write side) and /recall (read side)
# can surface session number + human-readable local time.
#
# State files (per-node, gitignored):
#   .ccanvil/state/session-counter   — integer, monotonically incrementing
#   .ccanvil/state/session-boundary  — JSON {epoch, iso, tz}
#
# Failure mode: WARN to stderr, exit 0. Never blocks session start.
# BTS-209: durable failure recording via _hook_record_failure helper —
# every WARN path also appends to .ccanvil/state/hook-failures.log.

set +e

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.ccanvil/state"
COUNTER_PATH="$STATE_DIR/session-counter"
BOUNDARY_PATH="$STATE_DIR/session-boundary"
# BTS-209/208: helper resolves relative to the hook's own location.
HELPER="$(dirname "${BASH_SOURCE[0]}")/_lib/record-failure.sh"

# BTS-209: source helper if present; fall back to no-op when missing
# (stderr WARN paths still fire — loud is preserved without the helper).
# BTS-208: same helper exposes _timer_start / _timer_duration_ms / _timer_emit.
if [[ -f "$HELPER" ]]; then
  source "$HELPER"
else
  _hook_record_failure() { :; }
  _timer_start() { date +%s 2>/dev/null || echo 0; }
  _timer_duration_ms() { echo 0; }
  _timer_emit() { :; }
fi

# BTS-208: timing instrumentation — start before any work
_t_start=$(_timer_start)

mkdir -p "$STATE_DIR" 2>/dev/null || {
  echo "WARN: session-boundary: cannot create $STATE_DIR" >&2
  _hook_record_failure "session-boundary" "mkdir-state-dir" "cannot create $STATE_DIR"
  exit 0
}

# Counter: read → validate integer → bump → atomic write.
counter=0
if [[ -f "$COUNTER_PATH" ]]; then
  raw=$(tr -d '[:space:]' < "$COUNTER_PATH" 2>/dev/null || echo "")
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    counter="$raw"
  else
    echo "WARN: session-counter contained non-integer; resetting to 1" >&2
    _hook_record_failure "session-boundary" "counter-non-integer" "non-integer counter contents reset to 1"
    counter=0
  fi
fi
counter=$((counter + 1))

tmp_counter=$(mktemp "$STATE_DIR/.session-counter.XXXXXX" 2>/dev/null) || {
  echo "WARN: session-boundary: cannot mktemp counter" >&2
  _hook_record_failure "session-boundary" "mktemp-counter" "cannot create temp counter file"
  exit 0
}
echo "$counter" > "$tmp_counter" 2>/dev/null && \
  mv "$tmp_counter" "$COUNTER_PATH" 2>/dev/null || {
    rm -f "$tmp_counter" 2>/dev/null
    echo "WARN: session-boundary: counter write failed" >&2
    _hook_record_failure "session-boundary" "counter-write" "counter write or mv failed"
    exit 0
  }

# Boundary: epoch + ISO-8601 with colon-separated offset + tz.
epoch=$(date +%s)
# BSD date emits offset as -0700; insert the colon to match RFC 3339.
iso=$(date '+%Y-%m-%dT%H:%M:%S%z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')
tz=""
if [[ -n "${TZ:-}" ]]; then
  tz="$TZ"
elif link=$(readlink /etc/localtime 2>/dev/null) && [[ -n "$link" ]]; then
  # macOS: /var/db/timezone/zoneinfo/America/Los_Angeles
  # Linux: /usr/share/zoneinfo/America/Los_Angeles
  tz="${link##*/zoneinfo/}"
elif command -v timedatectl >/dev/null 2>&1; then
  # Linux + systemd — handles non-symlink /etc/localtime (Docker, WSL).
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "")
fi
# Last-resort fallback: zone abbreviation from `date` (e.g., "PDT", "EST").
# Not IANA but informative; preferred over a blanket "UTC" lie when the
# above derivations fail. The iso string carries the numeric offset so the
# timestamp is unambiguous even when tz is an abbreviation.
if [[ -z "$tz" ]]; then
  tz=$(date '+%Z' 2>/dev/null || echo "UTC")
fi
tz="${tz:-UTC}"

tmp_boundary=$(mktemp "$STATE_DIR/.session-boundary.XXXXXX" 2>/dev/null) || {
  echo "WARN: session-boundary: cannot mktemp boundary" >&2
  _hook_record_failure "session-boundary" "mktemp-boundary" "cannot create temp boundary file"
  exit 0
}
jq -n --argjson epoch "$epoch" --arg iso "$iso" --arg tz "$tz" \
  '{epoch:$epoch, iso:$iso, tz:$tz}' > "$tmp_boundary" 2>/dev/null && \
  mv "$tmp_boundary" "$BOUNDARY_PATH" 2>/dev/null || {
    rm -f "$tmp_boundary" 2>/dev/null
    echo "WARN: session-boundary: boundary write failed" >&2
    _hook_record_failure "session-boundary" "boundary-write" "boundary write or mv failed"
    exit 0
  }

# BTS-208: emit timing on completion (best-effort; never fails the hook)
_timer_emit "hook" "session-boundary" "$(_timer_duration_ms "$_t_start")"

exit 0
