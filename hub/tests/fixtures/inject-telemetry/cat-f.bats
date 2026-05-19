#!/usr/bin/env bats
# Cat F fixture: setup_file() + teardown_file() only.

bats_require_minimum_version 1.5.0

setup_file() {
  EXAMPLE_FILE_VAR="initialised-once"
}

teardown_file() {
  unset EXAMPLE_FILE_VAR
}

@test "cat-f fixture: trivial test reads existing-setup-file var" {
  [ "$EXAMPLE_FILE_VAR" = "initialised-once" ]
}
