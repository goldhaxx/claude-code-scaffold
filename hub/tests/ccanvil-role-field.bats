#!/usr/bin/env bats
#
# BTS-384 Step 3: role field substrate.
#
# Hub .claude/ccanvil.json carries `role: hub-substrate-developer`. Downstream
# nodes default to `substrate-consumer` when the key is absent. Tested via the
# `ccanvil-sync.sh node-role <project-dir>` verb that prints the resolved role.

bats_require_minimum_version 1.5.0

SYNC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"
HUB_ROOT="$BATS_TEST_DIRNAME/../.."

@test "BTS-384 Step 3: hub .claude/ccanvil.json carries role: hub-substrate-developer" {
  set -e
  role=$(jq -r '.role // ""' "$HUB_ROOT/.claude/ccanvil.json")
  [ "$role" = "hub-substrate-developer" ]
}

@test "BTS-384 Step 3: template doc surfaces role field with substrate-consumer default" {
  set -e
  grep -q '"role"' "$HUB_ROOT/.ccanvil/templates/ccanvil.json.md"
  grep -q 'substrate-consumer' "$HUB_ROOT/.ccanvil/templates/ccanvil.json.md"
}

@test "BTS-384 Step 3: node-role verb resolves explicit hub-substrate-developer" {
  set -e
  fx="$BATS_TEST_TMPDIR/node-explicit-hub"
  mkdir -p "$fx/.claude"
  jq -n '{role:"hub-substrate-developer"}' > "$fx/.claude/ccanvil.json"
  run bash "$SYNC" node-role "$fx"
  [ "$status" -eq 0 ]
  [ "$output" = "hub-substrate-developer" ]
}

@test "BTS-384 Step 3: node-role verb resolves explicit substrate-consumer" {
  set -e
  fx="$BATS_TEST_TMPDIR/node-explicit-consumer"
  mkdir -p "$fx/.claude"
  jq -n '{role:"substrate-consumer"}' > "$fx/.claude/ccanvil.json"
  run bash "$SYNC" node-role "$fx"
  [ "$status" -eq 0 ]
  [ "$output" = "substrate-consumer" ]
}

@test "BTS-384 Step 3 (AC-7): missing role key defaults to substrate-consumer" {
  set -e
  fx="$BATS_TEST_TMPDIR/node-missing-role"
  mkdir -p "$fx/.claude"
  jq -n '{features:{pr_review:false}}' > "$fx/.claude/ccanvil.json"
  run bash "$SYNC" node-role "$fx"
  [ "$status" -eq 0 ]
  [ "$output" = "substrate-consumer" ]
}

@test "BTS-384 Step 3: missing ccanvil.json defaults to substrate-consumer" {
  set -e
  fx="$BATS_TEST_TMPDIR/node-no-config"
  mkdir -p "$fx/.claude"
  run bash "$SYNC" node-role "$fx"
  [ "$status" -eq 0 ]
  [ "$output" = "substrate-consumer" ]
}
