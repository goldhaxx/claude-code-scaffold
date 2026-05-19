#!/usr/bin/env bats
# Cat C fixture: setup() + teardown().

bats_require_minimum_version 1.5.0

setup() {
  EXAMPLE_VAR="hello"
}

teardown() {
  unset EXAMPLE_VAR
}

@test "cat-c fixture: trivial test reads existing-setup var" {
  [ "$EXAMPLE_VAR" = "hello" ]
}
