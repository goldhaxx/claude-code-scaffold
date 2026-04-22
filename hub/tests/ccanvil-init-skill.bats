#!/usr/bin/env bets
# Grep-assertion tests for global-commands/ccanvil-init.md.
#
# The skill is Claude-executed documentation, not a runnable script — so
# we verify its correctness by asserting it documents each mode-aware
# branch the spec requires. Each test maps to one or more AC in
# docs/specs/init-mature-project.md.

SKILL_FILE="$BATS_TEST_DIRNAME/../../global-commands/ccanvil-init.md"

@test "skill file exists" {
  [ -f "$SKILL_FILE" ]
}

# =========================================================================
# AC-23: skill references project_mode, retrofit-check, create-delimiters
# =========================================================================

@test "AC-23: skill references project_mode" {
  grep -q 'project_mode' "$SKILL_FILE"
}

@test "AC-23: skill references retrofit-check" {
  grep -q 'retrofit-check' "$SKILL_FILE"
}

@test "AC-23: skill references section-merge-create-delimiters" {
  grep -q 'section-merge-create-delimiters' "$SKILL_FILE"
}

# =========================================================================
# AC-8: mode-aware git lifecycle — conditional git init, distinct messages
# =========================================================================

@test "AC-8: skill branches git init on project mode" {
  grep -qE 'mature-repo|partial-ccanvil' "$SKILL_FILE"
  # Retrofit commit message (distinct from fresh-init message)
  grep -q 'retrofit' "$SKILL_FILE"
}

@test "AC-8: skill still documents fresh-init commit message" {
  grep -qE 'chore: initialize project with ccanvil preset' "$SKILL_FILE"
}

# =========================================================================
# AC-9: pre-push hook conditional install
# =========================================================================

@test "AC-9: skill conditions pre-push hook install on prior existence" {
  grep -q 'pre-push' "$SKILL_FILE"
  # Preservation language
  grep -qE 'existing.*pre-push|pre-push.*exists|preserve' "$SKILL_FILE"
}

# =========================================================================
# AC-10: skip-if-exists for lifecycle docs
# =========================================================================

@test "AC-10: skill declares skip-if-exists for docs/*.md" {
  grep -q 'PRESERVED:' "$SKILL_FILE"
}

@test "AC-10: skill names the four lifecycle docs by path" {
  grep -q 'docs/spec.md' "$SKILL_FILE"
  grep -q 'docs/plan.md' "$SKILL_FILE"
  grep -q 'docs/stasis.md' "$SKILL_FILE"
  grep -q 'docs/roadmap.md' "$SKILL_FILE"
}

# =========================================================================
# AC-11: in-progress feature detection from docs/stasis.md header
# =========================================================================

@test "AC-11: skill surfaces in-progress feature when stasis is preserved" {
  grep -qE 'in-progress feature|> Feature:' "$SKILL_FILE"
}

# =========================================================================
# AC-12, AC-13: already-initialized idempotency path
# =========================================================================

@test "AC-12: skill offers Update / Re-register / Abort for already-initialized" {
  grep -q 'already-initialized' "$SKILL_FILE"
  grep -qE '\bUpdate\b' "$SKILL_FILE"
  grep -qE '\bRe-register\b' "$SKILL_FILE"
  grep -qE '\bAbort\b' "$SKILL_FILE"
}

@test "AC-13: skill's already-initialized path does not run git init" {
  # Some nearby line must state that this path doesn't re-init git.
  grep -qE 'already-initialized.*(no|skip|does not|DO NOT).*git init' "$SKILL_FILE" \
    || grep -qE '(no|skip|DO NOT).*git init.*already-initialized' "$SKILL_FILE"
}

# =========================================================================
# stasis-recall drive-by cleanup (surfaced by legacy-refs-scan)
# =========================================================================

@test "drive-by: skill refers to docs/stasis.md, not docs/checkpoint.md" {
  grep -q 'docs/stasis.md' "$SKILL_FILE"
  ! grep -q 'docs/checkpoint.md' "$SKILL_FILE"
}
