#!/usr/bin/env bash
# BTS-113 — PreCompact hook. Records epoch timestamp so
# docs-check.sh recommend can distinguish "session about to end (suggest /compact)"
# from "session just resumed after /compact + /recall (suggest forward action)".
#
# BTS-209: migrated to canonical telemetry-hook pattern (loud, never-block,
# never-snuff). Per-step explicit guards + durable failure log via
# _hook_record_failure helper.

# @manifest
# purpose: PreCompact hook that stamps `$CLAUDE_PROJECT_DIR/.ccanvil/state/last-compact-ts` with the current epoch right before /compact runs. Read by docs-check.sh's recommend logic to distinguish "session-about-to-end" (suggest /compact) from "session-just-resumed" (suggest forward action). Telemetry-hook pattern (BTS-209): loud on failure, never blocks, never snuffs.
# input: env CLAUDE_PROJECT_DIR (falls back to PWD)
# output: file `.ccanvil/state/last-compact-ts` (epoch integer)
# output: exit-code 0 always (telemetry hook never blocks /compact)
# output: stderr on failure: WARN with reason
# output: durable failure log: `.ccanvil/state/hook-failures.log` (via _hook_record_failure)
# caller: .claude/settings.json
# depends-on: date
# depends-on: mkdir
# side-effect: writes-marker-file
# side-effect: writes-stderr-warn-on-failure
# failure-mode: never-fails | exit=0 | visible=stderr-WARN-and-failure-log-on-mkdir-or-write-failure | mitigation=verify-state-dir-writable
# contract: never-blocks
# contract: idempotent-on-rerun
# contract: helper-fallback-when-_lib/record-failure.sh-missing
# anchor: BTS-113 (origin)
# anchor: BTS-208 (timing instrumentation)
# anchor: BTS-209 (durable failure logging)
# anchor: BTS-251 (manifest seed)

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
  # @failure-mode: never-fails
  # @side-effect: writes-stderr-warn-on-failure
  echo "WARN: post-compact-marker: cannot create $STATE_DIR" >&2
  _hook_record_failure "post-compact-marker" "mkdir" "cannot create $STATE_DIR"
  exit 0
fi

# @side-effect: writes-marker-file
if ! date +%s > "$MARKER_PATH" 2>/dev/null; then
  echo "WARN: post-compact-marker: cannot write $MARKER_PATH" >&2
  _hook_record_failure "post-compact-marker" "write-marker" "cannot write $MARKER_PATH"
  exit 0
fi

# BTS-208: emit timing on completion (best-effort; never fails the hook)
_timer_emit "hook" "post-compact-marker" "$(_timer_duration_ms "$_t_start")"

exit 0
