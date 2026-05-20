#!/usr/bin/env bash
# BTS-543 — generic OpenTelemetry span helper.
#
# Sourceable bash library (no CLI dispatch). Any ccanvil script can `source`
# this and emit OTel spans to the local Collector without duplicating span
# mechanics. Extracted from hub/tests/_helpers/telemetry.bash (BTS-497) as the
# foundation of the Workflow Observability umbrella (BTS-542).
#
# Public functions:
#   otel_span_init             — resolve endpoint + one liveness probe (cached)
#   otel_span_cache_invariants — cache run.id / git.sha / project root
#   otel_span_new_trace_id     — echo 32 lowercase hex chars
#   otel_span_new_span_id      — echo 16 lowercase hex chars
#   otel_span_sanitize         — comma -> semicolon for otel-cli --attrs safety
#   otel_span_emit             — emit one completed span via otel-cli
#   otel_span_run              — wrap + time a command, emit a span, preserve rc
#
# Env overrides (the CCANVIL_* names match telemetry.bash's existing contract):
#   CCANVIL_OTLP_ENDPOINT      OTLP HTTP endpoint   (default http://127.0.0.1:4318)
#   CCANVIL_TELEMETRY_URL      healthcheck endpoint (default http://127.0.0.1:13133)
#   CCANVIL_TELEMETRY_DISABLED any value disables emission entirely
#   OTEL_SPAN_CLI              otel-cli binary name/path (default otel-cli) — test seam
#   OTEL_SPAN_NO_OPENSSL       any value forces the shasum ID fallback — test seam
#
# Never fails its caller: a down Collector, a missing otel-cli, or the disabled
# flag all degrade to a silent no-op. The bats helper layers its own hard-fail
# healthcheck on top — that decision is NOT delegated here.

# @manifest
# id: otel-span
# purpose: Generic OpenTelemetry span helper — a sourceable bash library owning span mechanics (trace/span ID generation, attribute sanitization, otel-cli emission, wrap-and-time) so any ccanvil script can emit OTel spans without duplicating bats-coupled code. Extracted from telemetry.bash (BTS-497) as the foundation of the Workflow Observability umbrella (BTS-542). Never fails its caller: a down Collector, missing otel-cli, or the disabled flag all degrade to a silent no-op.
# input: env CCANVIL_OTLP_ENDPOINT — OTLP HTTP endpoint (default http://127.0.0.1:4318)
# input: env CCANVIL_TELEMETRY_URL — Collector healthcheck endpoint (default http://127.0.0.1:13133)
# input: env CCANVIL_TELEMETRY_DISABLED — any value disables emission entirely
# input: function arguments — otel_span_emit and otel_span_run named flags
# output: OTel spans emitted to the local Collector via otel-cli (best-effort)
# output: exported cache vars OTEL_SPAN_ENDPOINT / OTEL_SPAN_LIVE / OTEL_SPAN_RUN_ID / OTEL_SPAN_GIT_SHA / OTEL_SPAN_PROJECT_ROOT
# caller: hub/tests/_helpers/telemetry.bash
# caller: .ccanvil/scripts/bats-report.sh
# depends-on: otel-cli
# depends-on: curl
# depends-on: openssl
# depends-on: git
# depends-on: date
# depends-on: shasum
# depends-on: awk
# side-effect: emits-otel-spans
# side-effect: exports-cache-env-vars
# failure-mode: collector-unreachable | exit=0 | visible=silent-no-op | mitigation=start-the-observability-stack
# failure-mode: otel-cli-missing | exit=0 | visible=silent-no-op | mitigation=brew-install-otel-cli
# contract: never-fails-caller
# contract: graceful-skip-when-collector-down
# contract: idempotent-init-probes-once-per-process
# anchor: BTS-543 (origin)
# anchor: BTS-542 (umbrella)

# --- ID generation ---------------------------------------------------------

