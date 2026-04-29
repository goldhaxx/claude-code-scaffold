#!/usr/bin/env bash
# BTS-118 — bats-report.sh
# BTS-137 — --timings / --slow-top N for per-test timing observability.
#
# Run the bats suite exactly once and emit structured output. Replaces the
# 3×-invocation pattern (bats | tail; bats | grep ok; bats | grep not ok)
# that was inflating /pr and /recall wall-time.

# @manifest
# purpose: Run the bats suite exactly once and derive PASS/FAIL/TOTAL counts, raw tail, and optional per-test timings from a single capture — replaces the BTS-118 3×-invocation pattern (bats|tail; bats|grep ok; bats|grep not ok) that was 3× the wall-time. Optionally parallelizes via `bats --jobs N` when GNU parallel is installed.
# input: --parallel (use bats --jobs N where N=max(2, cpu/2))
# input: --json (emit structured {ok, not_ok, total, tail, raw_exit, timings} to stdout)
# input: --timings (run bats -T; append slowest-first timing table to human output)
# input: --slow-top <N> (cap timing rows to N slowest; N=0 emits zero rows; non-integer fails with exit 2)
# input: --help / -h (print usage and exit 0)
# input: env BATS_REPORT_HAS_PARALLEL (=0 forces no-parallel branch even when parallel is installed; testability hook)
# input: positional bats-args (target paths or filters like `-f 'pattern'`); defaults to `hub/tests/` when no path arg present
# output: stdout (default): bats raw output + `---` separator + `PASS: <N> / FAIL: <M> / TOTAL: <T>`; with --timings, second `---` + `Timings (slowest first):` table
# output: stdout (--json): JSON envelope `{ok, not_ok, total, tail, raw_exit, timings:[{test, ms}]}`
# output: exit-code mirrors bats's exit (0 pass / non-zero fail / 2 invalid-arg)
# caller: skill:/pr
# caller: skill:/stasis
# caller: .claude/rules/tdd.md
# depends-on: bats
# depends-on: jq
# depends-on: mktemp
# side-effect: writes-temp-file
# side-effect: writes-stderr-warn-on-missing-parallel
# failure-mode: invalid-slow-top | exit=2 | visible=stderr-error | mitigation=pass-non-negative-integer
# failure-mode: bats-suite-failed | exit=passthrough | visible=stdout-not-ok-lines | mitigation=fix-failing-test
# contract: single-bats-invocation
# contract: silent-fallback-warn-on-missing-parallel
# contract: counts-derived-from-single-capture
# anchor: BTS-118 (origin)
# anchor: BTS-137 (--timings / --slow-top)
# anchor: BTS-251 (manifest seed)
#
# Usage:
#   bats-report.sh [--parallel] [--json] [--timings] [--slow-top N] [--] [<bats-args>...]
#
# Flags:
#   --parallel      Use GNU parallel via `bats --jobs N` (N = max(2, cpu/2)).
#                   Falls back to serial with a WARN: if parallel is missing.
#   --json          Emit `{ok, not_ok, total, tail, raw_exit, timings}` to stdout.
#   --timings       Run bats with `-T`; append a sorted per-test timing table
#                   (slowest first) to human output. JSON mode populates the
#                   `timings` array with `[{test, ms}]` entries.
#   --slow-top N    Like --timings but emits only the N slowest tests. N must
#                   be a non-negative integer. N=0 emits zero timing rows.
#   --help          Show this help and exit 0.
#
# Default target: `hub/tests/` (relative to CWD — run from the repo root).
# Pass explicit paths (file or dir) to override. Pass bats-native args
# (e.g. `-f 'filter'`) alongside; they're forwarded.
#
# Exit code mirrors bats's exit (0 on pass, non-zero on any failure).
# Exit 2 for invalid arguments (e.g., --slow-top with non-integer).

set -uo pipefail

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

parallel_mode=0
json_mode=0
timings_mode=0
slow_top=-1
passthrough=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parallel) parallel_mode=1 ;;
    --json)     json_mode=1 ;;
    --timings)  timings_mode=1 ;;
    --slow-top)
      timings_mode=1
      shift
      if [[ -z "${1:-}" || ! "$1" =~ ^[0-9]+$ ]]; then
        # @failure-mode: invalid-slow-top
        echo "ERROR: --slow-top requires a non-negative integer argument" >&2
        exit 2
      fi
      slow_top="$1"
      ;;
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
if (( timings_mode )); then
  bats_cmd+=(-T)
fi
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
    # @side-effect: writes-stderr-warn-on-missing-parallel
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
# @side-effect: writes-temp-file
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

"${bats_cmd[@]}" > "$tmp" 2>&1
bats_exit=$?
# @failure-mode: bats-suite-failed

ok=$(grep -cE '^ok ' "$tmp" 2>/dev/null || true)
not_ok=$(grep -cE '^not ok ' "$tmp" 2>/dev/null || true)
[[ -z "$ok" ]] && ok=0
[[ -z "$not_ok" ]] && not_ok=0
total=$((ok + not_ok))
tail_output=$(tail -3 "$tmp")

# BTS-137: parse per-test timings when --timings was requested. bats with -T
# emits `ok N <test name> in Nms` (and `not ok N ... in Nms`). Parse into
# tab-separated `ms<TAB>test-name` lines sorted slowest-first. When
# --slow-top is set, cap to that count (0 = empty).
timings_tsv=""
if (( timings_mode )); then
  timings_tsv=$(grep -E '^(ok|not ok) [0-9]+ .+ in [0-9]+ms$' "$tmp" 2>/dev/null \
    | sed -E 's/^(ok|not ok) [0-9]+ (.+) in ([0-9]+)ms$/\3	\2/' \
    | sort -rn || true)
  if [[ "$slow_top" -ge 0 ]]; then
    if [[ "$slow_top" -eq 0 ]]; then
      timings_tsv=""
    else
      timings_tsv=$(echo "$timings_tsv" | head -n "$slow_top")
    fi
  fi
fi

if (( json_mode )); then
  # Build timings JSON array from the TSV. Empty input → [].
  if [[ -n "$timings_tsv" ]]; then
    timings_json=$(echo "$timings_tsv" | jq -Rn '
      [inputs
       | select(length > 0)
       | split("\t")
       | {test: .[1], ms: (.[0] | tonumber)}]
    ')
  else
    timings_json='[]'
  fi
  jq -n \
    --argjson ok "$ok" \
    --argjson not_ok "$not_ok" \
    --argjson total "$total" \
    --arg tail "$tail_output" \
    --argjson exit "$bats_exit" \
    --argjson timings "$timings_json" \
    '{ok:$ok, not_ok:$not_ok, total:$total, tail:$tail, raw_exit:$exit, timings:$timings}'
else
  cat "$tmp"
  echo "---"
  echo "PASS: $ok / FAIL: $not_ok / TOTAL: $total"
  if (( timings_mode )) && [[ -n "$timings_tsv" ]]; then
    echo "---"
    echo "Timings (slowest first):"
    # Left-align: pad ms column to 6 chars.
    echo "$timings_tsv" | awk -F'\t' '{ printf "%-6s %s\n", $1, $2 }'
  fi
fi

exit "$bats_exit"
