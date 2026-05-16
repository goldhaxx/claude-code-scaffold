# BTS-497 — bats telemetry helper (runner-neutral OTel emission).
#
# Sourced once per .bats file via shared setup_file() / teardown_file() and
# per @test via setup() / teardown(). Emits one OTel span per @test to the
# local Collector at $CCANVIL_OTLP_ENDPOINT (default http://127.0.0.1:4318),
# carrying the runner-neutral attribute set documented in
# .ccanvil/observability/SCHEMA.md (v1.0.0).
#
# Public functions:
#   telemetry_setup_file    — healthcheck + otel-cli probe + cache invariants
#   telemetry_teardown_file — no-op (kept for symmetry / future flush hook)
#   telemetry_setup         — capture per-test start nanoseconds
#   telemetry_teardown      — emit one span via direct OTLP HTTP
#
# Env overrides:
#   CCANVIL_TELEMETRY_URL       healthcheck endpoint (default http://127.0.0.1:13133)
#   CCANVIL_OTLP_ENDPOINT       OTLP HTTP endpoint   (default http://127.0.0.1:4318)
#   CCANVIL_TELEMETRY_DISABLED  any value disables the helper entirely
#                               (used by --no-telemetry escape hatch in
#                                bats-report.sh — Plan Step 14)
#
# Emission mechanism: direct `otel-cli span --endpoint <url>` per test.
# Prior design used `otel-cli span background` for a unix-socket span server
# to amortize emission cost, but that verb creates ONE long-running span you
# add events to — not a multi-span daemon. Direct per-test OTLP HTTP connect
# is ~5-15 ms per emission (vs ~1-3 ms socket projection); 2,338 tests adds
# ~12-35 s of wall time, well inside AC-7's 50 ms p95 budget. No background
# process means no kill/wait/teardown — terminating by construction.

telemetry_setup_file() {
  # AC-7 / Step 14 escape hatch: disabled mode is a hard no-op so substrate
  # self-tests run without the stack.
  if [[ -n "${CCANVIL_TELEMETRY_DISABLED:-}" ]]; then
    return 0
  fi

  # AC-5: otel-cli must be installed.
  if ! command -v otel-cli >/dev/null 2>&1; then
    echo "ERROR: otel-cli not on PATH — required by BTS-497 test observability" >&2
    echo "Install: brew install equinix-labs/otel-cli/otel-cli" >&2
    return 1
  fi

  # AC-2: Collector healthcheck must respond 200.
  local url="${CCANVIL_TELEMETRY_URL:-http://127.0.0.1:13133}"
  if ! curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
    echo "ERROR: OTel Collector healthcheck unreachable at $url" >&2
    echo "Start: docker compose -f .ccanvil/observability/docker-compose.yml up -d" >&2
    return 1
  fi

  export BTS_TELEMETRY_ENDPOINT="${CCANVIL_OTLP_ENDPOINT:-http://127.0.0.1:4318}"
  _telemetry_cache_invariants
}

# Pure-bash invariant cache (no live deps). Exposed so unit tests can
# assert attribute resolution without standing up the Collector.
# Sets BTS_TELEMETRY_RUN_ID, BTS_TELEMETRY_GIT_SHA, BTS_TELEMETRY_WORKER_ID.
_telemetry_cache_invariants() {
  # AC-6: PARALLEL_JOBSLOT is set by GNU parallel when bats shells out via
  # `--jobs N`. Single-file mode → unset → default to 0 (no error, no warning,
  # no missing field). The span still emits.
  export BTS_TELEMETRY_WORKER_ID="${PARALLEL_JOBSLOT:-0}"
  # AC-1: run.id format <epoch>-<pid>. Honors externally-set BTS_RUN_ID
  # (bats-report.sh in Step 13 sets one shared run.id for the whole suite
  # so all files share it).
  export BTS_TELEMETRY_RUN_ID="${BTS_RUN_ID:-$(date +%s)-$$}"
  # AC-1: git.sha = current HEAD. Resolves once per file; degrades to
  # "unknown" outside a git tree rather than failing.
  export BTS_TELEMETRY_GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
}

