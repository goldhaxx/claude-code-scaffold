#!/usr/bin/env bats

@test "slow: short sleep" {
  sleep 0.3
  [ true ]
}

@test "slow: configurable long sleep (gated by env var)" {
  if [[ "${BATS_PROGRESS_TEST_SLOW:-0}" == "1" ]]; then
    sleep "${BATS_PROGRESS_TEST_SLOW_SECS:-35}"
  fi
  [ true ]
}
