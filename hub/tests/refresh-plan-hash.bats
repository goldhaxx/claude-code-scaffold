#!/usr/bin/env bats
# BTS-177 — refresh-plan-hash substrate primitive.
#
# Recomputes docs/spec.md's content_hash and rewrites docs/plan.md's
# `> Spec hash:` metadata line to match. Eliminates the manual plan-hash
# edit Claude was performing on mid-flow scope expansion.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/docs"
}

teardown() {
  rm -rf "$PROJECT"
}

# Write a minimal spec with a known body. The `> ` blockquote lines are
# excluded from content_hash; the body below it is what gets hashed.
_write_spec() {
  local body="${1:-default body content}"
  cat > "$PROJECT/docs/spec.md" <<EOF
# Feature: Test

> Feature: test-feature
> Work: linear:BTS-X
> Created: 1700000000
> Status: In Progress

## Summary

$body
EOF
}

# Write a minimal plan with a deliberately wrong spec_hash.
_write_plan_with_hash() {
  local hash="${1:-deadbeef}"
  cat > "$PROJECT/docs/plan.md" <<EOF
# Implementation Plan: Test

> Feature: test-feature
> Work: linear:BTS-X
> Created: 1700000000
> Spec hash: $hash
> Based on: docs/spec.md

## Objective

Test plan.

## Sequence

### Step 1
EOF
}

_current_spec_hash() {
  # cmd_status expects a docs_dir, not a project_dir.
  bash "$SCRIPT" status "$PROJECT/docs" | jq -r '.spec.content_hash'
}

# =========================================================================
# AC-1, AC-2, AC-8: happy path — refresh-plan-hash rewrites the line
# =========================================================================

@test "AC-1+AC-2+AC-8: refresh-plan-hash rewrites stale plan hash to match spec" {
  set -e
  _write_spec "first paragraph"
  _write_plan_with_hash "deadbeef"

  local expected_hash
  expected_hash=$(_current_spec_hash)
  [ -n "$expected_hash" ]
  [ "$expected_hash" != "deadbeef" ]

  run bash "$SCRIPT" refresh-plan-hash --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.updated == true'
  echo "$output" | jq -e --arg h "$expected_hash" '.spec_hash == $h'
  echo "$output" | jq -e '.plan == "docs/plan.md"'

  # Plan file's `> Spec hash:` line was updated.
  grep -q "^> Spec hash: $expected_hash$" "$PROJECT/docs/plan.md"
  ! grep -q "deadbeef" "$PROJECT/docs/plan.md"
}

@test "AC-2: rest of plan.md is unchanged byte-for-byte except the hash line" {
  set -e
  _write_spec "first paragraph"
  _write_plan_with_hash "deadbeef"

  # Capture all non-hash-line lines BEFORE refresh.
  grep -v "^> Spec hash:" "$PROJECT/docs/plan.md" > "$PROJECT/before.txt"

  run bash "$SCRIPT" refresh-plan-hash --project-dir "$PROJECT"
  [ "$status" -eq 0 ]

  # Capture all non-hash-line lines AFTER refresh.
  grep -v "^> Spec hash:" "$PROJECT/docs/plan.md" > "$PROJECT/after.txt"

  diff "$PROJECT/before.txt" "$PROJECT/after.txt"
}

# =========================================================================
# AC-3: idempotent — second run is no-op
# =========================================================================

@test "AC-3: second run is no-op (updated:false, file unchanged)" {
  set -e
  _write_spec "body"
  _write_plan_with_hash "deadbeef"

  bash "$SCRIPT" refresh-plan-hash --project-dir "$PROJECT" >/dev/null
  cp "$PROJECT/docs/plan.md" "$PROJECT/snapshot.md"

  run bash "$SCRIPT" refresh-plan-hash --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.updated == false'

  # Plan unchanged.
  diff "$PROJECT/snapshot.md" "$PROJECT/docs/plan.md"
}

# =========================================================================
# AC-4 (regression): refresh-plan-hash returns validate to aligned
# =========================================================================

