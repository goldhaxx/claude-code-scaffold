#!/usr/bin/env bats
# Tests for scripts/context-budget.sh
#
# Each test creates an isolated fixture directory with known file content
# to get deterministic token counts.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/context-budget.sh"

setup() {
  FIXTURE=$(mktemp -d)

  # Create a minimal project structure with known content
  mkdir -p "$FIXTURE/.claude/rules"

  # Project CLAUDE.md — 20 chars = 5 tokens
  printf '12345678901234567890' > "$FIXTURE/CLAUDE.md"

  # One rule file — 8 chars = 2 tokens
  printf '12345678' > "$FIXTURE/.claude/rules/test-rule.md"

  # Settings file — 12 chars = 3 tokens
  printf '{"perms": 1}' > "$FIXTURE/.claude/settings.json"

  # .claudeignore — 4 chars = 1 token
  printf 'dist' > "$FIXTURE/.claudeignore"
}

teardown() {
  rm -rf "$FIXTURE"
}


# =========================================================================
# Step 1: Script skeleton with usage and arg parsing
# =========================================================================

@test "no arguments prints usage and exits 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown command prints usage and exits 2" {
  run bash "$SCRIPT" foo
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "check outputs valid JSON" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
}

@test "--help prints usage and exits 2" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}
