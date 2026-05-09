#!/usr/bin/env bats
#
# BTS-384 Step 2: vocabulary-leak drift-guard in module-manifest.sh validate.
#
# Scans `scope: universal` rule bodies for hub-specific tokens (bats-report.sh,
# module-manifest.sh, ccanvil-sync.sh, linear-query.sh, docs-check.sh, BTS-N)
# appearing OUTSIDE an `## Anchored on (...)` block. Emits warn-shape
# `rule-vocabulary-leak` to info[]. Substrate-scope and hub-only-scope rules
# are NOT scanned. Tokens inside an anchor block are exempt.

bats_require_minimum_version 1.5.0

MM="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/module-manifest.sh"
FIX_DIR="$BATS_TEST_DIRNAME/fixtures/rule-vocab-leak"

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

@test "BTS-384 Step 2: leak outside anchor block emits rule-vocabulary-leak info" {
  set -e
  fx=$(_make_rule_project "leak-outside-fx" "leak-outside-anchor.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | length == 1'
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | .[0].path | endswith("leak-outside-anchor.md")'
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | .[0].tokens | index("bats-report.sh") != null'
  echo "$output" | jq -e '.drift | length == 0'
}

@test "BTS-384 Step 2: tokens inside anchor block are exempt" {
  set -e
  fx=$(_make_rule_project "leak-inside-fx" "leak-inside-anchor.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | length == 0'
  echo "$output" | jq -e '.drift | length == 0'
}

@test "BTS-384 Step 2: leak with no anchor block at all emits info" {
  set -e
  fx=$(_make_rule_project "leak-no-anchor-fx" "leak-no-anchor.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | length == 1'
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | .[0].tokens | index("module-manifest.sh") != null'
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | .[0].tokens | index("BTS-NNN") != null'
}

@test "BTS-384 Step 2: substrate-scope rule with hub tokens is NOT scanned" {
  set -e
  fx=$(_make_rule_project "substrate-token-fx" "substrate-with-token.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | length == 0'
}

@test "BTS-384 Step 2: clean universal rule emits no leak info" {
  set -e
  fx=$(_make_rule_project "clean-fx" "clean-universal.md")
  cd "$fx"
  run bash "$MM" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.info | map(select(.reason == "rule-vocabulary-leak")) | length == 0'
  echo "$output" | jq -e '.drift | length == 0'
}
