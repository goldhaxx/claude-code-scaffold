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

  # Disable global CLAUDE.md by default (point to nonexistent path)
  # Tests that need it override with --global-claude-md
  NO_GLOBAL="--global-claude-md /nonexistent/CLAUDE.md"
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
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
}

@test "--help prints usage and exits 2" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}


# =========================================================================
# Step 2: File discovery and per-file measurement (AC-1, AC-2)
# =========================================================================

@test "check outputs files array with per-file entries" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.files | type == "array"'
  echo "$output" | jq -e '.files | length > 0'
}

@test "each file entry has path, lines, chars, estimated_tokens" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.files[0] | has("path", "lines", "chars", "estimated_tokens")'
}

@test "project CLAUDE.md is measured" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.files[] | select(.path | endswith("CLAUDE.md"))] | length > 0'
}

@test "rules files are measured" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.files[] | select(.path | contains("rules/"))] | length > 0'
}

@test "settings.json is measured" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.files[] | select(.path | endswith("settings.json"))] | length > 0'
}

@test ".claudeignore is measured" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.files[] | select(.path | endswith(".claudeignore"))] | length > 0'
}

@test "token estimation uses ceil(chars/4)" {
  # CLAUDE.md has 20 chars → ceil(20/4) = 5 tokens
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  local tokens
  tokens=$(echo "$output" | jq '[.files[] | select(.path | endswith("CLAUDE.md"))][0].estimated_tokens')
  [ "$tokens" -eq 5 ]
}

@test "totals object has aggregate lines, chars, estimated_tokens" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.totals | has("lines", "chars", "estimated_tokens")'
}

@test "totals are sum of individual files" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  # 20 + 8 + 12 + 4 = 44 chars total
  local total_chars
  total_chars=$(echo "$output" | jq '.totals.chars')
  local sum_chars
  sum_chars=$(echo "$output" | jq '[.files[].chars] | add')
  [ "$total_chars" -eq "$sum_chars" ]
}


# =========================================================================
# Step 3: Budget computation and exit codes (AC-3, AC-5, AC-12)
# =========================================================================

@test "default budget ceiling is 200000 * 0.04 = 8000" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  local ceiling
  ceiling=$(echo "$output" | jq '.context.budget_ceiling')
  [ "$ceiling" -eq 8000 ]
}

@test "totals includes budget_percent" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.totals | has("budget_percent")'
}

@test "context object has model, context_window, budget_ceiling, source" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.context | has("model", "context_window", "budget_ceiling", "source")'
}

@test "default source is 'default'" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  local source
  source=$(echo "$output" | jq -r '.context.source')
  [ "$source" = "default" ]
}

@test "default context_window is 200000" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  local window
  window=$(echo "$output" | jq '.context.context_window')
  [ "$window" -eq 200000 ]
}

@test "exit 0 (HEALTHY) when under 70% of budget" {
  # Fixture total: 11 tokens, budget 8000 → 0.1% → HEALTHY
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
}

@test "exit 1 (WARNING) when 70-90% of budget" {
  # 11 tokens total in fixture. Set budget to 15 → 11/15 = 73% → WARNING
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --budget 15
  [ "$status" -eq 1 ]
}

@test "exit 2 (CRITICAL) when over 90% of budget" {
  # 11 tokens total in fixture. Set budget to 11 → 100% → CRITICAL
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --budget 11
  [ "$status" -eq 2 ]
}

@test "totals includes status field" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  local status_val
  status_val=$(echo "$output" | jq -r '.totals.status')
  [ "$status_val" = "HEALTHY" ]
}


# =========================================================================
# Step 4: --context-window, --model, --budget flags (AC-3, AC-6, AC-11)
# =========================================================================

@test "--context-window 1000000 sets budget to 40000" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --context-window 1000000
  [ "$status" -eq 0 ]
  local ceiling
  ceiling=$(echo "$output" | jq '.context.budget_ceiling')
  [ "$ceiling" -eq 40000 ]
  local window
  window=$(echo "$output" | jq '.context.context_window')
  [ "$window" -eq 1000000 ]
}

@test "--context-window sets source to context-window" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --context-window 500000
  [ "$status" -eq 0 ]
  local source
  source=$(echo "$output" | jq -r '.context.source')
  [ "$source" = "context-window" ]
}

@test "--model claude-opus-4-6[1m] sets window to 1000000" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --model 'claude-opus-4-6[1m]'
  [ "$status" -eq 0 ]
  local window
  window=$(echo "$output" | jq '.context.context_window')
  [ "$window" -eq 1000000 ]
  local ceiling
  ceiling=$(echo "$output" | jq '.context.budget_ceiling')
  [ "$ceiling" -eq 40000 ]
}

