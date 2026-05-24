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
# input: --progress (BTS-383: streaming progress mode. With --parallel: defers to native `bats --jobs N` for speed + spawns periodic heartbeat (no per-file lines, since parallel TAP interleaves). Without --parallel: per-file orchestrated mode; emits `[N/M] <file>: PASS X/Y in T.Ts` on stderr after each file completes; aggregates output for the existing summary/JSON pipeline. Heartbeat fires in both sub-modes.)
# input: env BATS_PROGRESS_HEARTBEAT_SECS (override --progress heartbeat interval in seconds; default 30; non-positive disables heartbeat)
# input: --help / -h (print usage and exit 0)
# input: env BATS_REPORT_HAS_PARALLEL (=0 forces no-parallel branch even when parallel is installed; testability hook)
# input: env BATS_REPORT_PERF_CORES (override the perf-core count probed via sysctl; testability + cross-host pinning)
# input: env BATS_REPORT_STATE_DIR (override the directory where bats-runs.jsonl is appended; defaults to .ccanvil/state)
# input: --no-telemetry (BTS-497: opt out of OTel observability — disables the bats helper's per-test span emission AND skips the post-run otel-flatten.sh invocation; exports CCANVIL_TELEMETRY_DISABLED=1 to the bats subprocess)
# input: env BTS_RUN_ID (BTS-497: override the suite-run identifier shared across the bats helper's span emissions and the post-run otel-flatten.sh filter; defaults to <epoch>-<pid>)
# input: env OTEL_FLATTEN_INPUT (BTS-497: override the raw-traces.jsonl path otel-flatten.sh reads; testability hook)
# input: env OTEL_FLATTEN_OUTPUT (BTS-497: override the test-runs.jsonl path otel-flatten.sh writes; testability hook)
# input: positional bats-args (target paths or filters like `-f 'pattern'`); defaults to `hub/tests/` when no path arg present
# output: stdout (default): bats raw output + `---` separator + `PASS: <N> / FAIL: <M> / TOTAL: <T>`; with --timings, second `---` + `Timings (slowest first):` table
# output: stdout (--json): JSON envelope `{ok, not_ok, total, tail, raw_exit, timings:[{test, ms}], failures:[{test_name, file, line_number, error_excerpt}], wall_ms, jobs, cpus}`
# output: side-effect appends one line to .ccanvil/state/bats-runs.jsonl per run with shape {epoch, wall_ms, ok, not_ok, total, jobs, cpus, raw_exit, parallel, failures:[{test_name, file, line_number, error_excerpt}]}
# output: stderr (--progress, BTS-383): per-file completion lines `[N/M] <file>: PASS|FAIL X/Y in T.Ts`
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
# side-effect: invokes-otel-flatten
# side-effect: emits-otel-spans
# failure-mode: invalid-slow-top | exit=2 | visible=stderr-error | mitigation=pass-non-negative-integer
# failure-mode: bats-suite-failed | exit=passthrough | visible=stdout-not-ok-lines | mitigation=fix-failing-test
# failure-mode: jsonl-append-failed | exit=passthrough | visible=stderr-warn | mitigation=ensure-state-dir-writable
# failure-mode: flatten-failed | exit=78 | visible=stderr-error | mitigation=start-otel-collector-or-pass-no-telemetry
# contract: single-bats-invocation
# contract: silent-fallback-warn-on-missing-parallel
# contract: counts-derived-from-single-capture
# contract: metrics-envelope-includes-wall_ms-jobs-cpus
# contract: exit-78-on-flatten-failure-supersedes-bats-exit
# contract: span-emission-never-alters-exit-code
# anchor: BTS-118 (origin)
# anchor: BTS-137 (--timings / --slow-top)
# anchor: BTS-251 (manifest seed)
# anchor: BTS-277 (perf-core default + metrics envelope + bats-runs.jsonl)
# anchor: BTS-383 (--progress per-file orchestration + heartbeat + per-failure detail)
# anchor: BTS-497 (post-run otel-flatten + exit-78 precedence + --no-telemetry escape hatch)
# anchor: BTS-560 (test-suite-run end-to-end trace — root + phase spans)
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
  # BTS-383: bumped range from 44→47 to surface --progress + stderr-progress
  # output line + BTS-383 anchor.
  sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'
}

