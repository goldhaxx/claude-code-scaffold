#!/usr/bin/env bats
#
# BTS-316 Step 3: operator-config commands (init/get/set/show).
#
# Manages $HOME/.ccanvil/operator.json — the operator-wide defaults that the
# 3-tier merge_config (BTS-316 Step 2) reads as the lowest-precedence tier.
# The four subcommands give scripts and skills a deterministic interface for
# reading/writing operator-wide settings without hand-editing JSON.

bats_require_minimum_version 1.5.0

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export HOME="$BATS_TEST_TMPDIR/fake-home"
}

@test "BTS-316 AC-1: operator-config init writes seeded shape with provider+team" {
  set -e
  run bash "$DC" operator-config init --provider linear --team "Acme Corp"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ccanvil/operator.json" ]
  jq -e '.integrations.providers.linear.team == "Acme Corp"' "$HOME/.ccanvil/operator.json" >/dev/null
  jq -e '.integrations.default_routes.spec == "linear"' "$HOME/.ccanvil/operator.json" >/dev/null
  jq -e '.integrations.default_routes.plan == "linear"' "$HOME/.ccanvil/operator.json" >/dev/null
  jq -e '.integrations.default_routes.stasis == "linear"' "$HOME/.ccanvil/operator.json" >/dev/null
  jq -e '.integrations.default_routes.idea == "linear"' "$HOME/.ccanvil/operator.json" >/dev/null
}

@test "BTS-316 AC-1: operator-config init is idempotent — second run produces zero diff" {
  set -e
  bash "$DC" operator-config init --provider linear --team "Acme Corp"
  cp "$HOME/.ccanvil/operator.json" "$BATS_TEST_TMPDIR/snapshot.json"
  bash "$DC" operator-config init --provider linear --team "Acme Corp"
  diff -q "$BATS_TEST_TMPDIR/snapshot.json" "$HOME/.ccanvil/operator.json"
}

@test "BTS-316 AC-2: operator-config get reads dotted path" {
  set -e
  bash "$DC" operator-config init --provider linear --team "Acme Corp"
  run bash "$DC" operator-config get integrations.providers.linear.team
  [ "$status" -eq 0 ]
  [ "$output" = "Acme Corp" ]
}

@test "BTS-316 AC-2: operator-config get returns empty + exit 0 on missing key" {
  set -e
  bash "$DC" operator-config init --provider linear --team "Acme Corp"
  run bash "$DC" operator-config get integrations.providers.linear.nonexistent
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-316 AC-2: operator-config get on missing file returns empty + exit 0" {
  set -e
  # No init — operator.json does not exist.
  run bash "$DC" operator-config get integrations.providers.linear.team
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-316 AC-3: operator-config set updates dotted key" {
  set -e
  bash "$DC" operator-config init --provider linear --team "Acme Corp"
  run bash "$DC" operator-config set integrations.providers.linear.team "Beta Co"
  [ "$status" -eq 0 ]
  run bash "$DC" operator-config get integrations.providers.linear.team
  [ "$output" = "Beta Co" ]
}

@test "BTS-316 AC-3: operator-config set creates the file when absent" {
  set -e
  # No init first.
  run bash "$DC" operator-config set integrations.providers.linear.team "Solo"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ccanvil/operator.json" ]
  jq -e '.integrations.providers.linear.team == "Solo"' "$HOME/.ccanvil/operator.json" >/dev/null
}

@test "BTS-316 AC-3: operator-config set creates the parent dir when absent" {
  set -e
  # Test that .ccanvil/ does not need to pre-exist.
  [ ! -d "$HOME/.ccanvil" ]
  run bash "$DC" operator-config set foo.bar baz
  [ "$status" -eq 0 ]
  [ -d "$HOME/.ccanvil" ]
  jq -e '.foo.bar == "baz"' "$HOME/.ccanvil/operator.json" >/dev/null
}

@test "BTS-316 AC-3: operator-config set writes valid JSON atomically" {
  set -e
  bash "$DC" operator-config set a.b "first"
  bash "$DC" operator-config set a.c "second"
  bash "$DC" operator-config set a.d "third"
  jq empty "$HOME/.ccanvil/operator.json"
  jq -e '.a.b == "first" and .a.c == "second" and .a.d == "third"' "$HOME/.ccanvil/operator.json" >/dev/null
}

@test "BTS-316 AC-4: operator-config show emits pretty JSON" {
  set -e
  bash "$DC" operator-config init --provider linear --team "Acme Corp"
  run bash "$DC" operator-config show
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrations.providers.linear.team == "Acme Corp"' >/dev/null
}

@test "BTS-316 AC-4: operator-config show on missing file emits {}" {
  set -e
  run bash "$DC" operator-config show
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {}' >/dev/null
}

@test "BTS-316 Step 3: operator-config init rejects non-linear provider (Phase 1 only)" {
  run --separate-stderr bash "$DC" operator-config init --provider notion --team "X"
  [ "$status" -ne 0 ]
  echo "$stderr" | grep -q linear
}

@test "BTS-316 Step 3: operator-config get/set use 3-tier merge_config end-to-end" {
  # Activation flow: init operator-config, then verify merge_config in a
  # downstream fx picks up the operator team as a default.
  set -e
  bash "$DC" operator-config init --provider linear --team "Op-Team"
  fx="$BATS_TEST_TMPDIR/node-fx"
  mkdir -p "$fx/.claude"
  echo '{}' > "$fx/.claude/ccanvil.json"
  OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"
  run bash "$OPS" merge-config --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrations.providers.linear.team == "Op-Team"' >/dev/null
}
