#!/usr/bin/env bash
# Fixture: declares a depends-on that does not appear in the function body.

# @manifest
# purpose: Test fixture for depends-on-not-found drift class
# input: stdin
# output: stdout
# depends-on: nonexistent_dependency_xyz
# side-effect: writes-tmp
# failure-mode: foo | exit=1 | visible=stderr
# contract: idempotent
# anchor: BTS-239
depends_on_not_found_func() {
  echo "body does NOT contain the dependency"
  return 0
}
