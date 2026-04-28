#!/usr/bin/env bash
# BTS-113 — PreCompact hook. Records epoch timestamp so
# docs-check.sh recommend can distinguish "session about to end (suggest /compact)"
# from "session just resumed after /compact + /recall (suggest forward action)".
#
# BTS-209: migrated to canonical telemetry-hook pattern (loud, never-block,
# never-snuff). Per-step explicit guards + durable failure log via
# _hook_record_failure helper.

set +e

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.ccanvil/state"
MARKER_PATH="$STATE_DIR/last-compact-ts"
# BTS-209/208: helper resolves relative to the hook's own location, not
# the project root — hooks may be invoked from any cwd, but the helper
# lives next to them in the hub-tracked .claude/hooks/_lib directory.
HELPER="$(dirname "${BASH_SOURCE[0]}")/_lib/record-failure.sh"

# Source helper — best-effort. If missing, fall back to stderr-only WARN.
if [[ -f "$HELPER" ]]; then
  source "$HELPER"
else
  _hook_record_failure() { :; }  # no-op fallback
  _timer_start() { date +%s 2>/dev/null || echo 0; }
  _timer_duration_ms() { echo 0; }
  _timer_emit() { :; }
fi

# BTS-208: timing instrumentation
_t_start=$(_timer_start)

mkdir -p "$STATE_DIR" 2>/dev/null
if [[ ! -d "$STATE_DIR" ]]; then
  echo "WARN: post-compact-marker: cannot create $STATE_DIR" >&2
  _hook_record_failure "post-compact-marker" "mkdir" "cannot create $STATE_DIR"
  exit 0
fi

if ! date +%s > "$MARKER_PATH" 2>/dev/null; then
  echo "WARN: post-compact-marker: cannot write $MARKER_PATH" >&2
  _hook_record_failure "post-compact-marker" "write-marker" "cannot write $MARKER_PATH"
  exit 0
fi

# BTS-208: emit timing on completion (best-effort; never fails the hook)
_timer_emit "hook" "post-compact-marker" "$(_timer_duration_ms "$_t_start")"

exit 0
