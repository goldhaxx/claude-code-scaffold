#!/usr/bin/env bash
# BTS-118 — bats-report.sh
#
# Run the bats suite exactly once and emit structured output. Replaces the
# 3×-invocation pattern (bats | tail; bats | grep ok; bats | grep not ok)
# that was inflating /pr and /recall wall-time.
#
# Usage:
#   bats-report.sh [--parallel] [--json] [--] [<bats-args>...]
#
# Flags:
#   --parallel  Use GNU parallel via `bats --jobs N` (N = max(2, cpu/2)).
#               Falls back to serial with a WARN: if parallel is missing.
#   --json      Emit `{ok, not_ok, total, tail, raw_exit}` to stdout.
#   --help      Show this help and exit 0.
#
# Default target: `hub/tests/` (relative to CWD — run from the repo root).
# Pass explicit paths (file or dir) to override. Pass bats-native args
# (e.g. `-f 'filter'`) alongside; they're forwarded.
#
# Exit code mirrors bats's exit (0 on pass, non-zero on any failure).

set -uo pipefail

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

parallel_mode=0
json_mode=0
passthrough=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parallel) parallel_mode=1 ;;
    --json)     json_mode=1 ;;
    --help|-h)  usage; exit 0 ;;
    --)         shift; passthrough+=("$@"); break ;;
    *)          passthrough+=("$1") ;;
  esac
  shift
done

# Default target when none given. The script assumes hub/tests/ exists
# relative to CWD — run from the repo root.
has_path=0
for a in "${passthrough[@]+"${passthrough[@]}"}"; do
  if [[ "$a" != -* ]] && [[ -e "$a" ]]; then
    has_path=1
    break
  fi
done
if (( has_path == 0 )); then
  passthrough+=("hub/tests/")
fi

# Build the bats command.
bats_cmd=(bats)
if (( parallel_mode )); then
  # Honor BATS_REPORT_HAS_PARALLEL for testability: "0" forces the no-parallel
  # branch even when parallel is actually installed; unset or anything else
  # falls through to the normal `command -v` probe.
  if [[ "${BATS_REPORT_HAS_PARALLEL:-}" = "0" ]]; then
    has_parallel=0
  elif command -v parallel >/dev/null 2>&1; then
    has_parallel=1
  else
    has_parallel=0
  fi

  if (( has_parallel )); then
    cpus=$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)
    jobs=$((cpus / 2))
    (( jobs < 2 )) && jobs=2
    bats_cmd+=(--jobs "$jobs")
  else
    echo "WARN: --parallel requested but GNU parallel is not installed." >&2
    echo "" >&2
    echo "  To enable parallelism:" >&2
    echo "    brew install parallel   # macOS" >&2
    echo "" >&2
    echo "  Falling back to serial execution." >&2
  fi
fi
bats_cmd+=("${passthrough[@]+"${passthrough[@]}"}")

# Run bats ONCE, capture to tempfile.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

"${bats_cmd[@]}" > "$tmp" 2>&1
bats_exit=$?

ok=$(grep -cE '^ok ' "$tmp" 2>/dev/null || true)
not_ok=$(grep -cE '^not ok ' "$tmp" 2>/dev/null || true)
[[ -z "$ok" ]] && ok=0
[[ -z "$not_ok" ]] && not_ok=0
total=$((ok + not_ok))
tail_output=$(tail -3 "$tmp")

if (( json_mode )); then
  jq -n \
    --argjson ok "$ok" \
    --argjson not_ok "$not_ok" \
    --argjson total "$total" \
    --arg tail "$tail_output" \
    --argjson exit "$bats_exit" \
    '{ok:$ok, not_ok:$not_ok, total:$total, tail:$tail, raw_exit:$exit}'
else
  cat "$tmp"
  echo "---"
  echo "PASS: $ok / FAIL: $not_ok / TOTAL: $total"
fi

exit "$bats_exit"
