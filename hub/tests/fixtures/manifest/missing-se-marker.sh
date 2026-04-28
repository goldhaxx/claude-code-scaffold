#!/usr/bin/env bash
# Fixture: declares side-effect but no matching @side-effect source-marker.

# @manifest
# purpose: Test fixture for missing-@side-effect-marker drift class
# input: stdin
# output: stdout
# side-effect: orphan-se
# failure-mode: foo | exit=1 | visible=stderr
# contract: idempotent
# anchor: BTS-239
missing_se_marker_func() {
  # @failure-mode: foo
  echo "no @side-effect marker for orphan-se"
  return 0
}
