#!/usr/bin/env bats
# BTS-208: hook timing instrumentation primitive.
# - _timer_emit appends JSONL to .ccanvil/state/execution-timing.log.
# - post-compact-marker.sh and session-boundary.sh emit duration on completion.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
HELPER="$REPO_ROOT/.claude/hooks/_lib/record-failure.sh"
TIMER_HELPER="$REPO_ROOT/.claude/hooks/_lib/timer.sh"
POST_COMPACT_HOOK="$REPO_ROOT/.claude/hooks/post-compact-marker.sh"
SESSION_BOUNDARY_HOOK="$REPO_ROOT/.claude/hooks/session-boundary.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
  PROJECT="$TMPDIR_BATS/proj"
  mkdir -p "$PROJECT/.ccanvil/state"
  export CLAUDE_PROJECT_DIR="$PROJECT"
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

# =========================================================================
# AC-1, AC-5: _timer_emit appends JSONL line
# =========================================================================

@test "BTS-208 AC-1: _timer_emit appends JSONL to execution-timing.log" {
  set -e
  # Helper expected at one of the two locations
  if [[ -f "$TIMER_HELPER" ]]; then
    source "$TIMER_HELPER"
  elif [[ -f "$HELPER" ]]; then
    source "$HELPER"
  else
    return 1
  fi
  _timer_emit "hook" "test-hook" 42

  log="$PROJECT/.ccanvil/state/execution-timing.log"
  [ -f "$log" ]
  count=$(wc -l < "$log" | tr -d ' ')
  [ "$count" -eq 1 ]
  line=$(tail -1 "$log")
  echo "$line" | jq -e '.kind == "hook"'
  echo "$line" | jq -e '.name == "test-hook"'
  echo "$line" | jq -e '.duration_ms == 42'
  echo "$line" | jq -e '.ts | type == "number"'
}

# =========================================================================
# AC-2: _timer_start + _timer_duration_ms produce a numeric duration
# =========================================================================

@test "BTS-208 AC-2: _timer_start + _timer_duration_ms produces numeric ms" {
  set -e
  if [[ -f "$TIMER_HELPER" ]]; then
    source "$TIMER_HELPER"
  elif [[ -f "$HELPER" ]]; then
    source "$HELPER"
  else
    return 1
  fi
  start=$(_timer_start)
  [[ "$start" =~ ^[0-9]+$ ]]
  sleep 0.05
  dur=$(_timer_duration_ms "$start")
  [[ "$dur" =~ ^[0-9]+$ ]]
  # Duration should be ≥ 0 (at minimum non-negative; on second-granularity
  # systems sleep 0.05 may register as 0)
  [ "$dur" -ge 0 ]
}

# =========================================================================
# AC-3, AC-5: post-compact-marker.sh emits timing
# =========================================================================

@test "BTS-208 AC-3: post-compact-marker.sh emits timing on completion" {
  set -e
  run bash "$POST_COMPACT_HOOK"
  [ "$status" -eq 0 ]
  log="$PROJECT/.ccanvil/state/execution-timing.log"
  [ -f "$log" ]
  grep -q '"name":"post-compact-marker"' "$log"
}

# =========================================================================
# AC-4, AC-5: session-boundary.sh emits timing
# =========================================================================

@test "BTS-208 AC-4: session-boundary.sh emits timing on completion" {
  set -e
  run bash "$SESSION_BOUNDARY_HOOK"
  [ "$status" -eq 0 ]
  log="$PROJECT/.ccanvil/state/execution-timing.log"
  [ -f "$log" ]
  grep -q '"name":"session-boundary"' "$log"
}

# =========================================================================
# AC-6: timer-emit failure never blocks (regression)
# =========================================================================

@test "BTS-208 AC-6: hooks exit 0 even when timer-emit fails (read-only state dir)" {
  chmod 0555 "$PROJECT/.ccanvil/state"
  run bash "$POST_COMPACT_HOOK"
  rc=$status
  chmod 0755 "$PROJECT/.ccanvil/state"
  [ "$rc" -eq 0 ]
}

# =========================================================================
# Drift-guards
# =========================================================================

@test "BTS-208 drift: BTS-208 referenced inline in timer helper" {
  if [[ -f "$TIMER_HELPER" ]]; then
    grep -q "BTS-208" "$TIMER_HELPER"
  else
    grep -q "BTS-208" "$HELPER"
  fi
}

@test "BTS-208 drift: BTS-208 referenced inline in post-compact-marker.sh" {
  grep -q "BTS-208" "$POST_COMPACT_HOOK"
}

@test "BTS-208 drift: BTS-208 referenced inline in session-boundary.sh" {
  grep -q "BTS-208" "$SESSION_BOUNDARY_HOOK"
}
