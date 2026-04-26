#!/usr/bin/env bats
# BTS-175 — drift-guards: /recall and /radar SKILL.md prose must (a) handle
# the new http mechanism for backlog.list, and (b) include the explicit
# anti-pattern note that idea.list is NOT a backlog proxy.

bats_require_minimum_version 1.5.0

RECALL="$BATS_TEST_DIRNAME/../../.claude/skills/recall/SKILL.md"
RADAR="$BATS_TEST_DIRNAME/../../.claude/skills/radar/SKILL.md"

# =========================================================================
# AC-6: /recall step 0c handles http mechanism
# =========================================================================

@test "AC-6: /recall SKILL.md mentions http mechanism for backlog.list" {
  # Accepts either descriptive prose ("mechanism is http") or a case-branch
  # pattern ("http) ..."). Drift-guard intent is presence of http handling.
  grep -qE "mechanism is .http|mechanism is http|http\)|\"http\"|'http'" "$RECALL"
}

@test "AC-6: /recall SKILL.md mentions 'eval' for executing http command" {
  grep -q "eval" "$RECALL"
}

# =========================================================================
# AC-7: /recall has explicit anti-pattern note
# =========================================================================

@test "AC-7: /recall SKILL.md contains anti-pattern note about idea.list" {
  # The note must reference both idea.list and the anti-pattern intent.
  set -e
  grep -q "idea\.list" "$RECALL"
  # Look for words that signal "do not use" or "not for backlog" — accept
  # multiple phrasings.
  grep -qE "[Dd]o NOT|don't use|never use|anti-pattern|filtered" "$RECALL"
}

# =========================================================================
# AC-8: /radar mirrors AC-7 anti-pattern note
# =========================================================================

@test "AC-8: /radar SKILL.md contains anti-pattern note about idea.list" {
  set -e
  grep -q "idea\.list" "$RADAR"
  grep -qE "[Dd]o NOT|don't use|never use|anti-pattern|filtered" "$RADAR"
}

@test "AC-8: /radar SKILL.md still references backlog.list as canonical" {
  grep -q "backlog\.list" "$RADAR"
}

# =========================================================================
# Hub-managed area: notes must be above NODE-SPECIFIC-START
# =========================================================================

@test "AC-7+8: anti-pattern notes live in hub-managed area (above NODE-SPECIFIC-START)" {
  set -e
  # /recall
  recall_idea_line=$(grep -n "idea\.list" "$RECALL" | head -1 | cut -d: -f1)
  recall_marker=$(grep -n "NODE-SPECIFIC-START" "$RECALL" | head -1 | cut -d: -f1)
  [ -n "$recall_idea_line" ] && [ -n "$recall_marker" ] && [ "$recall_idea_line" -lt "$recall_marker" ]
  # /radar
  radar_idea_line=$(grep -n "idea\.list" "$RADAR" | head -1 | cut -d: -f1)
  radar_marker=$(grep -n "NODE-SPECIFIC-START" "$RADAR" | head -1 | cut -d: -f1)
  [ -n "$radar_idea_line" ] && [ -n "$radar_marker" ] && [ "$radar_idea_line" -lt "$radar_marker" ]
}
