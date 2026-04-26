#!/usr/bin/env bats
# BTS-22 — AC-6: cmd_validate isolation guarantee.
#
# Adding files to docs/sessions/ must NOT affect cmd_validate's result.
# The session archive is independent of the live lifecycle triplet.

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

# =========================================================================
# AC-6: validate ignores docs/sessions/ entirely
# =========================================================================

@test "AC-6: empty project + populated docs/sessions/ → no-active-spec (unchanged)" {
  set -e
  mkdir -p "$PROJECT/docs/sessions"
  cat > "$PROJECT/docs/sessions/1700000000-stale.md" <<EOF
# Stasis

> Feature: stale-feature-id
> Kind: session
> Last updated: 1700000000

stale content
EOF

  run bash "$SCRIPT" validate "$PROJECT/docs"
  [ "$status" -eq 0 ]
  local result
  result=$(echo "$output" | jq -r '.result')
  # Without an active spec/plan/stasis triplet, validate should report
  # 'aligned' (BTS-141: missing spec.md AND plan.md is the no-active-spec
  # form, treated as aligned).
  [[ "$result" == "aligned" || "$result" == "no-active-spec" ]]
}

@test "AC-6: aligned project + populated docs/sessions/ → result unchanged" {
  set -e
  # Create an aligned active triplet.
  cat > "$PROJECT/docs/spec.md" <<EOF
# Feature: Test

> Feature: bts-x-test
> Work: linear:BTS-X
> Created: 1700000000
> Status: In Progress

## Summary

Test summary.

## Acceptance Criteria

- [ ] AC-1
EOF

  cat > "$PROJECT/docs/plan.md" <<EOF
# Plan

> Feature: bts-x-test
> Work: linear:BTS-X
> Created: 1700000000
> Spec hash: PLACEHOLDER

## Sequence

step.
EOF

  # Compute spec_hash AND plan_hash from the actual files; stasis's Plan hash
  # must match the plan's content_hash (not the spec's) for alignment.
  local spec_hash plan_hash
  spec_hash=$(bash "$SCRIPT" status "$PROJECT/docs" | jq -r '.spec.content_hash')
  # Patch plan with the real spec_hash, then read the plan's content_hash.
  sed -i.bak "s/PLACEHOLDER/$spec_hash/" "$PROJECT/docs/plan.md" && rm "$PROJECT/docs/plan.md.bak"
  plan_hash=$(bash "$SCRIPT" status "$PROJECT/docs" | jq -r '.plan.content_hash')

  cat > "$PROJECT/docs/stasis.md" <<EOF
# Stasis

> Feature: bts-x-test
> Kind: feature
> Created: 1700000000
> Plan hash: $plan_hash

## Determinism Review

- operations_reviewed: 0
- candidates_found: 0

No candidates this session.
EOF

  # Capture baseline validate result (whatever it is — aligned in the
  # happy path, but the contract is isolation, not the specific outcome).
  local baseline_result
  baseline_result=$(bash "$SCRIPT" validate "$PROJECT/docs" | jq -r '.result')

  # Now drop stale-shaped session files into docs/sessions/.
  mkdir -p "$PROJECT/docs/sessions"
  cat > "$PROJECT/docs/sessions/1700000000-completely-different.md" <<EOF
# Stasis
> Feature: completely-different
> Kind: session
> Last updated: 1700000000
EOF
  cat > "$PROJECT/docs/sessions/1750000000-mismatched.md" <<EOF
# Stasis
> Feature: not-the-active-feature
> Kind: session
> Last updated: 1750000000
EOF

  local after_result
  after_result=$(bash "$SCRIPT" validate "$PROJECT/docs" | jq -r '.result')

  # Isolation contract: same result before and after.
  [ "$baseline_result" = "$after_result" ]
}