parallel_mode=0
json_mode=0
timings_mode=0
progress_mode=0
no_telemetry=0
slow_top=-1
passthrough=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parallel) parallel_mode=1 ;;
    --json)     json_mode=1 ;;
    --timings)  timings_mode=1 ;;
    --progress) progress_mode=1 ;;
    --no-telemetry)
      # BTS-497 Step 14: opt out of BTS-497 test-observability entirely.
      # (a) disables the bats telemetry helper's per-test span emission so
      #     the suite runs without needing the OTel Collector,
      # (b) skips the post-run otel-flatten.sh invocation so a missing
      #     raw-traces.jsonl does not propagate exit 78.
      # Used by substrate self-tests and any caller that wants the suite
      # to be observability-independent.
      no_telemetry=1
      export CCANVIL_TELEMETRY_DISABLED=1
      ;;
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

# BTS-497: anchor a stable BTS_RUN_ID for the suite run. The telemetry helper
# (hub/tests/_helpers/telemetry.bash) reads this to tag every span; the
# AC-12d flatten step below passes the same value to otel-flatten.sh so it
# filters to spans from THIS run. Honors an externally-set value (CI may
# want a deterministic id).
export BTS_RUN_ID="${BTS_RUN_ID:-$(date +%s)-$$}"

# BTS-504 follow-up: emit ONE trace_id per suite run so every test span across
# every parallel worker shares the same OTel trace. Grafana / Tempo then
# renders the whole bats invocation as a single waterfall — parallel files
# appear as stacked swimlanes; tests within a file appear as sequential bars.
# Honors externally-set value. 32 lowercase hex chars per W3C Trace Context.
if [[ -z "${BTS_TELEMETRY_TRACE_ID:-}" ]] && command -v openssl >/dev/null 2>&1; then
  export BTS_TELEMETRY_TRACE_ID="$(openssl rand -hex 16 2>/dev/null)"
fi
# Suite-level root span: bats-report owns the suite root; per-file spans
# (telemetry_setup_file/teardown_file) become its children; per-test spans
# become grandchildren via the file span. The hierarchy renders in Tempo /
# Grafana as a proper drill-down waterfall.
if [[ -z "${BTS_TELEMETRY_SUITE_SPAN_ID:-}" ]] && command -v openssl >/dev/null 2>&1; then
  export BTS_TELEMETRY_SUITE_SPAN_ID="$(openssl rand -hex 8 2>/dev/null)"
fi
# BTS-560: capture the run-trace start BEFORE the suite start so the
# test-suite-run root span fully wraps the bats-suite span in the waterfall.
export BTS_TELEMETRY_RUN_START_EPOCH="$(date +%s.%N 2>/dev/null || date +%s)"
export BTS_TELEMETRY_SUITE_START_EPOCH="$(date +%s.%N 2>/dev/null || date +%s)"

# BTS-560: end-to-end run trace. Source otel-span.sh once so every phase span
# (manifest pre-warm, bats suite, otel-flatten) and the test-suite-run root
# span emit through the shared helper. A missing/broken helper must never
# corrupt the suite exit code — the whole trace is best-effort.
_otel_span_ready=0
_otel_span_lib="$(dirname "${BASH_SOURCE[0]}")/../observability/otel-span.sh"
if [[ -f "$_otel_span_lib" ]] && source "$_otel_span_lib" 2>/dev/null; then
  _otel_span_ready=1