# Echo nbytes*2 lowercase hex chars. openssl when available; a shasum-based
# fallback otherwise (offline / minimal hosts). OTEL_SPAN_NO_OPENSSL forces
# the fallback for tests. 32 lowercase hex chars per W3C Trace Context.
_otel_span_rand_hex() {
  local nbytes="$1"
  if [[ -z "${OTEL_SPAN_NO_OPENSSL:-}" ]] && command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$nbytes" 2>/dev/null
  else
    local nchars=$(( nbytes * 2 ))
    printf '%s' "$(date +%s%N 2>/dev/null || date +%s)-$$-${RANDOM}-${RANDOM}" \
      | shasum -a 256 | awk -v n="$nchars" '{print substr($1, 1, n)}'
  fi
}

otel_span_new_trace_id() { _otel_span_rand_hex 16; }
otel_span_new_span_id()  { _otel_span_rand_hex 8; }

# --- attribute sanitization ------------------------------------------------

# otel-cli's --attrs flag is comma-delimited with no escape mechanism, so
# every string-valued attribute must have its commas replaced (';' is the
# canonical substitute).
otel_span_sanitize() {
  local s="${1:-}"
  printf '%s' "${s//,/;}"
}

# --- invariant cache -------------------------------------------------------

# Cache run.id / git.sha / project root. Idempotent — honors pre-set values
# so a caller can pin them (e.g. one run.id for a whole multi-process run).
otel_span_cache_invariants() {
  export OTEL_SPAN_RUN_ID="${OTEL_SPAN_RUN_ID:-$(date +%s)-$$}"
  export OTEL_SPAN_GIT_SHA="${OTEL_SPAN_GIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
  if [[ -z "${OTEL_SPAN_PROJECT_ROOT:-}" ]]; then
    export OTEL_SPAN_PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD:-}")"
  fi
}

# --- init / endpoint discovery --------------------------------------------

# Resolve the OTLP endpoint and probe the Collector ONCE per process. Sets
# OTEL_SPAN_LIVE=1 only when otel-cli is present AND the Collector answers.
# CCANVIL_TELEMETRY_DISABLED forces OTEL_SPAN_LIVE=0 with no probe. Idempotent
# via OTEL_SPAN_INIT_DONE — which is also the seam tests use to pin the state.
otel_span_init() {
  if [[ -n "${OTEL_SPAN_INIT_DONE:-}" ]]; then
    return 0
  fi
  export OTEL_SPAN_ENDPOINT="${CCANVIL_OTLP_ENDPOINT:-http://127.0.0.1:4318}"
  export OTEL_SPAN_HEALTH_URL="${CCANVIL_TELEMETRY_URL:-http://127.0.0.1:13133}"
  if [[ -n "${CCANVIL_TELEMETRY_DISABLED:-}" ]]; then
    export OTEL_SPAN_LIVE=0
    export OTEL_SPAN_INIT_DONE=1
    return 0
  fi
  if command -v "${OTEL_SPAN_CLI:-otel-cli}" >/dev/null 2>&1 \
     && curl -fsS --max-time 2 "$OTEL_SPAN_HEALTH_URL" >/dev/null 2>&1; then
    export OTEL_SPAN_LIVE=1
  else
    export OTEL_SPAN_LIVE=0
  fi
  export OTEL_SPAN_INIT_DONE=1
  return 0
}

# --- emit a completed span -------------------------------------------------

