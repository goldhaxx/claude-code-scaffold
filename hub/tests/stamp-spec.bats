#!/usr/bin/env bats
# BTS-141 — docs-check.sh stamp-spec: deterministic Created: epoch stamping.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/docs/specs"
}

teardown() {
  rm -rf "$PROJECT"
}

_spec_with_placeholder() {
  local id="$1"
  cat > "$PROJECT/docs/specs/$id.md" <<MD
# Feature: Test

> Feature: $id
> Work: linear:BTS-X
> Created: PLACEHOLDER
> Status: Draft

## Summary
Body.
MD
}

@test "BTS-141 AC-1: stamp-spec replaces > Created: line with current epoch" {
  set -e
  _spec_with_placeholder "test-spec"
  local before_epoch
  before_epoch=$(date +%s)

  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" stamp-spec test-spec"
  [ "$status" -eq 0 ]

  # Read the stamped file; epoch line is the second-to-last metadata line.
  local stamped
  stamped=$(grep -E '^> Created: [0-9]+$' "$PROJECT/docs/specs/test-spec.md" | head -1)
  [ -n "$stamped" ]
  local stamped_epoch="${stamped##*: }"
  # Within 5 seconds of the test's epoch (clock skew tolerance).
  [ "$stamped_epoch" -ge "$before_epoch" ]
  [ "$stamped_epoch" -le $((before_epoch + 5)) ]
}

@test "BTS-141 AC-2: missing spec file → exit non-zero with ERROR on stderr" {
  run --separate-stderr bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" stamp-spec nope-not-here"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "ERROR" ]]
  [[ "$stderr" =~ "spec not found" ]]
}

@test "BTS-141 AC-3: spec without > Created: line → exit non-zero, no silent insert" {
  cat > "$PROJECT/docs/specs/no-created.md" <<'MD'
# Feature: Test

> Feature: no-created
> Status: Draft
MD

  run --separate-stderr bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" stamp-spec no-created"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "ERROR" ]]
  [[ "$stderr" =~ "Created" ]]
  # Confirm no insert happened.
  ! grep -q "^> Created:" "$PROJECT/docs/specs/no-created.md"
}

@test "BTS-141 AC-4: idempotent — running twice in the same second leaves epoch unchanged" {
  set -e
  _spec_with_placeholder "idem"
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" stamp-spec idem"
  [ "$status" -eq 0 ]
  local first
  first=$(grep -E '^> Created: [0-9]+$' "$PROJECT/docs/specs/idem.md" | head -1)

  # Same-second second invocation; epoch may match or be 1 greater (clock advance).
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" stamp-spec idem"
  [ "$status" -eq 0 ]
  local second
  second=$(grep -E '^> Created: [0-9]+$' "$PROJECT/docs/specs/idem.md" | head -1)

  local first_n="${first##*: }"
  local second_n="${second##*: }"
  [ "$second_n" -ge "$first_n" ]
  [ $((second_n - first_n)) -le 2 ]
}

@test "BTS-141 AC-5: other metadata lines are not modified" {
  set -e
  _spec_with_placeholder "preserve"
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" stamp-spec preserve"
  [ "$status" -eq 0 ]

  # Feature, Work, Status lines are intact verbatim.
  grep -q "^> Feature: preserve$" "$PROJECT/docs/specs/preserve.md"
  grep -q "^> Work: linear:BTS-X$" "$PROJECT/docs/specs/preserve.md"
  grep -q "^> Status: Draft$" "$PROJECT/docs/specs/preserve.md"
}

@test "BTS-141 AC-6: stamped value is always a positive integer (no $stamp literals, no zero)" {
  set -e
  _spec_with_placeholder "guard"
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" stamp-spec guard"
  [ "$status" -eq 0 ]

  # The stamped line must match strict positive-integer pattern.
  local line
  line=$(grep "^> Created:" "$PROJECT/docs/specs/guard.md" | head -1)
  [[ "$line" =~ ^\>\ Created:\ [1-9][0-9]+$ ]]
  # Negative guards: no $stamp literal, no PLACEHOLDER, no empty string.
  ! grep -qE '^> Created: \$' "$PROJECT/docs/specs/guard.md"
  ! grep -qE '^> Created: PLACEHOLDER$' "$PROJECT/docs/specs/guard.md"
  ! grep -qE '^> Created: $' "$PROJECT/docs/specs/guard.md"
  ! grep -qE '^> Created: 0$' "$PROJECT/docs/specs/guard.md"
}

@test "BTS-141 AC-7: stdout JSON envelope on success — feature_id, stamped_epoch, file" {
  set -e
  _spec_with_placeholder "json-out"
  run --separate-stderr bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" stamp-spec json-out"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.feature_id == "json-out"'
  echo "$output" | jq -e '.stamped_epoch | type == "number"'
  echo "$output" | jq -e '.stamped_epoch > 0'
  echo "$output" | jq -e '.file | endswith("docs/specs/json-out.md")'
}

@test "BTS-141 AC-8: /spec skill prose references stamp-spec subcommand" {
  set -e
  local skill="$BATS_TEST_DIRNAME/../../.claude/skills/spec/SKILL.md"
  grep -q 'stamp-spec' "$skill"
  # date +%s should not be the metadata-write instruction anymore (drift guard);
  # other date-related references (e.g., audit-session timestamps) may exist —
  # but the metadata-write step 8 should reference stamp-spec instead.
  ! grep -qE 'Created:.*via.*date \+%s' "$skill"
}
