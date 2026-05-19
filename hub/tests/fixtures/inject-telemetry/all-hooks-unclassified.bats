#!/usr/bin/env bats
# UNCLASSIFIED fixture: setup_file + teardown_file + setup + teardown all
# present. No supported truth-table row matches this combination.

bats_require_minimum_version 1.5.0

setup_file()    { :; }
teardown_file() { :; }
setup()         { :; }
teardown()      { :; }

@test "unclassified fixture: trivial test passes" {
  true
}
