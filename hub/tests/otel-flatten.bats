#!/usr/bin/env bats
# BTS-497 Step 3 — otel-flatten.sh core flatten path (AC-10).
#
# The flatten step reads OTLP `ExportTraceServiceRequest` envelopes from
# raw-traces.jsonl, filters spans by the run.id attribute, and emits one
# canonical flat JSON record per span to test-runs.jsonl. Schema is
# documented in .ccanvil/observability/SCHEMA.md (v1.0.0).
#
# Fixture: hub/tests/fixtures/raw-traces-sample.jsonl — 2 OTLP envelopes
# carrying mixed spans (3 for run-abc, 2 for run-xyz), to exercise the
# filter-across-envelopes path.

FLATTEN="$BATS_TEST_DIRNAME/../../.ccanvil/observability/otel-flatten.sh"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/raw-traces-sample.jsonl"

setup() {
  export OTEL_FLATTEN_INPUT="$FIXTURE"
  export OTEL_FLATTEN_OUTPUT="$BATS_TEST_TMPDIR/test-runs.jsonl"
}

# =========================================================================
# Core flatten — filter + schema shape
# =========================================================================

@test "AC-10: flatten run-abc emits exactly 3 records" {
  run bash "$FLATTEN" run-abc
  [ "$status" -eq 0 ]
  [ -f "$OTEL_FLATTEN_OUTPUT" ]
  local count
  count=$(wc -l < "$OTEL_FLATTEN_OUTPUT" | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "AC-10: no run-xyz contamination — all emitted records have run_id=run-abc" {
  bash "$FLATTEN" run-abc
  local mismatched
  mismatched=$(jq -c 'select(.run_id != "run-abc")' "$OTEL_FLATTEN_OUTPUT" | wc -l | tr -d ' ')
  [ "$mismatched" -eq 0 ]
}

@test "AC-10: every record has the 10 required snake_cased fields" {
  bash "$FLATTEN" run-abc
  local required=(run_id test_name test_file test_outcome worker_id runner_kind \
                  git_sha started_at_unix_nano duration_ms schema_version)
  while IFS= read -r line; do
    for field in "${required[@]}"; do
      echo "$line" | jq -e "has(\"$field\")" >/dev/null \
        || { echo "MISSING field '$field' in: $line" >&2; return 1; }
    done
  done < "$OTEL_FLATTEN_OUTPUT"
}

@test "AC-10: schema_version field value is v1.0.0 on every record" {
  bash "$FLATTEN" run-abc
  local bad
  bad=$(jq -c 'select(.schema_version != "v1.0.0")' "$OTEL_FLATTEN_OUTPUT" | wc -l | tr -d ' ')
  [ "$bad" -eq 0 ]
}

@test "AC-10: test_outcome values are subset of {pass, fail, skip}" {
  bash "$FLATTEN" run-abc
  local bad
  bad=$(jq -r '.test_outcome' "$OTEL_FLATTEN_OUTPUT" | grep -vE '^(pass|fail|skip)$' | wc -l | tr -d ' ')
  [ "$bad" -eq 0 ]
}

@test "AC-10: worker_id is integer-typed, not string" {
  bash "$FLATTEN" run-abc
  # jq's type discrimination: number vs string. Fixture has intValue="3", and
  # the flatten step must convert to JSON number per the schema.
  local non_number
  non_number=$(jq -c 'select((.worker_id | type) != "number")' "$OTEL_FLATTEN_OUTPUT" | wc -l | tr -d ' ')
  [ "$non_number" -eq 0 ]
}

# =========================================================================
# error_excerpt conditional optionality (AC-10 Implementation Note)
# =========================================================================

@test "AC-10: error_excerpt present iff test_outcome=fail" {
  bash "$FLATTEN" run-abc
  # On the 3 run-abc spans: test 1=pass, test 2=fail (with excerpt), test 3=skip.
  local fail_with_excerpt
  fail_with_excerpt=$(jq -c 'select(.test_outcome=="fail") | select(has("error_excerpt"))' \
    "$OTEL_FLATTEN_OUTPUT" | wc -l | tr -d ' ')
  [ "$fail_with_excerpt" -eq 1 ]

  local non_fail_with_excerpt
  non_fail_with_excerpt=$(jq -c 'select(.test_outcome!="fail") | select(has("error_excerpt"))' \
    "$OTEL_FLATTEN_OUTPUT" | wc -l | tr -d ' ')
  [ "$non_fail_with_excerpt" -eq 0 ]
}

@test "AC-10: error_excerpt value matches fixture for the failing span" {
  bash "$FLATTEN" run-abc
  local excerpt
  excerpt=$(jq -r 'select(.test_outcome=="fail") | .error_excerpt' "$OTEL_FLATTEN_OUTPUT")
  [ "$excerpt" = "boom: expected 1 got 2" ]
}

# =========================================================================
# Canonical-keyed output (AC-12 Implementation Note — jq -c -S)
# =========================================================================

@test "AC-12: output uses canonical sorted-keys form (each line begins with sorted key)" {
  bash "$FLATTEN" run-abc
  # First key alphabetically should be 'duration_ms' (d before g, r, s, t, w).
  # jq -c -S sorts keys; the first JSON key in each line must be 'duration_ms'.
  while IFS= read -r line; do
    local first_key
    first_key=$(echo "$line" | jq -r 'keys[0]')
    [ "$first_key" = "duration_ms" ]
  done < "$OTEL_FLATTEN_OUTPUT"
}

# =========================================================================
# Run-id filtering negative case
# =========================================================================

@test "AC-10: flatten run-xyz emits exactly 2 records (no run-abc contamination)" {
  bash "$FLATTEN" run-xyz
  local count
  count=$(wc -l < "$OTEL_FLATTEN_OUTPUT" | tr -d ' ')
  [ "$count" -eq 2 ]
  local bad
  bad=$(jq -c 'select(.run_id != "run-xyz")' "$OTEL_FLATTEN_OUTPUT" | wc -l | tr -d ' ')
  [ "$bad" -eq 0 ]
}
