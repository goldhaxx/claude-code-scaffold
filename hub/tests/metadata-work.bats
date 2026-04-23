#!/usr/bin/env bats
# Tests for Work: and Kind: metadata parsing in docs-check.sh
# BTS-130 (work-identity) — Phase 1: foundation.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  DOCS=$(mktemp -d)
}

teardown() {
  rm -rf "$DOCS"
}

# ---------------------------------------------------------------------------
# Step 1 — parse_metadata extracts `work` from `> Work:` blockquote line
# ---------------------------------------------------------------------------

@test "BTS-130 step 1: status emits spec.work when > Work: present" {
  cat > "$DOCS/spec.md" <<EOF
# Feature: Test

> Feature: bts-130-test
> Work: linear:BTS-130
> Created: 1776973070
> Status: In Progress

## Summary

Body.
EOF
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.spec.work == "linear:BTS-130"'
}

@test "BTS-130 step 1: status emits empty spec.work when > Work: absent" {
  cat > "$DOCS/spec.md" <<EOF
# Feature: Test

> Feature: bts-130-test
> Created: 1776973070
> Status: In Progress

## Summary

Body.
EOF
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]
  # Absent Work: → field is either missing or empty; jq `// empty` normalizes both.
  local work_val
  work_val=$(echo "$output" | jq -r '.spec.work // ""')
  [ "$work_val" = "" ]
}

# ---------------------------------------------------------------------------
# Step 2 — parse_metadata extracts `kind` from `> Kind:` on stasis
# ---------------------------------------------------------------------------

@test "BTS-130 step 2: status emits stasis.kind=session when > Kind: session" {
  cat > "$DOCS/stasis.md" <<EOF
# Stasis

> Feature: session-2026-04-23-example-ship
> Kind: session
> Last updated: 1776971680

## Accomplished

Body.
EOF
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stasis.kind == "session"'
}

@test "BTS-130 step 2: status emits stasis.kind=feature when > Kind: feature" {
  cat > "$DOCS/stasis.md" <<EOF
# Stasis

> Feature: bts-130-work-identity
> Work: linear:BTS-130
> Kind: feature
> Last updated: 1776971680

## Accomplished

Body.
EOF
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stasis.kind == "feature"'
}

@test "BTS-130 step 2: status emits empty stasis.kind when > Kind: absent" {
  cat > "$DOCS/stasis.md" <<EOF
# Stasis

> Feature: legacy-stasis-no-kind
> Last updated: 1776971680

## Accomplished

Body.
EOF
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]
  local kind_val
  kind_val=$(echo "$output" | jq -r '.stasis.kind // ""')
  [ "$kind_val" = "" ]
}
