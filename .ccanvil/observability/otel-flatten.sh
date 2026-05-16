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

mkdir -p "$(dirname "$OUTPUT")"

# Flatten + filter via jq. Two passes:
#   1) Extract spans, unwrap OTLP attribute arrays into a flat key:value
#      map, filter by run.id, project to the AC-10 schema, drop null
#      optional fields via with_entries.
#   2) Canonicalize via `jq -c -S` (compact, sorted keys) — produces
#      reviewable, byte-stable output per the AC-12 Implementation Note.
jq -c --arg RUN_ID "$RUN_ID" '
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
  with_entries(select(.value != null))
' "$INPUT" | jq -c -S '.' >> "$OUTPUT"
