#!/usr/bin/env bats
#
# BTS-384 Step 4: scope filter at sync.
#
# Helper matrix: scope ∈ {universal, substrate, hub-only, missing}, role ∈
# {hub-substrate-developer, substrate-consumer}. Plus non-rule path (filter does
# not apply). Tested via the `scope-check` verb that exposes the helper directly.
#
# Integration: one end-to-end pull-plan case — a `scope: substrate` rule
# appears as a `scope-skipped` action for substrate-consumer nodes and an
# `auto-update` action for hub-substrate-developer nodes.

bats_require_minimum_version 1.5.0

SYNC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

# ----- Helper matrix (lightweight) -------------------------------------------

_make_rule() {
  local path="$1" scope_line="$2"
  cat > "$path" <<EOF
---
tier: 0
${scope_line}
stack: any
anchors: {}
---

# Rule

Body.
EOF
}

@test "BTS-384 Step 4: universal × hub-substrate-developer → allowed" {
  set -e
  fx="$BATS_TEST_TMPDIR/uni-hub.md"
  _make_rule "$fx" "scope: universal"
  run bash "$SYNC" scope-check "$fx" hub-substrate-developer
  [ "$status" -eq 0 ]
  [ "$output" = "allowed" ]
}

@test "BTS-384 Step 4: universal × substrate-consumer → allowed" {
  set -e
  fx="$BATS_TEST_TMPDIR/uni-cons.md"
  _make_rule "$fx" "scope: universal"
  run bash "$SYNC" scope-check "$fx" substrate-consumer
  [ "$status" -eq 0 ]
  [ "$output" = "allowed" ]
}

@test "BTS-384 Step 4: substrate × hub-substrate-developer → allowed" {
  set -e
  fx="$BATS_TEST_TMPDIR/sub-hub.md"
  _make_rule "$fx" "scope: substrate"
  run bash "$SYNC" scope-check "$fx" hub-substrate-developer
  [ "$status" -eq 0 ]
  [ "$output" = "allowed" ]
}

@test "BTS-384 Step 4 (AC-3): substrate × substrate-consumer → skipped:substrate" {
  fx="$BATS_TEST_TMPDIR/sub-cons.md"
  _make_rule "$fx" "scope: substrate"
  run bash "$SYNC" scope-check "$fx" substrate-consumer
  [ "$status" -eq 1 ]
  [ "$output" = "skipped:substrate" ]
}

@test "BTS-384 Step 4 (AC-4): hub-only × hub-substrate-developer → skipped:hub-only" {
  fx="$BATS_TEST_TMPDIR/hubonly-hub.md"
  _make_rule "$fx" "scope: hub-only"
  run bash "$SYNC" scope-check "$fx" hub-substrate-developer
  [ "$status" -eq 1 ]
  [ "$output" = "skipped:hub-only" ]
}

@test "BTS-384 Step 4 (AC-4): hub-only × substrate-consumer → skipped:hub-only" {
  fx="$BATS_TEST_TMPDIR/hubonly-cons.md"
  _make_rule "$fx" "scope: hub-only"
  run bash "$SYNC" scope-check "$fx" substrate-consumer
  [ "$status" -eq 1 ]
  [ "$output" = "skipped:hub-only" ]
}

@test "BTS-384 Step 4: missing scope key defaults to allowed (back-compat)" {
  set -e
  fx="$BATS_TEST_TMPDIR/no-scope.md"
  cat > "$fx" <<'EOF'
---
tier: 0
stack: any
anchors: {}
---

# Rule

Body without scope key.
EOF
  run bash "$SYNC" scope-check "$fx" substrate-consumer
  [ "$status" -eq 0 ]
  [ "$output" = "allowed" ]
}

@test "BTS-384 Step 4: non-rule path (script) is always allowed (filter scoped to rules only)" {
  set -e
  fx="$BATS_TEST_TMPDIR/script.sh"
  echo '#!/bin/bash' > "$fx"
  run bash "$SYNC" scope-check "$fx" substrate-consumer
  [ "$status" -eq 0 ]
  [ "$output" = "allowed" ]
}

# ----- Integration test -------------------------------------------------------

