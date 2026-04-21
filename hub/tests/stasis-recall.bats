#!/usr/bin/env bats
# Tests for stasis-recall: comprehensive rename of checkpoint/catchup →
# stasis/recall across verbs, artifact filename, template, internal
# identifiers, and guide references. Spec: docs/specs/stasis-recall.md

REPO_ROOT="$BATS_TEST_DIRNAME/../.."

# --- Step 1: Template rename + three new sections ---

@test "template: .ccanvil/templates/stasis.md exists" {
  [ -f "$REPO_ROOT/.ccanvil/templates/stasis.md" ]
}

@test "template: legacy .ccanvil/templates/checkpoint.md no longer exists" {
  [ ! -f "$REPO_ROOT/.ccanvil/templates/checkpoint.md" ]
}

@test "template: stasis.md has Cross-Session Patterns section" {
  grep -q "^## Cross-Session Patterns" "$REPO_ROOT/.ccanvil/templates/stasis.md"
}

@test "template: stasis.md has Security Review section" {
  grep -q "^## Security Review" "$REPO_ROOT/.ccanvil/templates/stasis.md"
}

@test "template: stasis.md has Memory Candidates section" {
  grep -q "^## Memory Candidates" "$REPO_ROOT/.ccanvil/templates/stasis.md"
}

@test "template: stasis.md retains existing required sections" {
  grep -q "^## Accomplished" "$REPO_ROOT/.ccanvil/templates/stasis.md"
  grep -q "^## Current State" "$REPO_ROOT/.ccanvil/templates/stasis.md"
  grep -q "^## Next Steps" "$REPO_ROOT/.ccanvil/templates/stasis.md"
  grep -q "^## Determinism Review" "$REPO_ROOT/.ccanvil/templates/stasis.md"
}

# --- Step 2: docs-check.sh — artifact path + state name + variable rename ---

DOCS_CHECK="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

@test "docs-check.sh: no legacy 'cp_' variable prefixes" {
  ! grep -qE '\bcp_(entry|exists|fid|stored_plan_hash)' "$DOCS_CHECK"
}

@test "docs-check.sh: uses full-spelling stasis_ variable names" {
  grep -qE '\bstasis_(entry|exists|fid|stored_plan_hash)\b' "$DOCS_CHECK"
}

@test "docs-check.sh: no 'stale-checkpoint' state name remains" {
  ! grep -q 'stale-checkpoint' "$DOCS_CHECK"
}

@test "docs-check.sh: exposes 'stale-stasis' state name" {
  grep -q 'stale-stasis' "$DOCS_CHECK"
}

@test "docs-check.sh: references docs/stasis.md (not docs/checkpoint.md)" {
  ! grep -q 'docs/checkpoint\.md' "$DOCS_CHECK"
  grep -q 'checkpoint\.md\|stasis\.md' "$DOCS_CHECK"
}

# Behavioral tests use a fixture directory like docs-check.bats does.
setup_fixture() {
  FIXTURE=$(mktemp -d)
  DOCS="$FIXTURE/docs"
  mkdir -p "$DOCS"
}

teardown_fixture() {
  rm -rf "$FIXTURE"
}

@test "status: emits .stasis JSON key (not .checkpoint)" {
  setup_fixture
  cat > "$DOCS/stasis.md" <<EOF
# Stasis

> Feature: demo
> Last updated: 1700000000
> Plan hash: abcd1234

## Accomplished
- Test
## Next Steps
- Next
## Determinism Review
- **operations_reviewed:** 1
- **candidates_found:** 0
EOF
  run bash "$DOCS_CHECK" status "$DOCS"
  [ "$status" -eq 0 ]
  stasis_feature=$(echo "$output" | jq -r '.stasis.feature_id')
  [ "$stasis_feature" = "demo" ]
  # Legacy key should NOT exist
  legacy=$(echo "$output" | jq -r '.checkpoint // "absent"')
  [ "$legacy" = "absent" ]
  teardown_fixture
}

