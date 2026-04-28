#!/usr/bin/env bash
# Fixture: valid manifest with caller, depends-on, all markers in place.

# Caller function — present in this same file so caller-grep finds it.
referenced_caller() {
  echo "this calls valid_deep_func"
  valid_deep_func
}

# @manifest
# purpose: Test fixture for fully-valid deep validation
# input: stdin
# output: stdout
# caller: referenced_caller
# depends-on: cat
# side-effect: writes-tmp
# failure-mode: foo | exit=1 | visible=stderr
# contract: idempotent
# anchor: BTS-239
valid_deep_func() {
  # @failure-mode: foo
  # @side-effect: writes-tmp
  cat /etc/hostname > /dev/null
  return 0
}
