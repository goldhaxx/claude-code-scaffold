#!/usr/bin/env bats
# BTS-135 — context-budget.sh: TTY-aware default + explicit --json/--text flags.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/context-budget.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude/rules"
  # Minimal viable project: empty CLAUDE.md is enough — the script measures
  # whatever it finds and doesn't blow up on small inputs.
  : > "$PROJECT/CLAUDE.md"
}

teardown() {
  rm -rf "$PROJECT"
}

@test "BTS-135 AC-1: --json flag produces JSON regardless of TTY (run captures non-TTY)" {
  set -e
  run bash "$SCRIPT" check --project-dir "$PROJECT" --json
  echo "$output" | jq -e 'has("files") and has("totals") and has("context")'
}

@test "BTS-135 AC-2: default invocation under bats run (non-TTY) emits JSON" {
  set -e
  # bats `run` always captures stdout — never a TTY. Default should be JSON.
  run bash "$SCRIPT" check --project-dir "$PROJECT"
  echo "$output" | jq -e 'has("totals")'
  echo "$output" | jq -e '.totals.estimated_tokens | type == "number"'
}

@test "BTS-135 AC-3: --text flag forces text output regardless of TTY" {
  run bash "$SCRIPT" check --project-dir "$PROJECT" --text
  # Text output starts with the report header
  [[ "$output" =~ "Context Budget Report" ]]
  # Not parseable as JSON
  ! echo "$output" | jq -e '.' >/dev/null 2>&1
}

@test "BTS-135 AC-4: --json --text last-wins (text wins, output is text)" {
  run bash "$SCRIPT" check --project-dir "$PROJECT" --json --text
  [[ "$output" =~ "Context Budget Report" ]]
}

@test "BTS-135 AC-4: --text --json last-wins (json wins, output is JSON)" {
  set -e
  run bash "$SCRIPT" check --project-dir "$PROJECT" --text --json
  echo "$output" | jq -e 'has("totals")'
}

@test "BTS-135 AC-5: existing JSON shape preserved — totals.estimated_tokens, totals.budget_percent, totals.status" {
  set -e
  run bash "$SCRIPT" check --project-dir "$PROJECT" --json
  echo "$output" | jq -e '.totals.estimated_tokens | type == "number"'
  echo "$output" | jq -e '.totals.budget_percent | type == "number"'
  echo "$output" | jq -e '.totals.status | type == "string"'
}

@test "BTS-135 AC-6: exit code 0 on HEALTHY (small project well under budget)" {
  # Empty project → zero tokens → HEALTHY → exit 0.
  run bash "$SCRIPT" check --project-dir "$PROJECT" --json
  [ "$status" -eq 0 ]
}

@test "BTS-135 AC-7: existing test surface (--text + --budget) continues to work" {
  set -e
  # Force CRITICAL by setting budget = 1 token. exit 2.
  run bash "$SCRIPT" check --project-dir "$PROJECT" --text --budget 1
  [ "$status" -eq 2 ]
  [[ "$output" =~ "CRITICAL" ]]
}
