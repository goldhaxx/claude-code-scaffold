#!/usr/bin/env bats
# BTS-176: drift-guard — `/idea` skill prose must use `jq -Rr @sh` (raw
# output) for shell-quoting priority/duplicate-of values, not `jq -R @sh`
# which leaves the result JSON-wrapped and fails the eval round-trip
# into `linear-query.sh save-issue --priority "'3'"`.
#
# Mirrors the BTS-125 / BTS-171 drift-guard pattern: pure prose
# assertions against the skill file, no fixture setup.

bats_require_minimum_version 1.5.0

SKILL="$BATS_TEST_DIRNAME/../../.claude/skills/idea/SKILL.md"

@test "AC-3: SKILL.md does NOT contain the buggy 'jq -R @sh' pattern" {
  # The bare `-R` (raw input) without `-r` (raw output) wraps the result
  # in JSON quotes, so `printf '%s' "3" | jq -R @sh` returns "'3'" rather
  # than '3' — eval'd into save-issue's --argjson, this is invalid JSON.
  ! grep -q 'jq -R @sh' "$SKILL"
}

@test "AC-4: SKILL.md contains 'jq -Rr @sh' at least 3 times" {
  # Three expected sites: --parent-id (BTS-162), --priority (this ship),
  # --duplicate-of (this ship). The sync section's --parent-id @sh quoting
  # is also -Rr; so a clean fix reaches ≥ 4. Lower bound 3 covers the
  # BTS-176 patched form.
  count=$(grep -c 'jq -Rr @sh' "$SKILL")
  [ "$count" -ge 3 ]
}
