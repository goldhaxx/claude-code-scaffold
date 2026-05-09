#!/usr/bin/env bats
#
# BTS-385 Step 1: cmd_rule_resolve happy path.
#
# Tests the new rule-resolve substrate primitive that returns a JSON envelope
# describing a rule's tier metadata + anchor pointers. RED first — cmd does
# not exist yet; test fails with "rule-resolve: unknown command" until Step 2
# implements it.

bats_require_minimum_version 1.5.0

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"
FIX_DIR="$BATS_TEST_DIRNAME/fixtures/rule-tier"

_make_rule_fx() {
  local fx="$BATS_TEST_TMPDIR/rule-fx"
  mkdir -p "$fx/.claude/rules"
  cp "$FIX_DIR/sample-atom.md" "$fx/.claude/rules/sample-atom.md"
  echo "$fx"
}

@test "BTS-385 Step 1: rule-resolve returns envelope for fixture rule with frontmatter" {
  set -e
  fx=$(_make_rule_fx)
  run bash "$DC" rule-resolve sample-atom --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rule == "sample-atom"'
  echo "$output" | jq -e '.tier == 0'
  echo "$output" | jq -e '.scope == "universal"'
  echo "$output" | jq -e '.stack == "any"'
  echo "$output" | jq -e '.body_path | endswith(".claude/rules/sample-atom.md")'
  echo "$output" | jq -e '(.anchors.apply | length) == 1'
  echo "$output" | jq -e '(.anchors.evidence | length) == 1'
  echo "$output" | jq -e '(.anchors["related-rules"] | length) == 0'
}
