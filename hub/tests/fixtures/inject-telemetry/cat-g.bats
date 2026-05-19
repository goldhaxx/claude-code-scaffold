#!/usr/bin/env bats
# Cat G fixture: teardown() only (no setup_file, no teardown_file, no setup).

bats_require_minimum_version 1.5.0

teardown() {
  unset EXAMPLE_VAR
}

@test "cat-g fixture: trivial test passes" {
  EXAMPLE_VAR="hello"
  [ "$EXAMPLE_VAR" = "hello" ]
}
