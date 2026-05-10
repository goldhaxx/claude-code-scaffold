#!/usr/bin/env bats
#
# BTS-384 Step 1: scope-vocabulary parser extension in module-manifest.sh validate.
#
# Tests the rule-scan extension that surfaces `scope:` alongside `tier:`. Emits:
#   - drift: rule-scope-invalid   (block-shape — unknown scope value)
#   - info:  rule-scope-missing   (advisory — frontmatter present, no scope key)
# Valid scope values: universal | substrate | hub-only.

bats_require_minimum_version 1.5.0

MM="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/module-manifest.sh"
FIX_DIR="$BATS_TEST_DIRNAME/fixtures/rule-scope"

_make_rule_project() {
  local name="$1"
  shift
  local fx="$BATS_TEST_TMPDIR/$name"
  mkdir -p "$fx/.claude/rules" "$fx/.ccanvil"
  : > "$fx/.ccanvil/manifest-allowlist.txt"
  local rule
  for rule in "$@"; do
    cp "$FIX_DIR/$rule" "$fx/.claude/rules/$rule"
  done
  echo "$fx"
}

@test "BTS-384 Step 1: scope:universal emits no drift, no info, exit 0" {
  set -e
  fx=$(_make_rule_project "scope-universal-fx" "scope-universal.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drift | length == 0'
  echo "$output" | jq -e '.info | map(select(.reason | startswith("rule-scope-"))) | length == 0'
}

@test "BTS-384 Step 1: scope:substrate emits no drift, no info, exit 0" {
  set -e
  fx=$(_make_rule_project "scope-substrate-fx" "scope-substrate.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drift | length == 0'
  echo "$output" | jq -e '.info | map(select(.reason | startswith("rule-scope-"))) | length == 0'
}

@test "BTS-384 Step 1: scope:hub-only emits no drift, no info, exit 0" {
  set -e
  fx=$(_make_rule_project "scope-hub-only-fx" "scope-hub-only.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drift | length == 0'
  echo "$output" | jq -e '.info | map(select(.reason | startswith("rule-scope-"))) | length == 0'
}

@test "BTS-384 Step 1: invalid scope value emits rule-scope-invalid drift, exit 2" {
  fx=$(_make_rule_project "scope-invalid-fx" "scope-invalid.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.drift | map(select(.reason == "rule-scope-invalid")) | length == 1'
  echo "$output" | jq -e '.drift | map(select(.reason == "rule-scope-invalid")) | .[0].path | endswith("scope-invalid.md")'
  echo "$output" | jq -e '.drift | map(select(.reason == "rule-scope-invalid")) | .[0].value == "bogus-value"'
}

@test "BTS-384 Step 1: missing scope key emits rule-scope-missing info, exit 0" {
  set -e
  fx=$(_make_rule_project "scope-key-missing-fx" "scope-key-missing.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.info | map(select(.reason == "rule-scope-missing")) | length == 1'
  echo "$output" | jq -e '.drift | map(select(.reason | startswith("rule-scope-"))) | length == 0'
  echo "$output" | jq -e '.status == "ok"'
}