fi
# Run-trace root span id — every phase span parents under it. Honors an
# externally-set value (mirrors BTS_TELEMETRY_TRACE_ID / _SUITE_SPAN_ID).
# BTS_TELEMETRY_RUN_START_EPOCH is captured earlier, beside the suite start.
if [[ -z "${BTS_TELEMETRY_RUN_SPAN_ID:-}" ]] && command -v openssl >/dev/null 2>&1; then
  export BTS_TELEMETRY_RUN_SPAN_ID="$(openssl rand -hex 8 2>/dev/null)"
fi

# BTS-544: read .ccanvil/state/session-trace.json (when present) so the
# test-suite-run + bats-suite spans can carry session.id + claude_session_id
# as attrs — linking the suite trace to the rooted ccanvil-session trace
# without merging them. Fail-soft: a missing/malformed file leaves both vars
# empty; the omit-when-empty append pattern below drops the attrs entirely.
_bts_session_state_file="${BATS_REPORT_STATE_DIR:-.ccanvil/state}/session-trace.json"
BTS_SESSION_ID=""
BTS_CLAUDE_SESSION_ID=""
if [[ -f "$_bts_session_state_file" ]]; then
  BTS_SESSION_ID="$(jq -r '.session_id // ""' < "$_bts_session_state_file" 2>/dev/null)"
  BTS_CLAUDE_SESSION_ID="$(jq -r '.claude_session_id // ""' < "$_bts_session_state_file" 2>/dev/null)"
fi

# Gate shared by every phase/root span emission below. Honors the OTEL_SPAN_CLI
# test seam so the recording-stub harness works without a real otel-cli on PATH.
_otel_trace_live() {
  (( no_telemetry == 0 )) \
    && (( _otel_span_ready == 1 )) \
    && [[ -n "${BTS_TELEMETRY_TRACE_ID:-}" ]] \
    && [[ -n "${BTS_TELEMETRY_RUN_SPAN_ID:-}" ]] \
    && command -v "${OTEL_SPAN_CLI:-otel-cli}" >/dev/null 2>&1
}

# BTS-281: pre-warm module-manifest validate JSON ONCE before the suite runs,
# expose via env var. The 4 bats files that need this read the cached path
# instead of re-running validate. Skip when caller already set the env var
# (allows opt-out + lets bats files run standalone with their own cache).
# BTS-560: wrap the pre-warm in a `manifest pre-warm` phase span so the
# (often multi-minute) validate is visible in the end-to-end run trace.
if [[ -z "${BTS_MANIFEST_VALIDATE_CACHE:-}" ]] && [[ -x .ccanvil/scripts/module-manifest.sh ]]; then
  _prewarm_start_epoch="$(date +%s.%N 2>/dev/null || date +%s)"
  __mm_cache=$(mktemp -t bts-281-manifest-validate.XXXXXX)
  if bash .ccanvil/scripts/module-manifest.sh validate --json > "$__mm_cache" 2>/dev/null; then
    export BTS_MANIFEST_VALIDATE_CACHE="$__mm_cache"
  else
    rm -f "$__mm_cache" 2>/dev/null
  fi
  if _otel_trace_live; then
    # BTS-560: emit in a subshell so otel_span_init's env exports
    # (OTEL_SPAN_INIT_DONE / OTEL_SPAN_LIVE) do NOT leak into the bats
    # subprocess that runs next — leaked init state would defeat the
    # telemetry-disabled / Collector-unreachable paths in the test suite. The
    # suite/root span emits run AFTER bats, so only this one needs isolation.
    (
      otel_span_emit \
        --service ccanvil-test \
        --name "manifest pre-warm" \
        --start "$_prewarm_start_epoch" \
        --end "$(date +%s.%N 2>/dev/null || date +%s)" \
        --trace-id "$BTS_TELEMETRY_TRACE_ID" \
        --parent-id "$BTS_TELEMETRY_RUN_SPAN_ID" \
        --attrs "phase=manifest-prewarm,run.id=$BTS_RUN_ID" \
        --timeout 5s
    )
  fi
