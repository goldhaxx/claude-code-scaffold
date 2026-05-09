#!/usr/bin/env bats

setup() {
  set -e
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURE_DIR="$REPO_ROOT/hub/tests/fixtures/bats-progress"
  cd "$REPO_ROOT"
  # Skip the BTS-281 pre-warm: this test exercises bats-report's --progress
  # output, not its manifest cache plumbing. The pre-warm runs full
  # module-manifest validate (~30s today), which dominates the test wall
  # time and contributes to the BTS-383 incident the rule was written for.
  export BTS_MANIFEST_VALIDATE_CACHE=/tmp/bts-383-progress-test-bypass
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
