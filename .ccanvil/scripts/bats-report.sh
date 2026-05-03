#!/usr/bin/env bash
# BTS-118 — bats-report.sh
# BTS-137 — --timings / --slow-top N for per-test timing observability.
#
# Run the bats suite exactly once and emit structured output. Replaces the
# 3×-invocation pattern (bats | tail; bats | grep ok; bats | grep not ok)
# that was inflating /pr and /recall wall-time.

# @manifest
# purpose: Run the bats suite exactly once and derive PASS/FAIL/TOTAL counts, raw tail, optional per-test timings, and a wall_ms/jobs/cpus metrics envelope from a single capture — replaces the BTS-118 3×-invocation pattern (bats|tail; bats|grep ok; bats|grep not ok) that was 3× the wall-time. Optionally parallelizes via `bats --jobs N` when GNU parallel is installed; --jobs default uses the host's perf-core count via `sysctl -n hw.perflevel0.physicalcpu` (12 on M4 Max), falling back to logicalcpu/2.
# input: --parallel (use bats --jobs N where N defaults to perf-core count, falling back to logicalcpu/2)
# input: --json (emit structured {ok, not_ok, total, tail, raw_exit, timings, wall_ms, jobs, cpus} to stdout)
# input: --timings (run bats -T; append slowest-first timing table to human output)
# input: --slow-top <N> (cap timing rows to N slowest; N=0 emits zero rows; non-integer fails with exit 2)
# input: --help / -h (print usage and exit 0)
# input: env BATS_REPORT_HAS_PARALLEL (=0 forces no-parallel branch even when parallel is installed; testability hook)
# input: env BATS_REPORT_PERF_CORES (override the perf-core count probed via sysctl; testability + cross-host pinning)
# input: env BATS_REPORT_STATE_DIR (override the directory where bats-runs.jsonl is appended; defaults to .ccanvil/state)
# input: positional bats-args (target paths or filters like `-f 'pattern'`); defaults to `hub/tests/` when no path arg present
# output: stdout (default): bats raw output + `---` separator + `PASS: <N> / FAIL: <M> / TOTAL: <T>`; with --timings, second `---` + `Timings (slowest first):` table
# output: stdout (--json): JSON envelope `{ok, not_ok, total, tail, raw_exit, timings:[{test, ms}], wall_ms, jobs, cpus}`
# output: side-effect appends one line to .ccanvil/state/bats-runs.jsonl per run with shape {epoch, wall_ms, ok, not_ok, total, jobs, cpus, raw_exit, parallel}
# output: exit-code mirrors bats's exit (0 pass / non-zero fail / 2 invalid-arg)
# caller: skill:/pr
# caller: skill:/stasis
# caller: .claude/rules/tdd.md
# depends-on: bats
# depends-on: jq
# depends-on: mktemp
# depends-on: perl
# side-effect: writes-temp-file
# side-effect: writes-stderr-warn-on-missing-parallel
# side-effect: writes-bats-runs-jsonl
# failure-mode: invalid-slow-top | exit=2 | visible=stderr-error | mitigation=pass-non-negative-integer
# failure-mode: bats-suite-failed | exit=passthrough | visible=stdout-not-ok-lines | mitigation=fix-failing-test
# failure-mode: jsonl-append-failed | exit=passthrough | visible=stderr-warn | mitigation=ensure-state-dir-writable
# contract: single-bats-invocation
# contract: silent-fallback-warn-on-missing-parallel
# contract: counts-derived-from-single-capture
# contract: metrics-envelope-includes-wall_ms-jobs-cpus
# anchor: BTS-118 (origin)
# anchor: BTS-137 (--timings / --slow-top)
# anchor: BTS-251 (manifest seed)
# anchor: BTS-277 (perf-core default + metrics envelope + bats-runs.jsonl)
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
  # BTS-277: bumped range from 28→44 to surface new manifest fields
  # (BATS_REPORT_PERF_CORES / BATS_REPORT_STATE_DIR / wall_ms / jobs / cpus
  # / bats-runs.jsonl) in --help output.
  sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
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
    # BTS-277: prefer perf-core count over logical/2; env override wins.
    perf="${BATS_REPORT_PERF_CORES:-}"
    [[ -z "$perf" ]] && perf=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "")
    if [[ "$perf" =~ ^[0-9]+$ ]] && (( perf >= 2 )); then
      jobs="$perf"
    else
      jobs=$((cpus / 2))
      (( jobs < 2 )) && jobs=2
    fi
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

# BTS-277: resolve jobs_used / cpus_total for the metrics envelope.
# jobs is set above only when the parallel branch fires; default to 1.
jobs_used="${jobs:-1}"
cpus_total="${cpus:-}"
if [[ -z "$cpus_total" ]]; then
  cpus_total=$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 1)
fi

# Run bats ONCE, capture to tempfile.
# @side-effect: writes-temp-file
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# BTS-277: wall-time around the bats invocation. Use perl Time::HiRes
# (ships on macOS + Linux) for ms-precision; fall back to second-precision
# if perl is missing.
_now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' 2>/dev/null
  else
    echo "$(($(date +%s) * 1000))"
  fi
}
start_ms=$(_now_ms)
"${bats_cmd[@]}" > "$tmp" 2>&1
bats_exit=$?
end_ms=$(_now_ms)
wall_ms=$((end_ms - start_ms))
(( wall_ms < 0 )) && wall_ms=0
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
    --argjson wall_ms "$wall_ms" \
    --argjson jobs "$jobs_used" \
    --argjson cpus "$cpus_total" \
    '{ok:$ok, not_ok:$not_ok, total:$total, tail:$tail, raw_exit:$exit, timings:$timings, wall_ms:$wall_ms, jobs:$jobs, cpus:$cpus}'
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

# BTS-277: append run-summary to .ccanvil/state/bats-runs.jsonl (AC-3).
# State dir is overridable via BATS_REPORT_STATE_DIR for testability.
state_dir="${BATS_REPORT_STATE_DIR:-.ccanvil/state}"
jsonl_path="$state_dir/bats-runs.jsonl"
parallel_bool=false
(( parallel_mode == 1 )) && parallel_bool=true
jsonl_entry=$(jq -c -n \
  --argjson epoch "$(date +%s)" \
  --argjson wall_ms "$wall_ms" \
  --argjson ok "$ok" \
  --argjson not_ok "$not_ok" \
  --argjson total "$total" \
  --argjson jobs "$jobs_used" \
  --argjson cpus "$cpus_total" \
  --argjson raw_exit "$bats_exit" \
  --argjson parallel "$parallel_bool" \
  '{epoch:$epoch, wall_ms:$wall_ms, ok:$ok, not_ok:$not_ok, total:$total, jobs:$jobs, cpus:$cpus, raw_exit:$raw_exit, parallel:$parallel}')
# @side-effect: writes-bats-runs-jsonl
if mkdir -p "$state_dir" 2>/dev/null && printf '%s\n' "$jsonl_entry" >> "$jsonl_path" 2>/dev/null; then
  :
else
  # @failure-mode: jsonl-append-failed
  echo "WARN: bats-runs.jsonl append skipped — could not write $jsonl_path" >&2
fi

exit "$bats_exit"