# Compose the otel-cli --attrs value from cached invariants + per-test args.
# Args: <outcome> <duration_ms> [<error_excerpt>]
# Echoes a comma-separated key=value string to stdout.
_telemetry_compose_attrs() {
  local outcome="$1" duration_ms="$2" error_excerpt="${3:-}"
  local file_rel="${BATS_TEST_FILENAME:-unknown}"
  # Strip leading $PWD/ so attribute matches repo-relative path used in the
  # flat JSONL schema (test_file field).
  [[ -n "${PWD:-}" ]] && file_rel="${file_rel#$PWD/}"
  local out="test.name=${BATS_TEST_DESCRIPTION:-unknown}"
  out+=",test.file=${file_rel}"
  out+=",test.outcome=${outcome}"
  out+=",worker.id=${BTS_TELEMETRY_WORKER_ID:-0}"
  out+=",runner.kind=bats"
  out+=",run.id=${BTS_TELEMETRY_RUN_ID:-unknown}"
  out+=",git.sha=${BTS_TELEMETRY_GIT_SHA:-unknown}"
  out+=",test.duration_ms=${duration_ms}"
  if [[ -n "$error_excerpt" ]]; then
    # Truncate to ~200 chars per SCHEMA.md guidance.
    local truncated="${error_excerpt:0:200}"
    # Strip commas (otel-cli --attrs comma-delimited) — pragmatic.
    truncated="${truncated//,/;}"
    out+=",test.error_excerpt=${truncated}"
  fi
  printf '%s' "$out"
}

telemetry_teardown_file() {
  # No background process to clean up — emission is per-test direct OTLP.
  # Kept as a public no-op for symmetric setup/teardown pairing and so a
  # future flush hook can land without touching every .bats file.
  return 0
}

telemetry_setup() {
  if [[ -n "${CCANVIL_TELEMETRY_DISABLED:-}" ]]; then
    return 0
  fi
  # Step 12 expands this: record test start in nanoseconds for the
  # test.duration_ms attribute computed in teardown.
  export BTS_TELEMETRY_TEST_START_NS="$(date +%s%N 2>/dev/null || echo 0)"
}

telemetry_teardown() {
  if [[ -n "${CCANVIL_TELEMETRY_DISABLED:-}" ]]; then
    return 0
  fi
  # AC-1: emit one span per test via the unix-socket span server.
  # Outcome derives from bats state vars:
  #   BATS_TEST_SKIPPED — non-empty when `skip` was called
  #   BATS_TEST_COMPLETED — 1 on pass, 0 on fail
  local outcome
  if [[ -n "${BATS_TEST_SKIPPED:-}" ]]; then
    outcome="skip"
  elif [[ "${BATS_TEST_COMPLETED:-0}" -eq 1 ]]; then
    outcome="pass"
  else
    outcome="fail"
  fi

  # Duration in ms — nanoseconds from setup minus now.
  local now_ns duration_ms
  now_ns="$(date +%s%N 2>/dev/null || echo 0)"
  if [[ "${BTS_TELEMETRY_TEST_START_NS:-0}" -gt 0 ]] && [[ "$now_ns" -gt 0 ]]; then
    duration_ms=$(( (now_ns - BTS_TELEMETRY_TEST_START_NS) / 1000000 ))
  else
    duration_ms=0
  fi

  local attrs
  attrs=$(_telemetry_compose_attrs "$outcome" "$duration_ms" "${BATS_TEST_ERROR_EXCERPT:-}")

  # Emit via direct OTLP HTTP. ~5-15 ms per call; well inside AC-7 budget.
  # Failures are non-fatal — never break a test because telemetry hiccupped.
  # Status code follows outcome: error on fail, unset on pass/skip.
  local status_code="unset"
  [[ "$outcome" == "fail" ]] && status_code="error"
  otel-cli span \
    --endpoint "${BTS_TELEMETRY_ENDPOINT:-http://127.0.0.1:4318}" \
    --protocol http/protobuf \
    --service ccanvil-test \
    --name "${BATS_TEST_DESCRIPTION:-unknown}" \
    --status-code "$status_code" \
    --attrs "$attrs" \
    --timeout 2s \
    >/dev/null 2>&1 || true
}