setup_file() {
  TMPDIR_BATS=$(mktemp -d)
  export TMPDIR_BATS
  HUB_DIR="$TMPDIR_BATS/hub"
  NODE_DIR="$TMPDIR_BATS/node"
  export HUB_DIR NODE_DIR
  mkdir -p "$HUB_DIR/.claude/rules" "$HUB_DIR/.ccanvil/scripts"
  mkdir -p "$NODE_DIR/.claude/rules" "$NODE_DIR/.ccanvil"

  # Initialize hub as a git repo (cmd_changelog dependency)
  cd "$HUB_DIR"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"

  _make_rule_v2() {
    local path="$1" scope="$2" body="$3"
    cat > "$path" <<EOF
---
tier: 0
scope: $scope
stack: any
anchors: {}
---

# Rule v2

$body
EOF
  }
  # Hub: one substrate rule, one universal rule
  _make_rule_v2 "$HUB_DIR/.claude/rules/sub-test.md" "substrate" "Substrate body."
  _make_rule_v2 "$HUB_DIR/.claude/rules/uni-test.md" "universal" "Universal body."
  cd "$HUB_DIR"
  git add -A
  git commit -q -m "feat: initial rules"
  HUB_VERSION=$(git rev-parse HEAD)
  export HUB_VERSION
  cd - >/dev/null

  # Node: copy the same rules + ccanvil.json with role=substrate-consumer
  cp "$HUB_DIR/.claude/rules/sub-test.md" "$NODE_DIR/.claude/rules/sub-test.md"
  cp "$HUB_DIR/.claude/rules/uni-test.md" "$NODE_DIR/.claude/rules/uni-test.md"
  jq -n '{role:"substrate-consumer"}' > "$NODE_DIR/.claude/ccanvil.json"

  # Pre-compute hashes for the lockfile. `cmd_hash` emits `<hash> <path>` (the
  # sha256sum -r format); take the first field for storage.
  sub_hash=$(bash "$SYNC" hash "$NODE_DIR/.claude/rules/sub-test.md" | awk '{print $1}')
  uni_hash=$(bash "$SYNC" hash "$NODE_DIR/.claude/rules/uni-test.md" | awk '{print $1}')
  cat > "$NODE_DIR/.ccanvil/ccanvil.lock" <<EOF
{"hub_source":"$HUB_DIR","hub_version":"$HUB_VERSION","node_uuid":"deadbeef",
 "files":{
   ".claude/rules/sub-test.md":{"origin":"hub","status":"clean","hub_hash":"$sub_hash","local_hash":"$sub_hash"},
   ".claude/rules/uni-test.md":{"origin":"hub","status":"clean","hub_hash":"$uni_hash","local_hash":"$uni_hash"}
 }}
EOF

  # Mutate hub: change both rules so pull-plan would normally emit auto-update
  cd "$HUB_DIR"
  sed -i.bak 's/Substrate body./Substrate body changed./' .claude/rules/sub-test.md
  sed -i.bak 's/Universal body./Universal body changed./' .claude/rules/uni-test.md
  rm -f .claude/rules/*.bak
  git add -A
  git commit -q -m "feat: mutate rules"
  cd - >/dev/null
}

teardown_file() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

@test "BTS-384 Step 4 integration: substrate rule emits scope-skipped for consumer node" {
  set -e
  cd "$NODE_DIR"
  run bash "$SYNC" pull-plan
  cd - >/dev/null
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.file == ".claude/rules/sub-test.md") | .action == "scope-skipped"'
  echo "$output" | jq -e '.[] | select(.file == ".claude/rules/uni-test.md") | .action == "auto-update"'
}

@test "BTS-384 Step 4 integration: substrate rule emits auto-update for hub role" {
  set -e
  jq '.role = "hub-substrate-developer"' "$NODE_DIR/.claude/ccanvil.json" > "$NODE_DIR/.claude/ccanvil.json.tmp"
  mv "$NODE_DIR/.claude/ccanvil.json.tmp" "$NODE_DIR/.claude/ccanvil.json"
  cd "$NODE_DIR"
  run bash "$SYNC" pull-plan
  cd - >/dev/null
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.file == ".claude/rules/sub-test.md") | .action == "auto-update"'
  echo "$output" | jq -e '.[] | select(.file == ".claude/rules/uni-test.md") | .action == "auto-update"'
}