@test "--model claude-opus-4-6 sets window to 200000" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --model 'claude-opus-4-6'
  [ "$status" -eq 0 ]
  local window
  window=$(echo "$output" | jq '.context.context_window')
  [ "$window" -eq 200000 ]
}

@test "--model claude-sonnet-4-6 sets window to 200000" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --model 'claude-sonnet-4-6'
  [ "$status" -eq 0 ]
  local window
  window=$(echo "$output" | jq '.context.context_window')
  [ "$window" -eq 200000 ]
}

@test "--model sets source to model and records model id" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --model 'claude-opus-4-6[1m]'
  [ "$status" -eq 0 ]
  local source
  source=$(echo "$output" | jq -r '.context.source')
  [ "$source" = "model" ]
  local model
  model=$(echo "$output" | jq -r '.context.model')
  [ "$model" = "claude-opus-4-6[1m]" ]
}

@test "unknown model defaults to 200000 with stderr warning" {
  # Capture stderr separately
  local stderr_out
  stderr_out=$(bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --model 'claude-future-99' 2>&1 >/dev/null) || true
  [[ "$stderr_out" == *"Unknown model"* ]]

  # Verify JSON output is correct (redirect stderr away)
  run bash -c "bash '$SCRIPT' check --project-dir '$FIXTURE' $NO_GLOBAL --model 'claude-future-99' 2>/dev/null"
  [ "$status" -eq 0 ]
  local window
  window=$(echo "$output" | jq '.context.context_window')
  [ "$window" -eq 200000 ]
}

@test "--budget overrides --context-window" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --context-window 1000000 --budget 5000
  [ "$status" -eq 0 ]
  local ceiling
  ceiling=$(echo "$output" | jq '.context.budget_ceiling')
  [ "$ceiling" -eq 5000 ]
  local source
  source=$(echo "$output" | jq -r '.context.source')
  [ "$source" = "flag" ]
}

@test "--budget overrides --model" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL --model 'claude-opus-4-6[1m]' --budget 3000
  [ "$status" -eq 0 ]
  local ceiling
  ceiling=$(echo "$output" | jq '.context.budget_ceiling')
  [ "$ceiling" -eq 3000 ]
  local source
  source=$(echo "$output" | jq -r '.context.source')
  [ "$source" = "flag" ]
}


# =========================================================================
# Step 5: Global CLAUDE.md and missing file handling (AC-7, AC-8)
# =========================================================================

@test "global CLAUDE.md is included when --global-claude-md points to existing file" {
  # Create a fake global CLAUDE.md
  printf '1234567890123456' > "$FIXTURE/global-claude.md"  # 16 chars = 4 tokens
  run bash "$SCRIPT" check --project-dir "$FIXTURE" --global-claude-md "$FIXTURE/global-claude.md"
  [ "$status" -eq 0 ]
  # Should have two CLAUDE.md entries
  local claude_count
  claude_count=$(echo "$output" | jq '[.files[] | select(.path | endswith("CLAUDE.md") or endswith("global-claude.md"))] | length')
  [ "$claude_count" -eq 2 ]
}

@test "global CLAUDE.md is silently skipped when file doesn't exist" {
  run bash "$SCRIPT" check --project-dir "$FIXTURE" --global-claude-md "/nonexistent/CLAUDE.md"
  [ "$status" -eq 0 ]
  # Should only have project CLAUDE.md
  local claude_count
  claude_count=$(echo "$output" | jq '[.files[] | select(.path | endswith("CLAUDE.md"))] | length')
  [ "$claude_count" -eq 1 ]
}

@test "missing project CLAUDE.md produces warning entry" {
  rm "$FIXTURE/CLAUDE.md"
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.warnings | length > 0'
  echo "$output" | jq -e '[.warnings[] | select(.type == "missing_file")] | length > 0'
}

@test "missing optional files are silently skipped" {
  # Remove .claudeignore (optional)
  rm "$FIXTURE/.claudeignore"
  run bash "$SCRIPT" check --project-dir "$FIXTURE" $NO_GLOBAL
  [ "$status" -eq 0 ]
  # No warning about .claudeignore
  local ignore_warnings
  ignore_warnings=$(echo "$output" | jq '[.warnings // [] | .[] | select(.path | contains("claudeignore"))] | length')
  [ "$ignore_warnings" -eq 0 ]
}
