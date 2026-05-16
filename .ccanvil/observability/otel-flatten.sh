#!/usr/bin/env bash
# otel-flatten.sh — normalize OTel Collector fileexporter envelopes into
# a flat per-test JSONL sidecar for agent-readable per-test queries.
#
# Reads OTLP `ExportTraceServiceRequest` envelopes (one per line) from
# raw-traces.jsonl, filters spans by the run.id attribute, and emits one
# canonical-keyed flat JSON record per span to test-runs.jsonl.
#
# Schema contract: .ccanvil/observability/SCHEMA.md (v1.0.0).
# Spec: BTS-497 AC-10 (record shape), AC-12 (idempotency, fail-closed).

# @manifest
# purpose: Deterministic OTLP→flat-JSONL normalizer for BTS-497 test observability. Reads the OTel Collector `fileexporter` output (one OTLP `ExportTraceServiceRequest` envelope per line) at raw-traces.jsonl, filters spans by the `run.id` user attribute (positional arg), unwraps OTLP attribute arrays into flat key:value maps, projects to the AC-10 flat-record schema (11 required + 1 optional snake_cased fields, schema_version v1.0.0), drops null optional fields via with_entries, dedups against the existing sidecar via O(N+M) hash-set lookup on the `(run_id, span_id)` pair, canonicalizes via `jq -c -S`, and appends previously-unseen records to test-runs.jsonl. Runs fail-closed at the JSONL layer: any of {missing-input, malformed-input, empty-input, no-matching-spans} exits 78 (sysexits EX_CONFIG) with actionable stderr — observability failures are distinct from test failures and must always surface. Schema and idempotency contract documented in .ccanvil/observability/SCHEMA.md.
# input: <run_id> (positional, required) — filter spans whose `run.id` attribute matches this value
# input: env OTEL_FLATTEN_INPUT (default `.ccanvil/observability/raw-traces.jsonl`) — path to the OTel Collector fileexporter output
# input: env OTEL_FLATTEN_OUTPUT (default `.ccanvil/state/test-runs.jsonl`) — path to the flat JSONL sidecar (append mode)
# output: append to OTEL_FLATTEN_OUTPUT — one canonical-keyed JSON record per newly-flattened span; zero records on idempotent re-run for a fully-flattened run_id
# output: stderr — actionable ERROR messages on fail-closed paths (missing/malformed/empty/no-matching input)
# output: exit-codes — 0 on success (any number of records appended, including zero on idempotent re-run); 78 on usage error, missing input, malformed input, empty input, or no spans matching the requested run_id
# depends-on: bash
# depends-on: jq
# side-effect: writes-test-runs-jsonl
# failure-mode: missing-input | exit=78 | visible=stderr-error | mitigation=start-otel-collector-via-docker-compose
# failure-mode: malformed-input | exit=78 | visible=stderr-error | mitigation=inspect-jq-stderr-and-clear-raw-traces
# failure-mode: empty-input | exit=78 | visible=stderr-error | mitigation=run-suite-first-then-flatten
# failure-mode: no-matching-spans | exit=78 | visible=stderr-error | mitigation=confirm-bats-helper-emitted-spans-and-collector-flushed
# contract: idempotent-on-(run_id,span_id)-pair
# contract: append-only-never-truncates-output
# contract: canonical-keyed-output-via-jq-c-S
# contract: fail-closed-exit-78-on-any-input-anomaly
# contract: schema-version-v1.0.0-on-every-record
# anchor: BTS-497 (AC-10 / AC-12)

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: otel-flatten.sh <run_id>

Env overrides (testing):
  OTEL_FLATTEN_INPUT   path to raw-traces.jsonl (default: .ccanvil/observability/raw-traces.jsonl)
  OTEL_FLATTEN_OUTPUT  path to test-runs.jsonl (default: .ccanvil/state/test-runs.jsonl)
USAGE
}

