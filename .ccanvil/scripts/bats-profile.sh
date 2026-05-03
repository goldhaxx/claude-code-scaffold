#!/usr/bin/env bash
# BTS-282 — bats-profile.sh
#
# Profiler for bats runs. Intercepts `bash <path>/<wrapped-script>` calls
# via a PATH-prefixed bash shim, logs {cmd, verb, elapsed_ms} to a temp
# trace file, and aggregates the trace into JSON
# `[{cmd, verb, count, total_ms, mean_ms}]` sorted by total_ms desc.
#
# Pure observation — does not modify the wrapped scripts. Re-entry guard
# (BTS_PROFILE_INSIDE) prevents nested bash invocations from double-counting.

# @manifest
# purpose: Profile a bats run by intercepting `bash <path>/<wrapped-script>` invocations via a PATH-prefixed bash shim, then aggregate per-(cmd, verb) timings into a JSON table sorted by total_ms descending. Pre-req for BTS-281's fork-pressure fixture work — provides the data that says which substrate calls dominate per-test CPU.
# input: positional <bats-file> (required; resolved against CWD)
# input: --top <N> (cap aggregation rows to top-N by total_ms; positive integer; non-int or zero exits 2)
# input: --wrap <cmd1,cmd2,...> (override the set of wrapped scripts; default: docs-check.sh,module-manifest.sh)
# input: env BTS_PROFILE_INSIDE (set by the bash shim during a wrapped invocation; prevents re-entry double-counting; not set by user)
# input: env BTS_PROFILE_TRACE_FILE (path the shim appends TSV trace lines to; not set by user)
# input: env BTS_PROFILE_REAL_BASH (absolute path to the real bash binary baked into the shim; not set by user)
# input: env BTS_PROFILE_WRAPPED_NAMES (space-separated list of wrapped script basenames; not set by user)
# output: stdout: bats raw output, then a JSON array `[{cmd, verb, count, total_ms, mean_ms}]` sorted by total_ms descending
# output: exit-code mirrors bats's exit (0 pass / non-zero fail / 2 invalid-arg)
# depends-on: bats
# depends-on: jq
# depends-on: perl
# depends-on: mktemp
# side-effect: writes-temp-file
# failure-mode: missing-bats-target | exit=2 | visible=stderr-error | mitigation=pass-existing-bats-file-path
# failure-mode: invalid-top | exit=2 | visible=stderr-error | mitigation=pass-positive-integer
# failure-mode: unresolvable-wrap-target | exit=2 | visible=stderr-error | mitigation=ensure-script-exists-on-PATH-or-in-.ccanvil/scripts
# contract: pure-observation-no-modification-of-wrapped-scripts
# contract: re-entry-guarded-via-BTS_PROFILE_INSIDE
# anchor: BTS-282 (origin)

set -uo pipefail

usage() {
  sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
}

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# BTS-282: default wrap set targets heavy-hitter substrate scripts as
# observed in hub/tests/ via grep audit (2026-05-02). ccanvil-sync.sh is
# by far the most-invoked (241 vs <10 for the others). Override via --wrap.
DEFAULT_WRAP=(ccanvil-sync.sh linear-query.sh docs-check.sh module-manifest.sh bats-report.sh operations.sh)

# --- argv parse ---
top=-1
wrap_csv=""
target=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --top)
      shift
      if [[ -z "${1:-}" || ! "$1" =~ ^[0-9]+$ ]] || (( "$1" == 0 )); then
        # @failure-mode: invalid-top
        echo "ERROR: --top requires a positive integer (got '${1:-}')" >&2
        exit 2
      fi
      top="$1"
      ;;
    --wrap)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "ERROR: --wrap requires a comma-separated list" >&2
        exit 2
      fi
      wrap_csv="$1"
      ;;
    --help|-h) usage; exit 0 ;;
    --) shift; target="${1:-}"; break ;;
    *) target="$1" ;;
  esac
  shift
done

if [[ -z "$target" ]]; then
  # @failure-mode: missing-bats-target
  echo "ERROR: bats target required" >&2
  exit 2
fi
if [[ ! -e "$target" ]]; then
  # @failure-mode: missing-bats-target
  echo "ERROR: bats target '$target' not found" >&2
  exit 2
fi

# --- resolve wrap set ---
if [[ -n "$wrap_csv" ]]; then
  IFS=',' read -ra wrap_list <<< "$wrap_csv"
else
  wrap_list=("${DEFAULT_WRAP[@]}")
fi

for name in "${wrap_list[@]}"; do
  if [[ ! -x "$REPO_ROOT/.ccanvil/scripts/$name" ]] && ! command -v "$name" >/dev/null 2>&1; then
    # @failure-mode: unresolvable-wrap-target
    echo "ERROR: --wrap target '$name' not found on PATH or under .ccanvil/scripts/" >&2
    exit 2
  fi
done

# --- prepare temp shim+trace ---
# @side-effect: writes-temp-file
profile_dir=$(mktemp -d "${TMPDIR:-/tmp}/bats-profile-$$.XXXXXX")
shim_dir="$profile_dir/bin"
trace_file="$profile_dir/trace.tsv"
mkdir -p "$shim_dir"
: > "$trace_file"
trap 'rm -rf "$profile_dir"' EXIT

# --- generate the bash shim ---
real_bash=$(command -v bash)
wrapped_names_str="${wrap_list[*]}"

cat > "$shim_dir/bash" <<SHIM
#!$real_bash
# bats-profile.sh shim. Intercepts \`bash <path>/<wrapped-script>\` only;
# all other bash invocations exec transparently. Hardcoded shebang to
# the resolved real bash so \`/usr/bin/env bash <shim>\` doesn't recurse
# back through our shim via the shim_dir-prefixed PATH.

__should_time=0
__cmd=""
if [[ -z "\${BTS_PROFILE_INSIDE:-}" ]] && [[ "\${1:-}" == *.sh ]] && [[ -f "\${1:-}" ]]; then
  __base=\$(basename "\$1")
  for __w in $wrapped_names_str; do
    if [[ "\$__base" == "\$__w" ]]; then
      __should_time=1
      __cmd="\$__base"
      break
    fi
  done
fi

if (( __should_time == 1 )); then
  __start=\$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' 2>/dev/null || echo 0)
  BTS_PROFILE_INSIDE=1 "$real_bash" "\$@"
  __rc=\$?
  __end=\$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' 2>/dev/null || echo 0)
  printf '%s\t%s\t%d\n' "\$__cmd" "\${2:-(none)}" "\$((__end - __start))" >> "$trace_file" 2>/dev/null
  exit \$__rc
else
  exec "$real_bash" "\$@"
fi
SHIM
chmod +x "$shim_dir/bash"

# --- run bats with shimmed PATH ---
PATH="$shim_dir:$PATH" bats "$target"
bats_exit=$?

# --- aggregate ---
if [[ -s "$trace_file" ]]; then
  jq -Rs --argjson top "$top" '
    split("\n")
    | map(select(length > 0)
          | split("\t")
          | {cmd: .[0], verb: .[1], ms: (.[2] | tonumber)})
    | group_by([.cmd, .verb])
    | map({
        cmd: .[0].cmd,
        verb: .[0].verb,
        count: length,
        total_ms: (map(.ms) | add),
        mean_ms: ((map(.ms) | add) / length | floor)
      })
    | sort_by(-.total_ms, -.count)
    | (if $top > 0 then .[:$top] else . end)
  ' < "$trace_file"
else
  echo "[]"
fi

exit "$bats_exit"
