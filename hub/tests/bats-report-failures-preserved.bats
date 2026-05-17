#!/usr/bin/env bats

load _helpers/bats-report-stub

setup() {
  set -e
  stub_bats_report_prewarm
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURE_DIR="$REPO_ROOT/hub/tests/fixtures/bats-progress"
  cd "$REPO_ROOT"
}

@test "AC-2: --json envelope carries failures[] with shape on forced-fail fixture" {
  set -e
  run bash .ccanvil/scripts/bats-report.sh --json "$FIXTURE_DIR/fail.bats"
  # bats-report.sh exits non-zero on suite failure, but JSON is still emitted to stdout.
  echo "$output" | jq -e '.failures | type == "array"'
  echo "$output" | jq -e '.failures | length == 1'
  echo "$output" | jq -e '.failures[0] | has("test_name") and has("file") and has("line_number") and has("error_excerpt")'
  echo "$output" | jq -e '.failures[0].test_name | test("deliberate failure for AC-2")'
  echo "$output" | jq -e '.failures[0].file | endswith("fail.bats")'
  echo "$output" | jq -e '.failures[0].line_number | type == "number"'
  echo "$output" | jq -e '.failures[0].error_excerpt | length > 0'
}

@test "AC-2: --json failures[] is empty on all-pass fixture" {
  set -e
  run bash .ccanvil/scripts/bats-report.sh --json "$FIXTURE_DIR/fast.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.failures == []'
}

@test "AC-3: bats-runs.jsonl entry preserves failures[] from a fail run" {
  set -e
  state_dir=$(mktemp -d)
  export BATS_REPORT_STATE_DIR="$state_dir"
  run bash .ccanvil/scripts/bats-report.sh --json "$FIXTURE_DIR/fail.bats"
  jsonl_path="$state_dir/bats-runs.jsonl"
  [ -f "$jsonl_path" ]
  tail -1 "$jsonl_path" | jq -e '.failures | type == "array"'
  tail -1 "$jsonl_path" | jq -e '.failures | length == 1'
  tail -1 "$jsonl_path" | jq -e '.failures[0].test_name | test("deliberate failure")'
  rm -rf "$state_dir"
}

@test "AC-3: bats-runs.jsonl failures[] empty on all-pass run" {
  set -e
  state_dir=$(mktemp -d)
  export BATS_REPORT_STATE_DIR="$state_dir"
  run bash .ccanvil/scripts/bats-report.sh --json "$FIXTURE_DIR/fast.bats"
  [ "$status" -eq 0 ]
  jsonl_path="$state_dir/bats-runs.jsonl"
  [ -f "$jsonl_path" ]
  tail -1 "$jsonl_path" | jq -e '.failures == []'
  rm -rf "$state_dir"
}