if [[ $# -ne 1 ]] || [[ -z "${1:-}" ]]; then
  usage
  exit 78
fi

RUN_ID="$1"
INPUT="${OTEL_FLATTEN_INPUT:-.ccanvil/observability/raw-traces.jsonl}"
OUTPUT="${OTEL_FLATTEN_OUTPUT:-.ccanvil/state/test-runs.jsonl}"

# AC-12c: fail-closed pre-flight checks. Each exits 78 (sysexits EX_CONFIG)
# with an actionable stderr message — observability-layer failures are
# distinct from test failures and must surface, never silently degrade.

# (1) INPUT must exist.
# @failure-mode: missing-input
if [[ ! -f "$INPUT" ]]; then
  echo "ERROR: raw-traces.jsonl not found at $INPUT" >&2
  echo "Hint: start the OTel Collector via .ccanvil/observability/docker-compose.yml" >&2
  exit 78
fi

# (2) INPUT must be parseable JSONL. Validate + count matches in one shot.
# @failure-mode: malformed-input
matched=$(jq -s --arg RUN_ID "$RUN_ID" '
  [
    .[]
    | .resourceSpans[]?.scopeSpans[]?.spans[]?
    | select(
        (
          (.attributes // [])
          | map({(.key): (.value.stringValue // .value.intValue // .value.doubleValue // .value.boolValue)})
          | add // {}
        )["run.id"] == $RUN_ID
      )
  ] | length
' "$INPUT" 2>&1) || {
  echo "ERROR: malformed JSON envelope in $INPUT — could not parse" >&2
  echo "jq stderr: $matched" >&2
  exit 78
}

# (3) Empty file (after parse — JSONL with zero lines is technically valid
# but carries no spans). Treat as no-spans case.
# @failure-mode: empty-input
if [[ ! -s "$INPUT" ]]; then
  echo "ERROR: empty raw-traces.jsonl at $INPUT — no spans for run.id=$RUN_ID" >&2
  exit 78
fi

# (4) No spans matching the requested run_id.
# @failure-mode: no-matching-spans
if [[ "${matched:-0}" -eq 0 ]]; then
  echo "ERROR: no spans for run.id=$RUN_ID in $INPUT" >&2
  echo "Hint: confirm the bats helper emitted spans for this run, and that" >&2
  echo "      the Collector flushed before this flatten step ran." >&2
  exit 78
fi

mkdir -p "$(dirname "$OUTPUT")"
# Ensure OUTPUT exists so --slurpfile binds to [] rather than erroring.
touch "$OUTPUT"

# @side-effect: writes-test-runs-jsonl

# Flatten + filter via jq. Two passes:
#   1) Extract spans, unwrap OTLP attribute arrays into a flat key:value
#      map, filter by run.id, project to the AC-10 schema, drop null
#      optional fields via with_entries. AC-12b idempotency: build hash-set
#      of existing (run_id, span_id) pairs from the sidecar via
#      --slurpfile; filter candidates whose pair is already present.
#      Object-as-set provides O(1) membership lookup — total cost O(N+M).
#   2) Canonicalize via `jq -c -S` (compact, sorted keys) — produces
#      reviewable, byte-stable output per the AC-12 Implementation Note.
jq -c --arg RUN_ID "$RUN_ID" --slurpfile existing "$OUTPUT" '
  ([$existing[] | {("\(.run_id):\(.span_id)"): true}] | add // {}) as $seen |
  [.resourceSpans[]?.scopeSpans[]?.spans[]?] | .[] |
  . as $span |
  (
    ($span.attributes // [])
    | map({(.key): (.value.stringValue // .value.intValue // .value.doubleValue // .value.boolValue)})
    | add // {}
  ) as $attrs |
  select($attrs["run.id"] == $RUN_ID) |
  {
    run_id: $attrs["run.id"],
    span_id: $span.spanId,
    test_name: $attrs["test.name"],
    test_file: $attrs["test.file"],
    test_outcome: $attrs["test.outcome"],
    worker_id: ($attrs["worker.id"] | tonumber),
    runner_kind: $attrs["runner.kind"],
    git_sha: $attrs["git.sha"],
    started_at_unix_nano: ($span.startTimeUnixNano | tonumber),
    duration_ms: ($attrs["test.duration_ms"] | if . == null then null else tonumber end),
    error_excerpt: $attrs["test.error_excerpt"],
    schema_version: "v1.0.0"
  } |
  with_entries(select(.value != null)) |
  select($seen["\(.run_id):\(.span_id)"] | not)
' "$INPUT" | jq -c -S '.' >> "$OUTPUT"