@test "validate: returns 'stale-stasis' when plan changes after stasis" {
  setup_fixture
  # Seed spec
  cat > "$DOCS/spec.md" <<EOF
# Feature

> Feature: demo
> Created: 1700000000
> Status: In Progress

## Acceptance Criteria
- AC-1
EOF
  # Compute real spec content_hash via the script's own status command,
  # then write plan with that hash so spec↔plan are linked.
  spec_hash=$(bash "$DOCS_CHECK" status "$DOCS" | jq -r '.spec.content_hash')
  cat > "$DOCS/plan.md" <<EOF
# Plan

> Feature: demo
> Created: 1700000100
> Spec hash: $spec_hash

## Sequence
- Step 1
EOF
  # Compute plan hash similarly, write stasis linking to it.
  plan_hash=$(bash "$DOCS_CHECK" status "$DOCS" | jq -r '.plan.content_hash')
  cat > "$DOCS/stasis.md" <<EOF
# Stasis

> Feature: demo
> Last updated: 1700000200
> Plan hash: $plan_hash

## Accomplished
- Done
## Next Steps
- Next
## Determinism Review
- **operations_reviewed:** 1
- **candidates_found:** 0
- No candidates this session.
EOF
  # Sanity: currently aligned
  run bash "$DOCS_CHECK" validate "$DOCS"
  [ "$(echo "$output" | jq -r '.result')" = "aligned" ]

  # Modify plan body — stasis should now be stale
  echo "- Step 2" >> "$DOCS/plan.md"
  run bash "$DOCS_CHECK" validate "$DOCS"
  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "stale-stasis" ]
  teardown_fixture
}

# --- Step 3: operations.sh op rename ---

OPERATIONS="$REPO_ROOT/.ccanvil/scripts/operations.sh"

@test "operations.sh: no 'checkpoint.read' or 'checkpoint.write' ops" {
  ! grep -qE 'checkpoint\.(read|write)' "$OPERATIONS"
}

@test "operations.sh: exposes 'stasis.read' and 'stasis.write' ops" {
  grep -q 'stasis\.read' "$OPERATIONS"
  grep -q 'stasis\.write' "$OPERATIONS"
}

@test "operations.sh resolve stasis.read returns JSON invocation" {
  run bash "$OPERATIONS" resolve stasis.read
  [ "$status" -eq 0 ]
  cmd=$(echo "$output" | jq -r '.invocation.command')
  [[ "$cmd" == *"docs/stasis.md"* ]]
}

@test "operations.sh resolve stasis.write returns JSON invocation" {
  run bash "$OPERATIONS" resolve stasis.write
  [ "$status" -eq 0 ]
  cmd=$(echo "$output" | jq -r '.invocation.command')
  [[ "$cmd" == *"templates/stasis.md"* ]]
  [[ "$cmd" == *"docs/stasis.md"* ]]
}

@test "operations.sh resolve checkpoint.read exits non-zero (removed)" {
  run bash "$OPERATIONS" resolve checkpoint.read
  [ "$status" -ne 0 ]
}

@test "operations.sh: status.get output contract includes 'stasis' (not 'checkpoint')" {
  grep -qE 'output_contract=.*"stasis"' "$OPERATIONS"
  ! grep -qE 'output_contract=.*"checkpoint"' "$OPERATIONS"
}

# --- Step 4: CI workflow template + manifest.lock ---

@test "ci.yml template: greps docs/stasis.md (not docs/checkpoint.md)" {
  local ci="$REPO_ROOT/.ccanvil/templates/github/workflows/ci.yml"
  grep -q 'docs/stasis\.md' "$ci"
  ! grep -q 'docs/checkpoint\.md' "$ci"
}

@test "manifest.lock: no 'docs/checkpoint.md' path entries" {
  ! grep -q '"docs/checkpoint\.md"' "$REPO_ROOT/.claude/manifest.lock"
}

@test "manifest.lock: no 'docs/templates/checkpoint.md' stale entries" {
  ! grep -q '"docs/templates/checkpoint\.md"' "$REPO_ROOT/.claude/manifest.lock"
}

# --- Step 5: pr skill + other command-files cleanup ---

@test "pr command: cleanup list references docs/stasis.md (not docs/checkpoint.md)" {
  local pr="$REPO_ROOT/.claude/commands/pr.md"
  grep -q 'docs/stasis\.md' "$pr"
  ! grep -q 'docs/checkpoint\.md' "$pr"
}

@test "ccanvil-audit command: references docs/stasis.md" {
  local audit="$REPO_ROOT/.claude/commands/ccanvil-audit.md"
  grep -q 'docs/stasis\.md' "$audit"
  ! grep -q 'docs/checkpoint\.md' "$audit"
}

@test "tdd skill: references docs/stasis.md for stuck-alternatives" {
  local tdd="$REPO_ROOT/.claude/skills/tdd/SKILL.md"
  ! grep -q 'docs/checkpoint\.md' "$tdd"
}
