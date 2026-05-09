#!/usr/bin/env bats

@test "fast: arithmetic works" {
  [ $((1 + 1)) -eq 2 ]
}

@test "fast: string compare" {
  [ "alpha" = "alpha" ]
}
