#!/usr/bin/env bash
# Fixture: declares failure-mode but no matching @failure-mode source-marker.

# @manifest
# purpose: Test fixture for missing-@failure-mode-marker drift class
# input: stdin
# output: stdout
# side-effect: writes-tmp
# failure-mode: orphan-fm | exit=1 | visible=stderr
# contract: idempotent
# anchor: BTS-239
missing_fm_marker_func() {
  # @side-effect: writes-tmp
  echo "no @failure-mode marker for orphan-fm"
  return 0
}