@test "AC-4: stale-plan → refresh-plan-hash → aligned" {
  set -e
  # Need a stasis to satisfy validate's full lifecycle expectations.
  _write_spec "initial body"
  _write_plan_with_hash "$(_current_spec_hash)"
  cat > "$PROJECT/docs/stasis.md" <<EOF
# Stasis

> Feature: test-feature
> Kind: session
> Last updated: 1700000000

## Determinism Review

- operations_reviewed: 0
- candidates_found: 0

No candidates this session.
EOF

  # Aligned at this point.
  local before_state
  before_state=$(bash "$SCRIPT" validate "$PROJECT/docs" | jq -r '.result')
  [ "$before_state" = "aligned" ]

  # Mutate spec body — content_hash changes, plan's spec_hash is now stale.
  _write_spec "different body content that changes the hash"
  local stale_state
  stale_state=$(bash "$SCRIPT" validate "$PROJECT/docs" | jq -r '.result')
  [ "$stale_state" = "stale-plan" ]

  # Refresh and re-validate.
  bash "$SCRIPT" refresh-plan-hash --project-dir "$PROJECT" >/dev/null
  local final_state
  final_state=$(bash "$SCRIPT" validate "$PROJECT/docs" | jq -r '.result')
  [ "$final_state" = "aligned" ]
}

# =========================================================================
# AC-5, AC-6, AC-7: error paths
# =========================================================================

@test "AC-5: missing spec.md → non-zero exit, plan unchanged" {
  set -e
  _write_plan_with_hash "deadbeef"
  local before_md5
  before_md5=$(md5 -q "$PROJECT/docs/plan.md" 2>/dev/null || md5sum "$PROJECT/docs/plan.md" | cut -d' ' -f1)

  run bash "$SCRIPT" refresh-plan-hash --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"docs/spec.md not found"* ]] || [[ "$stderr" == *"docs/spec.md not found"* ]]

  local after_md5
  after_md5=$(md5 -q "$PROJECT/docs/plan.md" 2>/dev/null || md5sum "$PROJECT/docs/plan.md" | cut -d' ' -f1)
  [ "$before_md5" = "$after_md5" ]
}

@test "AC-6: missing plan.md → non-zero exit with clear error" {
  _write_spec "body"

  run bash "$SCRIPT" refresh-plan-hash --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"docs/plan.md not found"* ]] || [[ "$stderr" == *"docs/plan.md not found"* ]]
}

@test "AC-7: plan.md missing '> Spec hash:' line → non-zero exit, file unchanged" {
  set -e
  _write_spec "body"
  cat > "$PROJECT/docs/plan.md" <<EOF
# Plan without spec hash metadata

This plan has no metadata blockquote.
EOF
  local before_md5
  before_md5=$(md5 -q "$PROJECT/docs/plan.md" 2>/dev/null || md5sum "$PROJECT/docs/plan.md" | cut -d' ' -f1)

  run bash "$SCRIPT" refresh-plan-hash --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Spec hash:"* ]] || [[ "$stderr" == *"Spec hash:"* ]]

  local after_md5
  after_md5=$(md5 -q "$PROJECT/docs/plan.md" 2>/dev/null || md5sum "$PROJECT/docs/plan.md" | cut -d' ' -f1)
  [ "$before_md5" = "$after_md5" ]
}

# =========================================================================
# AC-9 (drift-guard): atomic write — uses mktemp+mv, not direct redirect
# =========================================================================

@test "AC-9: cmd_refresh_plan_hash uses mktemp + mv (atomic write)" {
  set -e
  # Extract the function body and assert mktemp is used and direct redirect
  # to the destination plan file is absent.
  local fn_body
  fn_body=$(awk '/^cmd_refresh_plan_hash\(\) \{/,/^\}/' "$SCRIPT")
  [ -n "$fn_body" ]
  printf '%s' "$fn_body" | grep -q 'mktemp'
  printf '%s' "$fn_body" | grep -q 'mv '
  # No direct write to the destination path (would be a non-atomic write).
  ! printf '%s' "$fn_body" | grep -qE '> *"\$plan_file"'
}
