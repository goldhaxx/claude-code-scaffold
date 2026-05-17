#!/usr/bin/env bats

load _helpers/bats-report-stub

setup() {
  set -e
  stub_bats_report_prewarm
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURE_DIR="$REPO_ROOT/hub/tests/fixtures/bats-progress"
  cd "$REPO_ROOT"
}

@test "AC-1: --progress emits [N/M] markers per file" {
  set -e
  run bash .ccanvil/scripts/bats-report.sh --progress \
    "$FIXTURE_DIR/fast.bats" "$FIXTURE_DIR/slow.bats"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '\[1/2\]'
  echo "$output" | grep -qE '\[2/2\]'
  echo "$output" | grep -qE 'fast\.bats'
  echo "$output" | grep -qE 'slow\.bats'
}

@test "AC-1: --progress emits [heartbeat] during long-running file" {
  set -e
  run env BATS_PROGRESS_HEARTBEAT_SECS=1 \
          BATS_PROGRESS_TEST_SLOW=1 \
          BATS_PROGRESS_TEST_SLOW_SECS=3 \
    bash .ccanvil/scripts/bats-report.sh --progress "$FIXTURE_DIR/slow.bats"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '\[heartbeat\]'
  echo "$output" | grep -qE '\[1/1\]'
}