# otel_span_emit --service S --name N --start E --end E [--status unset|error]
#                [--attrs K=V;...] [--trace-id 32hex] [--span-id 16hex]
#                [--parent-id 16hex] [--timeout Ns]
# Builds one otel-cli span invocation. Graceful no-op (return 0) when the
# Collector is not live. Emission failure is suppressed — never fatal.
otel_span_emit() {
  otel_span_init
  if [[ "${OTEL_SPAN_LIVE:-0}" != "1" ]]; then
    return 0
  fi
  local service="" name="" start="" end="" status="unset" attrs=""
  local trace_id="" span_id="" parent_id="" timeout="2s"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --service)   service="${2:-}";   shift 2 ;;
      --name)      name="${2:-}";      shift 2 ;;
      --start)     start="${2:-}";     shift 2 ;;
      --end)       end="${2:-}";       shift 2 ;;
      --status)    status="${2:-}";    shift 2 ;;
      --attrs)     attrs="${2:-}";     shift 2 ;;
      --trace-id)  trace_id="${2:-}";  shift 2 ;;
      --span-id)   span_id="${2:-}";   shift 2 ;;
      --parent-id) parent_id="${2:-}"; shift 2 ;;
      --timeout)   timeout="${2:-}";   shift 2 ;;
      *)           shift ;;
    esac
  done
  local args=( span
    --endpoint "${OTEL_SPAN_ENDPOINT:-http://127.0.0.1:4318}"
    --protocol http/protobuf
    --service "$service"
    --name "$name"
    --start "$start"
    --end "$end"
    --status-code "$status"
    --attrs "$attrs"
  )
  [[ -n "$trace_id" ]]  && args+=( --force-trace-id "$trace_id" )
  [[ -n "$span_id" ]]   && args+=( --force-span-id "$span_id" )
  [[ -n "$parent_id" ]] && args+=( --force-parent-span-id "$parent_id" )
  args+=( --timeout "$timeout" )
  "${OTEL_SPAN_CLI:-otel-cli}" "${args[@]}" >/dev/null 2>&1 || true
  return 0
}

# --- wrap + time a command -------------------------------------------------

# otel_span_run --service S --name N --category C [--trace-id ..] [--parent-id ..]
#               [--span-id ..] [--attrs extra=v;..] -- <command> [args...]
# Runs <command>, times it, emits one span carrying script.category /
# exit.code / duration_ms (plus any caller extras), and returns <command>'s
# exit code unchanged. Safe under `set -e` in the caller.
otel_span_run() {
  local service="" name="" category="" trace_id="" parent_id="" span_id="" extra_attrs=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --service)   service="${2:-}";     shift 2 ;;
      --name)      name="${2:-}";        shift 2 ;;
      --category)  category="${2:-}";    shift 2 ;;
      --trace-id)  trace_id="${2:-}";    shift 2 ;;
      --parent-id) parent_id="${2:-}";   shift 2 ;;
      --span-id)   span_id="${2:-}";     shift 2 ;;
      --attrs)     extra_attrs="${2:-}"; shift 2 ;;
      --)          shift; break ;;
      *)           shift ;;
    esac
  done
  local start_epoch end_epoch start_ns end_ns rc
  start_epoch="$(date +%s.%N 2>/dev/null || date +%s)"
  start_ns="$(date +%s%N 2>/dev/null || echo 0)"
  # set -e safe: capture rc without aborting the function on a non-zero exit.
  if "$@"; then rc=0; else rc=$?; fi
  end_epoch="$(date +%s.%N 2>/dev/null || date +%s)"
  end_ns="$(date +%s%N 2>/dev/null || echo 0)"
  local duration_ms=0
  if [[ "${start_ns:-0}" -gt 0 ]] && [[ "${end_ns:-0}" -gt 0 ]]; then
    duration_ms=$(( (end_ns - start_ns) / 1000000 ))
  fi
  local status="unset"
  (( rc != 0 )) && status="error"
  local attrs="script.category=$(otel_span_sanitize "$category"),exit.code=${rc},duration_ms=${duration_ms}"
  [[ -n "$extra_attrs" ]] && attrs="${attrs},${extra_attrs}"
  local emit_args=( --service "$service" --name "$name"
    --start "$start_epoch" --end "$end_epoch" --status "$status" --attrs "$attrs" )
  [[ -n "$trace_id" ]]  && emit_args+=( --trace-id "$trace_id" )
  [[ -n "$parent_id" ]] && emit_args+=( --parent-id "$parent_id" )
  [[ -n "$span_id" ]]   && emit_args+=( --span-id "$span_id" )
  otel_span_emit "${emit_args[@]}"
  return "$rc"
}
