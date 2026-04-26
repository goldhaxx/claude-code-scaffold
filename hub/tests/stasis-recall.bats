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

@test "docs-check.sh: no 'stale-checkpoint' state name remains (excluding scanner)" {
  # cmd_legacy_refs_scan literally contains the legacy string as a regex
  # pattern + docstring to detect it in other files — retention is deliberate.
  # Strip everything from the scanner's docblock through its closing brace.
  run bash -c "awk '/^# cmd_legacy_refs_scan/{skip=1} skip && /^}/{skip=0; next} !skip' '$DOCS_CHECK' | grep -c 'stale-checkpoint'"
  [ "$output" = "0" ]
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

# --- Step 9: /recall skill + catchup deletion ---

@test "recall skill: .claude/skills/recall/SKILL.md exists" {
  [ -f "$REPO_ROOT/.claude/skills/recall/SKILL.md" ]
}

@test "recall skill: has frontmatter name: recall" {
  grep -qE '^name:\s*recall' "$REPO_ROOT/.claude/skills/recall/SKILL.md"
}

@test "recall skill: reads docs/stasis.md (not docs/checkpoint.md)" {
  local recall="$REPO_ROOT/.claude/skills/recall/SKILL.md"
  grep -q 'docs/stasis\.md' "$recall"
  ! grep -q 'docs/checkpoint\.md' "$recall"
}

@test "recall skill: runs audit-session (ported from catchup)" {
  grep -q 'audit-session' "$REPO_ROOT/.claude/skills/recall/SKILL.md"
}

@test "recall skill: runs docs-check.sh lifecycle-state (BTS-20 migration)" {
  # BTS-20 migrated /recall from separate validate + recommend calls to a
  # single lifecycle-state envelope. Pin the post-migration shape.
  grep -q 'docs-check.sh lifecycle-state' "$REPO_ROOT/.claude/skills/recall/SKILL.md"
}

@test "legacy catchup command: .claude/commands/catchup.md is deleted" {
  [ ! -f "$REPO_ROOT/.claude/commands/catchup.md" ]
}

# --- Step 10: /stasis skill ---

@test "stasis skill: .claude/skills/stasis/SKILL.md exists" {
  [ -f "$REPO_ROOT/.claude/skills/stasis/SKILL.md" ]
}

@test "stasis skill: has frontmatter name: stasis" {
  grep -qE '^name:\s*stasis' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

@test "stasis skill: writes to docs/stasis.md (AC-3)" {
  grep -q 'docs/stasis\.md' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

@test "stasis skill: uses .ccanvil/templates/stasis.md (AC-3)" {
  grep -q '\.ccanvil/templates/stasis\.md' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

@test "stasis skill: invokes docs-check.sh lifecycle-state (BTS-20 migration of AC-4, AC-11)" {
  # BTS-20 migrated /stasis pre-flight from validate to lifecycle-state.
  grep -q 'docs-check.sh lifecycle-state' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

@test "stasis skill: invokes radar-gather, idea-count, audit-session (AC-2)" {
  local s="$REPO_ROOT/.claude/skills/stasis/SKILL.md"
  grep -q 'radar-gather' "$s"
  grep -q 'idea-count' "$s"
  grep -q 'audit-session' "$s"
}

@test "stasis skill: invokes permissions-audit.sh and context-budget.sh (AC-2)" {
  local s="$REPO_ROOT/.claude/skills/stasis/SKILL.md"
  grep -q 'permissions-audit.sh' "$s"
  grep -q 'context-budget.sh' "$s"
}

@test "stasis skill: invokes legacy-refs-scan for Cross-Session Patterns (AC-37)" {
  grep -q 'legacy-refs-scan' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

@test "BTS-115 AC-9: stasis skill dual-captures determinism candidates as Linear ideas" {
  local s="$REPO_ROOT/.claude/skills/stasis/SKILL.md"
  # Positive grep for the deterministic title prefix and the BTS-166 capture surface.
  grep -q 'Determinism:' "$s"
  grep -q 'idea.add' "$s"
  # Must reference the dedup mechanism (idea.list resolver).
  grep -q 'idea.list' "$s"
  # Must reference the pending-log fallback for capture failures.
  grep -q 'idea-pending-append' "$s"
}

@test "BTS-115 AC-10: self-review.md notes the dual-capture behavior" {
  local r="$REPO_ROOT/.claude/rules/self-review.md"
  grep -q 'Determinism:' "$r"
  grep -qi 'dual.capture\|automatically captures' "$r"
}

@test "stasis skill: reads HEAD~1:docs/stasis.md for prior-state diff (AC-5, AC-10)" {
  grep -q 'HEAD~1:docs/stasis\.md' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

@test "stasis skill: describes all three new sections" {
  local s="$REPO_ROOT/.claude/skills/stasis/SKILL.md"
  grep -q 'Cross-Session Patterns' "$s"
  grep -q 'Security Review' "$s"
  grep -q 'Memory Candidates' "$s"
}

@test "stasis skill: closes with '/compact ... wrap session' directive (AC-9)" {
  # Skill's final-close line; backticks around /compact are allowed.
  grep -qE '/compact`? to wrap session' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

@test "stasis skill: commits with ALLOW_MAIN=1 pattern (AC-8)" {
  grep -q 'ALLOW_MAIN=1' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

@test "stasis skill: halts on non-aligned validate state (AC-11)" {
  # Skill file describes stopping if validate returns stale-plan/mismatched/etc.
  grep -qE 'stale-plan|mismatched|non-aligned|not aligned' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

# --- Step 13: AC-29 comprehensive grep guard ---

@test "AC-29 grep guard: no stray checkpoint/catchup references outside allowlist" {
  local allowlist="$REPO_ROOT/hub/tests/legacy-refs-allowlist.txt"
  [ -f "$allowlist" ]

  # Collect all hits via grep -rn across shipping content.
  # Exclude .git, node_modules, dist, generated, and common binary paths.
  local hits
  hits=$(cd "$REPO_ROOT" && grep -rnE \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=dist \
    --exclude-dir=generated \
    --exclude-dir=.claude/worktrees \
    'checkpoint|catchup' \
    .claude .ccanvil hub docs README.md CLAUDE.md 2>/dev/null \
    | sed 's|^\./||' || true)

  if [[ -z "$hits" ]]; then
    return 0
  fi

  # Build combined regex from allowlist (strip comments + blanks).
  local pattern
  pattern=$(grep -vE '^\s*(#|$)' "$allowlist" | tr '\n' '|' | sed 's/|$//')

  # Lines that do NOT match any allowlist entry are failures.
  local unexpected
  unexpected=$(echo "$hits" | grep -vE "$pattern" || true)

  if [[ -n "$unexpected" ]]; then
    echo "Unexpected legacy checkpoint/catchup references:" >&2
    echo "$unexpected" >&2
    return 1
  fi
}
