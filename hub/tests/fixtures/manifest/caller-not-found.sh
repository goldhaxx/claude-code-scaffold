#!/usr/bin/env bash
# Fixture: declares a caller that doesn't exist anywhere in source.

# @manifest
# purpose: Test fixture for caller-not-found drift class
# input: stdin
# output: stdout
# caller: nonexistent_caller_func_xyz
# side-effect: writes-tmp
# failure-mode: foo | exit=1 | visible=stderr
# contract: idempotent
# anchor: BTS-239
caller_not_found_func() {
  return 0
}