fi

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
trap '[[ -n "${hb_pid:-}" ]] && kill "$hb_pid" 2>/dev/null; rm -f "$tmp" "${BTS_MANIFEST_VALIDATE_CACHE:-}"' EXIT INT TERM

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

# BTS-383 AC-2: parse the captured TAP for `not ok` records + the indented
# `# (in test file <path>, line N)` and `#   ...` annotations bats emits
# below them. Emit a JSON array `[{test_name, file, line_number,
# error_excerpt}, ...]`. Empty array when there are no failures.
_parse_failures() {
  local tap_file="$1"
  perl -e '
    use strict; use warnings;
    use JSON::PP;
    my @failures;
    my $current;
    while (my $line = <STDIN>) {
      chomp $line;
      if ($line =~ /^not ok \d+ - (.+?)(?:\s+in \d+ms)?$/ ||
          $line =~ /^not ok \d+ (.+?)(?:\s+in \d+ms)?$/) {
        push @failures, $current if $current;
        $current = {
          test_name     => $1,
          file          => "",
          line_number   => undef,
          error_excerpt => "",
        };
      } elsif ($line =~ /^ok /) {
        push @failures, $current if $current;
        $current = undef;
      } elsif (defined $current) {
        if ($line =~ /^# \(in test file (.+), line (\d+)\)/ ||
            $line =~ /^# \(from .+ in test file (.+), line (\d+)\)/) {
          $current->{file}        = $1;
          $current->{line_number} = $2 + 0;
        } elsif ($line =~ /^# (.+)$/) {
          $current->{error_excerpt} .= "\n" if length $current->{error_excerpt};
          $current->{error_excerpt} .= $1;
        }
      }
    }
    push @failures, $current if $current;
    print encode_json(\@failures);
  ' < "$tap_file"
}
start_ms=$(_now_ms)
if (( progress_mode )); then
  # BTS-383 streaming progress. Two sub-modes:
  #
  # (a) --progress + --parallel: keep native `bats --jobs N` for speed
  #     (TAP from parallel jobs interleaves so per-file `[N/M]` boundaries
  #     are not extractable in a useful order); spawn ONLY a periodic
  #     heartbeat so 0-byte stderr is impossible during the run. This is
  #     the canonical /pr full-suite path.
  #
  # (b) --progress alone (no --parallel): per-file orchestration. Walk
  #     the passthrough list, expand directories to top-level *.bats
  #     files, run each as a separate `bats <args> <file>` subprocess,
  #     emit `[N/M] <file>: PASS X/Y in T.Ts` to stderr as each
  #     completes. Aggregate captured TAP into $tmp so the existing
  #     summary, --json, --timings, and bats-runs.jsonl pipelines stay
  #     unchanged.
  #
  # Heartbeat is shared across both branches. Cleanup trap above kills
  # the process on EXIT/INT/TERM.
  hb_secs="${BATS_PROGRESS_HEARTBEAT_SECS:-30}"
  if [[ "$hb_secs" =~ ^[0-9]+$ ]] && (( hb_secs > 0 )); then
    (
      hb_elapsed=0
      while sleep "$hb_secs"; do
        hb_elapsed=$((hb_elapsed + hb_secs))
        printf '[heartbeat] still working — %ds elapsed\n' "$hb_elapsed" >&2
      done
    ) &
    hb_pid=$!
  fi

  if (( parallel_mode )); then
    # Branch (a) — defer to native bats --jobs N (already in $bats_cmd).
    "${bats_cmd[@]}" > "$tmp" 2>&1
    bats_exit=$?
  else
    # Branch (b) — per-file orchestration with [N/M] emission.
    bp_files=()
    bp_extra_args=()
    for p in "${passthrough[@]+"${passthrough[@]}"}"; do
      if [[ "$p" == -* ]]; then
        bp_extra_args+=("$p")
      elif [[ -d "$p" ]]; then
        while IFS= read -r f; do bp_files+=("$f"); done < <(find "$p" -maxdepth 1 -name '*.bats' -type f | sort)
      elif [[ -f "$p" ]]; then
        bp_files+=("$p")
      fi
    done
    bp_total="${#bp_files[@]}"
    bats_exit=0
    for (( bp_i = 0; bp_i < bp_total; bp_i++ )); do
      bp_f="${bp_files[$bp_i]}"
      bp_start=$(_now_ms)
      bp_cmd=(bats)
      (( timings_mode )) && bp_cmd+=(-T)
      if (( ${#bp_extra_args[@]} > 0 )); then
        bp_cmd+=("${bp_extra_args[@]}")
      fi
      bp_cmd+=("$bp_f")
      bp_filetmp=$(mktemp)
      "${bp_cmd[@]}" > "$bp_filetmp" 2>&1
      bp_exit=$?
      bp_end=$(_now_ms)
      bp_ms=$((bp_end - bp_start))
      bp_ok=$(grep -cE '^ok ' "$bp_filetmp" 2>/dev/null || true)
      bp_not_ok=$(grep -cE '^not ok ' "$bp_filetmp" 2>/dev/null || true)
      [[ -z "$bp_ok" ]] && bp_ok=0
      [[ -z "$bp_not_ok" ]] && bp_not_ok=0
      bp_filetotal=$((bp_ok + bp_not_ok))
      if (( bp_not_ok > 0 )); then
        bp_label="FAIL ${bp_ok}/${bp_filetotal}"
      else
        bp_label="PASS ${bp_ok}/${bp_filetotal}"
      fi
      bp_secs=$(awk -v ms="$bp_ms" 'BEGIN{ printf "%.1fs", ms/1000 }')
      printf '[%d/%d] %s: %s in %s\n' "$((bp_i + 1))" "$bp_total" "$(basename "$bp_f")" "$bp_label" "$bp_secs" >&2
      cat "$bp_filetmp" >> "$tmp"
      rm -f "$bp_filetmp"
      (( bp_exit > bats_exit )) && bats_exit=$bp_exit
    done
  fi
else
  "${bats_cmd[@]}" > "$tmp" 2>&1
  bats_exit=$?
fi
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

# BTS-383 AC-2/AC-3: per-failure detail array. Computed unconditionally so
# both --json output AND the bats-runs.jsonl writer below can reference it.
# Empty when not_ok == 0.
if (( not_ok > 0 )); then
  failures_json=$(_parse_failures "$tmp")
  [[ -z "$failures_json" ]] && failures_json='[]'
else
  failures_json='[]'
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
    --argjson failures "$failures_json" \
    --argjson wall_ms "$wall_ms" \
    --argjson jobs "$jobs_used" \
    --argjson cpus "$cpus_total" \
    '{ok:$ok, not_ok:$not_ok, total:$total, tail:$tail, raw_exit:$exit, timings:$timings, failures:$failures, wall_ms:$wall_ms, jobs:$jobs, cpus:$cpus}'
else
  cat "$tmp"
  echo "---"
  # BTS-497 AC-11: surface parallelization config in human stdout. JSON mode
  # already carries jobs/cpus/wall_ms; this closes the long-standing visibility
  # gap (operator-flagged 2026-05-16) where the config was buried in
  # bats-runs.jsonl alone.
  if (( parallel_mode == 1 )); then
    wall_s=$(awk "BEGIN { printf \"%.1f\", $wall_ms / 1000.0 }")
    echo "parallel: jobs=$jobs_used cpus=$cpus_total wall=${wall_s}s"
  fi
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
  --argjson failures "$failures_json" \
  '{epoch:$epoch, wall_ms:$wall_ms, ok:$ok, not_ok:$not_ok, total:$total, jobs:$jobs, cpus:$cpus, raw_exit:$raw_exit, parallel:$parallel, failures:$failures}')
# @side-effect: writes-bats-runs-jsonl
if mkdir -p "$state_dir" 2>/dev/null && printf '%s\n' "$jsonl_entry" >> "$jsonl_path" 2>/dev/null; then
  :
else
  # @failure-mode: jsonl-append-failed
  echo "WARN: bats-runs.jsonl append skipped — could not write $jsonl_path" >&2
fi

# BTS-508 AC-7: write test-state full-suite marker on exit-0 when invoked as
# the canonical full-suite (gated by BATS_REPORT_FULL_SUITE=1, set by the
# docs-check.sh test-suite-run dispatcher). Single-file invocations from
# BTS-507 stub-helper tests and TDD inner loops skip the writer so they
# never pollute the real state file.
if [[ "${BATS_REPORT_FULL_SUITE:-0}" == "1" && "$bats_exit" -eq 0 ]]; then
  ts_file="$state_dir/test-state.json"
  ts_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
  if [[ -n "$ts_sha" ]]; then
    ts_prior="{}"
    if [[ -f "$ts_file" ]]; then
      ts_prior=$(cat "$ts_file" 2>/dev/null)
      if ! printf '%s' "$ts_prior" | jq -e . >/dev/null 2>&1; then
        ts_prior="{}"
      fi
    fi
    ts_epoch=$(date +%s)
    mkdir -p "$state_dir" 2>/dev/null
    if printf '%s' "$ts_prior" | jq --arg sha "$ts_sha" --argjson at "$ts_epoch" \
      '. + {last_full_suite_commit: $sha, last_full_suite_at: $at}' \
      > "$ts_file.tmp" 2>/dev/null; then
      mv "$ts_file.tmp" "$ts_file"
    else
      rm -f "$ts_file.tmp"
      echo "WARN: test-state full-suite write skipped — could not update $ts_file" >&2
    fi
  fi
fi

# BTS-497 AC-12d: invoke otel-flatten.sh after every --parallel run.
# Exit-code precedence rule: when flatten fails, propagate 78 regardless
# of bats_exit (flatten failure is the "running blind" signal that AC-2
# guards against and must always surface). When flatten succeeds, exit
# with bats_exit so test failures propagate normally for CI consumers.
# The bats_exit is preserved in bats-runs.jsonl's raw_exit field
# regardless of which code is propagated, so JSON consumers can still
# distinguish test-failure runs even when 78 is the exit code.
final_exit="$bats_exit"

# BTS-504 follow-up: emit the SUITE root span now that bats is done. All
# file + test spans emitted during the run share this trace_id; the suite
# span is their common parent (file spans set parent_span_id =
# $BTS_TELEMETRY_SUITE_SPAN_ID; test spans set parent_span_id =
# $BTS_TELEMETRY_FILE_SPAN_ID). Grafana then renders the trace as a
# nested hierarchical waterfall: suite → files → tests.
if _otel_trace_live && [[ -n "${BTS_TELEMETRY_SUITE_SPAN_ID:-}" ]]; then
  suite_end_epoch="$(date +%s.%N 2>/dev/null || date +%s)"
  suite_status="unset"
  (( bats_exit != 0 )) && suite_status="error"
  # BTS-543: emit via the shared otel-span.sh helper (sourced once up top).
  # BTS-560: the bats-suite phase span parents under the test-suite-run root.
  otel_span_emit \
    --service ccanvil-test \
    --name "bats suite ($BTS_RUN_ID)" \
    --start "$BTS_TELEMETRY_SUITE_START_EPOCH" \
    --end "$suite_end_epoch" \
    --status "$suite_status" \
    --trace-id "$BTS_TELEMETRY_TRACE_ID" \
    --span-id "$BTS_TELEMETRY_SUITE_SPAN_ID" \
    --parent-id "$BTS_TELEMETRY_RUN_SPAN_ID" \
    --attrs "phase=bats-suite,suite.kind=bats,suite.parallel=${parallel_mode},suite.jobs=${jobs:-1},suite.total=${total:-0},suite.passed=${ok:-0},suite.failed=${not_ok:-0},run.id=$BTS_RUN_ID,git.sha=$(git rev-parse HEAD 2>/dev/null || echo unknown)${BTS_SESSION_ID:+,session.id=$BTS_SESSION_ID}${BTS_CLAUDE_SESSION_ID:+,claude_session_id=$BTS_CLAUDE_SESSION_ID}" \
    --timeout 5s
fi

if (( parallel_mode == 1 )) && (( no_telemetry == 0 )); then
  # @side-effect: invokes-otel-flatten
  # CCANVIL_TELEMETRY_DISABLED gates only the bats HELPER's per-test
  # emission, NOT the post-run flatten (which reads OTEL_FLATTEN_INPUT
  # directly and may operate on data from external sources). The
  # --no-telemetry flag (Step 14) is the proper opt-out for both layers.
  flatten_script=".ccanvil/observability/otel-flatten.sh"
  _flatten_start_epoch="$(date +%s.%N 2>/dev/null || date +%s)"
  _flatten_status="unset"
  if [[ -x "$flatten_script" ]]; then
    if ! bash "$flatten_script" "$BTS_RUN_ID" >&2; then
      # @failure-mode: flatten-failed
      final_exit=78
      _flatten_status="error"
    fi
  else
    echo "WARN: $flatten_script missing — flatten step skipped" >&2
    # BTS-560: a missing flatten script means the phase did not complete —
    # record error, not unset (unset would read as "ran fine" in Tempo).
    _flatten_status="error"
  fi
  # BTS-560: emit the otel-flatten phase span under the test-suite-run root.
  if _otel_trace_live; then
    otel_span_emit \
      --service ccanvil-test \
      --name "otel-flatten" \
      --start "$_flatten_start_epoch" \
      --end "$(date +%s.%N 2>/dev/null || date +%s)" \
      --status "$_flatten_status" \
      --trace-id "$BTS_TELEMETRY_TRACE_ID" \
      --parent-id "$BTS_TELEMETRY_RUN_SPAN_ID" \
      --attrs "phase=otel-flatten,run.id=$BTS_RUN_ID" \
      --timeout 5s
  fi
fi

# BTS-560: emit the test-suite-run ROOT span — the common parent of the
# manifest-prewarm / bats-suite / otel-flatten phase spans. Emitted last (its
# true wall-clock duration is known only now); the trace id + run span id were
# established before the pre-warm so every phase span could nest under it.
if _otel_trace_live; then
  run_end_epoch="$(date +%s.%N 2>/dev/null || date +%s)"
  run_status="unset"
  (( bats_exit != 0 )) && run_status="error"
  # @side-effect: emits-otel-spans
  otel_span_emit \
    --service ccanvil-test \
    --name "test-suite-run" \
    --start "$BTS_TELEMETRY_RUN_START_EPOCH" \
    --end "$run_end_epoch" \
    --status "$run_status" \
    --trace-id "$BTS_TELEMETRY_TRACE_ID" \
    --span-id "$BTS_TELEMETRY_RUN_SPAN_ID" \
    --attrs "run.id=$BTS_RUN_ID,git.sha=$(git rev-parse HEAD 2>/dev/null || echo unknown),suite.total=${total:-0},suite.passed=${ok:-0},suite.failed=${not_ok:-0}${BTS_SESSION_ID:+,session.id=$BTS_SESSION_ID}${BTS_CLAUDE_SESSION_ID:+,claude_session_id=$BTS_CLAUDE_SESSION_ID}" \
    --timeout 5s
fi

exit "$final_exit"
