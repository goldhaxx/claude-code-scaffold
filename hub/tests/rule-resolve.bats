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

@test "BTS-385 Step 3: rule-resolve exits 1 with rule-not-found on missing rule" {
  set -e
  fx=$(_make_rule_fx)
  run bash "$DC" rule-resolve nonexistent-rule --project-dir "$fx"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error == "rule-not-found"'
  echo "$output" | jq -e '.rule == "nonexistent-rule"'
}

@test "BTS-385 Step 3: rule-resolve exits 2 with frontmatter-malformed on bad YAML" {
  set -e
  fx="$BATS_TEST_TMPDIR/malformed-fx"
  mkdir -p "$fx/.claude/rules"
  cp "$FIX_DIR/malformed.md" "$fx/.claude/rules/malformed.md"
  run bash "$DC" rule-resolve malformed --project-dir "$fx"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.error == "frontmatter-malformed"'
  echo "$output" | jq -e '.rule == "malformed"'
  echo "$output" | jq -e '.reason | length > 0'
}

@test "BTS-385 Step 3: rule-resolve returns default envelope for rule without frontmatter" {
  set -e
  fx="$BATS_TEST_TMPDIR/nofm-fx"
  mkdir -p "$fx/.claude/rules"
  cp "$FIX_DIR/no-frontmatter.md" "$fx/.claude/rules/no-frontmatter.md"
  run bash "$DC" rule-resolve no-frontmatter --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rule == "no-frontmatter"'
  echo "$output" | jq -e '.tier == 0'
  echo "$output" | jq -e '.scope == "universal"'
  echo "$output" | jq -e '.stack == "any"'
  echo "$output" | jq -e '(.anchors | length) == 0'
}
