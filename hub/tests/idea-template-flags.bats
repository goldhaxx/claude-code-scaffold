#!/usr/bin/env bats
# BTS-172: docs-check.sh idea-template-body — composes templated idea
# bodies from explicit flags. Sister of BTS-162 Part 1's --parent.

bats_require_minimum_version 1.5.0

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"
SKILL_FILE="$BATS_TEST_DIRNAME/../../.claude/skills/idea/SKILL.md"

setup() {
  NODE=$(mktemp -d)
}

teardown() {
  rm -rf "$NODE"
}

# =========================================================================
# AC-1: all three flags compose in fixed order, body verbatim at end
# =========================================================================

@test "AC-1: all flags set → captured-during + surfaced-at + Family + body, in order" {
  set -e
  run bash "$DC" idea-template-body \
    --body "the body" \
    --source-skill stasis \
    --context "row 6 of 16" \
    --family "BTS-150,BTS-169,BTS-171" \
    "$NODE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Captured during /stasis walk-through."
  echo "$output" | grep -q "Surfaced at row 6 of 16."
  echo "$output" | grep -q "## Family"
  echo "$output" | grep -q "^- BTS-150$"
  echo "$output" | grep -q "^- BTS-169$"
  echo "$output" | grep -q "^- BTS-171$"
  echo "$output" | grep -q "the body"
  # Order check: captured-during line precedes Surfaced-at, which precedes Family
  cap_line=$(echo "$output" | grep -n "Captured during" | head -1 | cut -d: -f1)
  surf_line=$(echo "$output" | grep -n "Surfaced at" | head -1 | cut -d: -f1)
  family_line=$(echo "$output" | grep -n "## Family" | head -1 | cut -d: -f1)
  body_line=$(echo "$output" | grep -n "the body" | head -1 | cut -d: -f1)
  [ "$cap_line" -lt "$surf_line" ]
  [ "$surf_line" -lt "$family_line" ]
  [ "$family_line" -lt "$body_line" ]
}

# =========================================================================
# AC-2: no-flag passthrough
# =========================================================================

@test "AC-2: no flags → body emitted verbatim, no prepended sections" {
  set -e
  run bash "$DC" idea-template-body --body "just the body" "$NODE"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Captured during"
  ! echo "$output" | grep -q "Surfaced at"
  ! echo "$output" | grep -q "## Family"
  echo "$output" | grep -q "just the body"
}

# =========================================================================
# AC-3: composability — only --family present
# =========================================================================

@test "AC-3: only --family → only Family section prepended" {
  set -e
  run bash "$DC" idea-template-body \
    --body "body text" \
    --family "BTS-A,BTS-B" \
    "$NODE"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "Captured during"
  ! echo "$output" | grep -q "Surfaced at"
  echo "$output" | grep -q "## Family"
  echo "$output" | grep -q "^- BTS-A$"
  echo "$output" | grep -q "^- BTS-B$"
  echo "$output" | grep -q "body text"
}

# =========================================================================
# AC-4: composability — only --source-skill present
# =========================================================================

@test "AC-4: only --source-skill → only Captured-during line prepended" {
  set -e
  run bash "$DC" idea-template-body \
    --body "body text" \
    --source-skill radar \
    "$NODE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Captured during /radar walk-through."
  ! echo "$output" | grep -q "Surfaced at"
  ! echo "$output" | grep -q "## Family"
  echo "$output" | grep -q "body text"
}

# =========================================================================
# AC-5: validation — --family empty / whitespace-only
# =========================================================================

@test "AC-5: --family '' rejected" {
  run bash "$DC" idea-template-body --body "x" --family "" "$NODE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--family requires a non-empty"* ]]
}

@test "AC-5: --family ' , ' (whitespace+comma only) rejected" {
  run bash "$DC" idea-template-body --body "x" --family " , " "$NODE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--family"* ]]
}

# =========================================================================
# AC-6: validation — --source-skill / --context empty
# =========================================================================

@test "AC-6: --source-skill '' rejected" {
  run bash "$DC" idea-template-body --body "x" --source-skill "" "$NODE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--source-skill requires a non-empty value"* ]]
}

@test "AC-6: --context '' rejected" {
  run bash "$DC" idea-template-body --body "x" --context "" "$NODE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--context requires a non-empty value"* ]]
}

# =========================================================================
# AC-7: skill-prose drift-guards
# =========================================================================

@test "AC-7: SKILL.md documents --context flag" {
  grep -q -- "--context" "$SKILL_FILE"
}

@test "AC-7: SKILL.md documents --family flag" {
  grep -q -- "--family" "$SKILL_FILE"
}

@test "AC-7: SKILL.md documents --source-skill flag" {
  grep -q -- "--source-skill" "$SKILL_FILE"
}

# =========================================================================
# AC-8: dispatch registration drift-guard
# =========================================================================

@test "AC-8: docs-check.sh dispatch registers idea-template-body" {
  grep -q "idea-template-body)" "$DC"
}

# =========================================================================
# Family parsing edge cases
# =========================================================================

@test "Family parsing: comma-and-whitespace separated values produce trimmed bullets" {
  set -e
  run bash "$DC" idea-template-body \
    --body "x" \
    --family "BTS-150,  BTS-169  ,BTS-171" \
    "$NODE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^- BTS-150$"
  echo "$output" | grep -q "^- BTS-169$"
  echo "$output" | grep -q "^- BTS-171$"
}

@test "Family parsing: single ref with no comma produces one bullet" {
  set -e
  run bash "$DC" idea-template-body \
    --body "x" \
    --family "BTS-200" \
    "$NODE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^- BTS-200$"
  # No second bullet
  bullet_count=$(echo "$output" | grep -c "^- BTS-")
  [ "$bullet_count" -eq 1 ]
}
