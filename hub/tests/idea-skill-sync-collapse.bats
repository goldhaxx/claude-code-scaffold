#!/usr/bin/env bats
# BTS-179 — drift-guard: /idea sync skill section collapses to single
# resolve+eval form, no per-op `case "$op" in` block.

bats_require_minimum_version 1.5.0

SKILL="$BATS_TEST_DIRNAME/../../.claude/skills/idea/SKILL.md"

# Extract the `## Sync: /idea sync` section (everything between that heading
# and the next `## ` heading).
_sync_section() {
  awk '/^## Sync:/{flag=1; next} /^## /{flag=0} flag' "$SKILL"
}

# =========================================================================
# AC-9 / AC-10: skill section is single resolve+eval, no per-op case block
# =========================================================================

@test "AC-9: /idea sync section contains the resolve+eval one-liner pattern" {
  set -e
  local section
  section=$(_sync_section)
  # The collapsed form: resolves idea.sync via operations.sh, then eval's
  # the resolved command.
  printf '%s' "$section" | grep -q 'operations.sh resolve idea.sync'
  printf '%s' "$section" | grep -F -q 'eval "$(echo "$RESOLUTION" | jq -r'
}

@test "AC-9: /idea sync section references idea-pending-replay as the substrate" {
  set -e
  local section
  section=$(_sync_section)
  printf '%s' "$section" | grep -q 'idea-pending-replay'
}

@test "AC-10: /idea sync section does NOT contain a per-op shell case block" {
  set -e
  local section
  section=$(_sync_section)
  # Negative grep: a literal `case "$op"` or `case $op` would indicate the
  # old per-op dispatch loop is still in skill prose.
  ! printf '%s' "$section" | grep -qE 'case[[:space:]]+"?\$op'
}

@test "AC-10: /idea sync section does NOT include per-entry idea-pending-append fallbacks" {
  set -e
  # The old prose had a long block of `idea-pending-append --op promote ...`
  # examples. With substrate dispatch, these don't belong in the skill any
  # more — replay handles ack/preserve internally.
  local section
  section=$(_sync_section)
  ! printf '%s' "$section" | grep -q 'idea-pending-append --op promote'
  ! printf '%s' "$section" | grep -q 'idea-pending-append --op defer'
}
