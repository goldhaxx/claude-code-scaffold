#!/usr/bin/env bats
# BTS-171: drift-guard — verify the live-API validation rule is encoded in
# .claude/rules/tdd.md and references at least one prior-incident anchor.
# Prevents silent removal of the rule by future hub edits or merge conflicts.

bats_require_minimum_version 1.5.0

TDD_RULE="$BATS_TEST_DIRNAME/../../.claude/rules/tdd.md"
PLAN_SKILL="$BATS_TEST_DIRNAME/../../.claude/commands/plan.md"
SELF_REVIEW_RULE="$BATS_TEST_DIRNAME/../../.claude/rules/self-review.md"

@test "tdd.md contains the live-API validation gate rule" {
  grep -qi "live-API" "$TDD_RULE"
}

@test "tdd.md references at least one prior-incident anchor (BTS-115 or BTS-170)" {
  grep -qE 'BTS-115|BTS-170' "$TDD_RULE"
}

@test "tdd.md's live-API rule is in the hub-managed section (above NODE-SPECIFIC-START)" {
  # The rule must live above the node-specific marker so downstream
  # ccanvil-sync.sh pull picks it up without operator action.
  rule_line=$(grep -n -i "live-API" "$TDD_RULE" | head -1 | cut -d: -f1)
  marker_line=$(grep -n "NODE-SPECIFIC-START" "$TDD_RULE" | head -1 | cut -d: -f1)
  [ -n "$rule_line" ]
  [ -n "$marker_line" ]
  [ "$rule_line" -lt "$marker_line" ]
}

@test "plan.md skill prose mentions live-API contract uncertainty" {
  # The /plan skill must instruct implementers to add an explicit
  # validation gate when plan steps flag live-API contract risks.
  grep -qi "live[ -]API" "$PLAN_SKILL"
}

@test "self-review.md flag-list mentions live-API validation gap" {
  grep -qi "live[ -]API" "$SELF_REVIEW_RULE"
}
