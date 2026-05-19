#!/usr/bin/env bats
# Cat E fixture: setup_file() + setup(), no teardown, no teardown_file.

bats_require_minimum_version 1.5.0

setup_file() {
  EXAMPLE_FILE_VAR="initialised-once"
}

setup() {
  EXAMPLE_VAR="hello"
}

@test "cat-e fixture: trivial test reads existing-setup var" {
  [ "$EXAMPLE_VAR" = "hello" ]
}
