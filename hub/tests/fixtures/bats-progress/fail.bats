#!/usr/bin/env bats

@test "fail-fixture: passing baseline" {
  [ 1 -eq 1 ]
}

@test "fail-fixture: deliberate failure for AC-2" {
  [ 1 -eq 2 ]
}
