#!/usr/bin/env bash
# Fixture for hub/tests/module-manifest-extract.bats — BTS-239 Step 1.
# Two valid @manifest blocks, one per function. Includes source markers so
# the fixture also validates cleanly under deep validation (Step 5+).

# Caller present in this file so caller-grep finds a real callsite.
fixture_caller() {
  func_one
  func_two
}

# @manifest
# purpose: First block test fixture
# input: stdin
# output: stdout
# caller: fixture_caller
# side-effect: writes-tmp-file
# failure-mode: missing-input | exit=1 | visible=stderr-message
# contract: idempotent
# anchor: BTS-239
func_one() {
  # @failure-mode: missing-input
  # @side-effect: writes-tmp-file
  echo hello
}

# This intervening function has no manifest — extract must skip it cleanly.
not_a_manifest() {
  return 0
}

# @manifest
# purpose: Second block test fixture
# input: cli-flags
# output: stdout
# caller: fixture_caller
# side-effect: bar
# failure-mode: parse-error | exit=2 | visible=stderr-message | mitigation=retry-with-fallback
# contract: pure
# anchor: BTS-239
func_two() {
  # @failure-mode: parse-error
  # @side-effect: bar
  echo world
}
