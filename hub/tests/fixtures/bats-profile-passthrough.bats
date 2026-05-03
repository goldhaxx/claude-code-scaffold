#!/usr/bin/env bats
# BTS-282 fixture — minimal bats file used by bats-profile.bats AC-1
# to assert wrapper-vs-direct equivalence. Invokes docs-check.sh status
# (a fast, stable, read-only verb) so the wrapper has at least one
# substrate row to aggregate.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

@test "fixture: docs-check.sh status returns a JSON envelope" {
  cd "$REPO_ROOT"
  run bash .ccanvil/scripts/docs-check.sh status
  [ "$status" -eq 0 ]
  echo "$output" | head -1 | grep -qE '^{'
}
