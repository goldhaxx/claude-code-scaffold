#!/usr/bin/env bats
# BTS-205: dual-capture resilience.
# - cmd_idea_pending_append now writes to .ccanvil/dual-capture-emergency.log
#   when its primary log write fails (perms, exotic FS issue).
# - The /stasis BTS-115 dual-capture skill prose now dispatches via
#   mechanism-aware case (bash vs http), removing the local-routed silent skip.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"
STASIS_SKILL="$REPO_ROOT/.claude/skills/stasis/SKILL.md"

setup() {
  TMPDIR_BATS=$(mktemp -d)
  PROJECT_DIR="$TMPDIR_BATS/project"
  mkdir -p "$PROJECT_DIR/.ccanvil"
}

teardown() {
  # Restore writability before cleanup
  chmod -R u+w "$TMPDIR_BATS" 2>/dev/null || true
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

# =========================================================================
# AC-4: emergency dead-letter when primary log unwritable
# =========================================================================

@test "AC-4: primary unwritable → emergency log written + WARN to stderr" {
  # Create primary log as a directory (mkdir -p .ccanvil already; now make
  # the file path point at a directory so >> fails predictably).
  mkdir -p "$PROJECT_DIR/.ccanvil/ideas-pending.log"  # path is a dir, append fails

  run bash "$SCRIPT" idea-pending-append \
    --op add --title "Test emergency" --body "body content" \
    --project-dir "$PROJECT_DIR"

  [ "$status" -eq 0 ]  # function returned 0 — emergency path absorbed the failure
  echo "$output" | grep -q "WARN: idea-pending-append: primary log write failed"
  echo "$output" | grep -q "emergency log"

  # Verify the emergency log was written and contains the entry
  [ -f "$PROJECT_DIR/.ccanvil/dual-capture-emergency.log" ]
  grep -q '"title":"Test emergency"' "$PROJECT_DIR/.ccanvil/dual-capture-emergency.log"
}

# =========================================================================
# AC-5: total failure when both primary AND emergency unwritable
# =========================================================================

@test "AC-5: both primary and emergency unwritable → exit 1 with ERROR" {
  # Make both potential write targets unwritable: primary log is a dir,
  # AND .ccanvil itself is read-only so emergency log can't be created.
  mkdir -p "$PROJECT_DIR/.ccanvil/ideas-pending.log"
  mkdir -p "$PROJECT_DIR/.ccanvil/dual-capture-emergency.log"  # also a dir

  run bash "$SCRIPT" idea-pending-append \
    --op add --title "Test total failure" --body "body" \
    --project-dir "$PROJECT_DIR"

  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ERROR: idea-pending-append: both primary and emergency log writes failed"
}

# =========================================================================
# AC-6: skill prose carries BTS-205 reference + mechanism-aware dispatch
# =========================================================================

@test "AC-6 lock: stasis SKILL.md references BTS-205" {
  grep -q "BTS-205" "$STASIS_SKILL"
}

@test "AC-6 lock: stasis SKILL.md uses mechanism-aware case dispatch (bash + http)" {
  # The new BTS-115 block dispatches by mechanism rather than skipping
  # local-routed nodes. This locks the structural change.
  grep -q 'case "$mechanism" in' "$STASIS_SKILL"
  grep -q 'http)' "$STASIS_SKILL"
  ! grep -q '\[\[ "$provider" != "linear" \]\] && continue' "$STASIS_SKILL"
}

# =========================================================================
# Drift-guard: BTS-205 reference present in docs-check.sh
# =========================================================================

@test "drift: BTS-205 referenced inline in docs-check.sh" {
  grep -q "BTS-205" "$SCRIPT"
}

# =========================================================================
# Regression: success path unchanged when primary writable
# =========================================================================

@test "regression: success path unchanged — entry written to primary log" {
  run bash "$SCRIPT" idea-pending-append \
    --op add --title "Normal capture" --body "body" \
    --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/.ccanvil/ideas-pending.log" ]
  grep -q '"title":"Normal capture"' "$PROJECT_DIR/.ccanvil/ideas-pending.log"
  # Emergency log should NOT exist
  [ ! -f "$PROJECT_DIR/.ccanvil/dual-capture-emergency.log" ]
}
