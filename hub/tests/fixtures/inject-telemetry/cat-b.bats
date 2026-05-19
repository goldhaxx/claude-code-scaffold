#!/usr/bin/env bats
# Cat B fixture: setup() only.

bats_require_minimum_version 1.5.0

setup() {
  EXAMPLE_VAR="hello"
}

@test "cat-b fixture: trivial test reads existing-setup var" {
  [ "$EXAMPLE_VAR" = "hello" ]
}
