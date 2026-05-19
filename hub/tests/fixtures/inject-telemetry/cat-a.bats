#!/usr/bin/env bats
# Cat A fixture: no setup_file, no teardown_file, no setup, no teardown.

bats_require_minimum_version 1.5.0

@test "cat-a fixture: trivial test passes" {
  true
}
