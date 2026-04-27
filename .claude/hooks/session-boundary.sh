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

set +e

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.ccanvil/state"
COUNTER_PATH="$STATE_DIR/session-counter"
BOUNDARY_PATH="$STATE_DIR/session-boundary"

mkdir -p "$STATE_DIR" 2>/dev/null || {
  echo "WARN: session-boundary: cannot create $STATE_DIR" >&2
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
    counter=0
  fi
fi
counter=$((counter + 1))

tmp_counter=$(mktemp "$STATE_DIR/.session-counter.XXXXXX" 2>/dev/null) || {
  echo "WARN: session-boundary: cannot mktemp counter" >&2
  exit 0
}
echo "$counter" > "$tmp_counter" 2>/dev/null && \
  mv "$tmp_counter" "$COUNTER_PATH" 2>/dev/null || {
    rm -f "$tmp_counter" 2>/dev/null
    echo "WARN: session-boundary: counter write failed" >&2
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
  exit 0
}
jq -n --argjson epoch "$epoch" --arg iso "$iso" --arg tz "$tz" \
  '{epoch:$epoch, iso:$iso, tz:$tz}' > "$tmp_boundary" 2>/dev/null && \
  mv "$tmp_boundary" "$BOUNDARY_PATH" 2>/dev/null || {
    rm -f "$tmp_boundary" 2>/dev/null
    echo "WARN: session-boundary: boundary write failed" >&2
    exit 0
  }

exit 0
