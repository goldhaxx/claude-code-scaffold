#!/usr/bin/env bash
# BTS-209: canonical hook-failure recording helper.
#
# Provides _hook_record_failure as a sourceable shell function. Appends one
# JSONL line {ts, hook, step, message} to .ccanvil/state/hook-failures.log
# (gitignored — operator-private failure history).
#
# Contract: telemetry hooks call this on guarded failures (loud, never-block,
# never-snuff). Guard hooks (PreToolUse blockers like protect-files,
# guard-destructive) keep their own blocking contract — this helper is for
# the telemetry-hook surface only.
#
# Usage:
#   source "$CLAUDE_PROJECT_DIR/.claude/hooks/_lib/record-failure.sh"
#   _hook_record_failure "session-boundary" "counter-write" "mktemp failed"
#
# Failures of the helper itself (jq missing, log dir unwritable) are silently
# swallowed — there's no further fallback. Caller already emitted to stderr
# (loud); the durable record is best-effort.

_hook_record_failure() {
  local hook="${1:-unknown}"
  local step="${2:-unknown}"
  local message="${3:-(no message)}"
  local root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local log_dir="$root/.ccanvil/state"
  local log_file="$log_dir/hook-failures.log"

  mkdir -p "$log_dir" 2>/dev/null || return 0

  local entry
  entry=$(jq -nc \
    --arg hk "$hook" \
    --arg st "$step" \
    --arg msg "$message" \
    --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
    '{ts:$ts, hook:$hk, step:$st, message:$msg}' 2>/dev/null) || return 0

  printf '%s\n' "$entry" >> "$log_file" 2>/dev/null || return 0
  return 0
}

# BTS-208: hook timing instrumentation primitive.
#
# _timer_start                     — echo current epoch-ms (or seconds*1000)
# _timer_duration_ms <start_ms>    — echo elapsed ms since <start_ms>
# _timer_emit <kind> <name> <ms>   — append JSONL record to execution-timing.log
#
# Granularity: GNU date supports %3N for millisecond precision; BSD date
# (macOS default) does not. Falls back to python3 if available; otherwise
# seconds*1000 (sub-second timings round to 0). Caveat: on macOS without
# python3 the recorded duration is second-granularity only.

_timer_start() {
  # Prefer GNU date %3N
  local ms
  ms=$(date +%s%3N 2>/dev/null)
  if [[ "$ms" =~ ^[0-9]+$ ]] && (( ${#ms} >= 13 )); then
    printf '%s\n' "$ms"
    return 0
  fi
  # python3 fallback for macOS
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null && return 0
  fi
  # Last resort: seconds-granularity
  ms=$(date +%s 2>/dev/null || echo 0)
  printf '%s\n' "$((ms * 1000))"
}

_timer_duration_ms() {
  local start_ms="${1:-0}"
  local now
  now=$(_timer_start)
  local diff=$((now - start_ms))
  (( diff < 0 )) && diff=0
  printf '%s\n' "$diff"
}

_timer_emit() {
  local kind="${1:-unknown}"
  local name="${2:-unknown}"
  local duration_ms="${3:-0}"
  local root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local log_dir="$root/.ccanvil/state"
  local log_file="$log_dir/execution-timing.log"

  mkdir -p "$log_dir" 2>/dev/null || return 0

  local entry
  entry=$(jq -nc \
    --arg kind "$kind" \
    --arg name "$name" \
    --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
    --argjson ms "$duration_ms" \
    '{ts:$ts, kind:$kind, name:$name, duration_ms:$ms}' 2>/dev/null) || return 0

  printf '%s\n' "$entry" >> "$log_file" 2>/dev/null || return 0
  return 0
}
