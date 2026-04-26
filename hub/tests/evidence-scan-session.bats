#!/usr/bin/env bats
# BTS-201 — unit tests for evidence-scan-session substrate primitive.
#
# Tests the docs-check.sh evidence-scan-session subcommand using canned
# JSON fixtures via --input-json so live Linear is never touched.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

# Helper: write canned issues JSON to a tempfile, return the path.
write_fixture() {
  local path="$TMPDIR_BATS/$1"
  shift
  cat > "$path"
  echo "$path"
}

# =========================================================================
# AC-8(a): zero captures
# =========================================================================

@test "AC-8a: zero captures returns evidence_gaps=[] scanned=0" {
  fixture=$(echo '[]' | write_fixture issues.json)
  run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.evidence_gaps == [] and .scanned == 0'
}

# =========================================================================
# AC-8(b): bug-shape title, no anchors → one gap
# =========================================================================

@test "AC-8b: bug-shape title without anchors emits one gap" {
  fixture=$(jq -n '[{
    id: "BTS-9001",
    title: "guard-destructive false positive in jq dict literals",
    description: "Likely root cause: regex matches braces. We worked around it.",
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scanned == 1'
  echo "$output" | jq -e '.evidence_gaps | length == 1'
  echo "$output" | jq -e '.evidence_gaps[0].id == "BTS-9001"'
  echo "$output" | jq -e '.evidence_gaps[0].reason == "missing-evidence-anchors"'
}

# =========================================================================
# AC-8(c): bug-shape title with all four anchors → zero gaps
# =========================================================================

@test "AC-8c: bug-shape title with all four anchors emits zero gaps" {
  body='Command: bash run.sh
Output: error: foo
Exit: 2
Reproduce: bash run.sh && echo $?'
  fixture=$(jq -n --arg b "$body" '[{
    id: "BTS-9002",
    title: "the foo command fails on macOS",
    description: $b,
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scanned == 1'
  echo "$output" | jq -e '.evidence_gaps | length == 0'
}

# =========================================================================
# AC-8(d) / AC-10: DIAGNOSE: titles are exempt
# =========================================================================

@test "AC-8d: DIAGNOSE: title is exempt from anchor requirement" {
  fixture=$(jq -n '[{
    id: "BTS-9003",
    title: "DIAGNOSE: intermittent watchdog failures",
    description: "we should add instrumentation",
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scanned == 1'
  echo "$output" | jq -e '.evidence_gaps | length == 0'
}

# =========================================================================
# AC-8(e): malformed JSON exits non-zero
# =========================================================================

@test "AC-8e: malformed JSON exits non-zero with clear error" {
  fixture=$(echo 'not-json-at-all' | write_fixture bad.json)
  run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ERROR" ]]
}

# =========================================================================
# AC-11: 24h fallback when --since is unresolvable
# =========================================================================

@test "AC-11: --since unresolvable triggers 24h fallback" {
  fixture=$(echo '[]' | write_fixture issues.json)
  run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --since "this-is-not-a-real-commit"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.fallback == "24h"'
}

# =========================================================================
# Bonus: non-bug captures pass through (heuristic only fires on bug shape)
# =========================================================================

@test "non-bug captures are not flagged even without anchors" {
  fixture=$(jq -n '[{
    id: "BTS-9004",
    title: "Add cool new feature for X",
    description: "this would be nice to have",
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scanned == 1'
  echo "$output" | jq -e '.evidence_gaps | length == 0'
}
