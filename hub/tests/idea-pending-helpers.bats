#!/usr/bin/env bats
# BTS-123 — idea-pending-append + idea-pending-validate primitives.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.ccanvil"
}

teardown() {
  rm -rf "$PROJECT"
}

_run_in_project() {
  bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" $*"
}

@test "BTS-123 AC-1: idea-pending-append --op add writes one compact JSONL line; body with newlines stays single line" {
  set -e
  local body=$'first line\nsecond line\nthird line'
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op add --title \"Test\" --body \"$body\""
  [ "$status" -eq 0 ]
  # File has exactly 1 line (literal newlines were escaped).
  [ "$(wc -l < "$PROJECT/.ccanvil/ideas-pending.log" | tr -d ' ')" = "1" ]
  # Parses cleanly as JSON.
  jq -e '.op == "add"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.title == "Test"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.body | contains("first line")' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.body | contains("third line")' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.ts | type == "number"' < "$PROJECT/.ccanvil/ideas-pending.log"
}

@test "BTS-123 AC-2: append with quotes/backslashes/backticks/emoji round-trips losslessly" {
  set -e
  local body='"quoted" \backslash `backtick` $dollar 🚀 emoji'
  # Pass --project-dir directly (avoid bash -c which re-evaluates backticks/$).
  run bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op add --title T --body "$body"
  [ "$status" -eq 0 ]
  # Recover original body verbatim
  local got
  got=$(jq -r '.args.body' < "$PROJECT/.ccanvil/ideas-pending.log")
  [ "$got" = "$body" ]
}

@test "BTS-123 AC-3: --op promote --id BTS-X --priority 3 writes correct shape" {
  set -e
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op promote --id BTS-X --priority 3"
  [ "$status" -eq 0 ]
  jq -e '.op == "promote"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.id == "BTS-X"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.priority == 3' < "$PROJECT/.ccanvil/ideas-pending.log"
}

@test "BTS-123 AC-4: --op defer --id BTS-Y writes {op, args:{id}, ts}" {
  set -e
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op defer --id BTS-Y"
  [ "$status" -eq 0 ]
  jq -e '.op == "defer"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.id == "BTS-Y"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args | keys == ["id"]' < "$PROJECT/.ccanvil/ideas-pending.log"
}

@test "BTS-123 AC-4: --op dismiss --id BTS-Z writes correct shape" {
  set -e
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op dismiss --id BTS-Z"
  [ "$status" -eq 0 ]
  jq -e '.op == "dismiss"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.id == "BTS-Z"' < "$PROJECT/.ccanvil/ideas-pending.log"
}

@test "BTS-123 AC-5: --op merge --id BTS-A --duplicate-of BTS-B writes {duplicateOf}" {
  set -e
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op merge --id BTS-A --duplicate-of BTS-B"
  [ "$status" -eq 0 ]
  jq -e '.op == "merge"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.id == "BTS-A"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.duplicateOf == "BTS-B"' < "$PROJECT/.ccanvil/ideas-pending.log"
}

@test "BTS-123 AC-6: --op ticket.transition --id BTS-X --role todo writes correct shape" {
  set -e
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op ticket.transition --id BTS-X --role todo"
  [ "$status" -eq 0 ]
  jq -e '.op == "ticket.transition"' < "$PROJECT/.ccanvil/ideas-pending.log"
  jq -e '.args.id == "BTS-X" and .args.role == "todo"' < "$PROJECT/.ccanvil/ideas-pending.log"
}

@test "BTS-123 AC-7: idea-pending-validate emits {count, valid, errors} on a valid log" {
  set -e
  bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op add --title T1 --body B1"
  bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op add --title T2 --body B2"
  bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op promote --id BTS-X --priority 3"

  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-validate"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count == 3'
  echo "$output" | jq -e '.valid == true'
  echo "$output" | jq -e '.errors == []'
}

@test "BTS-123 AC-7/AC-8: validate detects malformed lines and returns valid=false" {
  set -e
  # First entry is valid; second is broken (truncated JSON).
  bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-append --op add --title T --body B"
  printf 'this is not json\n' >> "$PROJECT/.ccanvil/ideas-pending.log"

  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-validate"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.valid == false'
  echo "$output" | jq -e '.errors | length >= 1'
}

@test "BTS-123 AC-9: missing pending log → validate reports {count: 0, valid: true, errors: []} and exits 0" {
  set -e
  # No log file created.
  run bash -c "cd \"$PROJECT\" && bash \"$SCRIPT\" idea-pending-validate"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count == 0 and .valid == true and (.errors | length == 0)'
}

@test "BTS-123 AC-10: /idea skill prose references idea-pending-append (drift guard)" {
  set -e
  local skill="$BATS_TEST_DIRNAME/../../.claude/skills/idea/SKILL.md"
  grep -q 'idea-pending-append' "$skill"
  # Legacy unsafe pattern should be gone — no inline echo with single-quoted JSON literal
  ! grep -qE "^[[:space:]]*echo '\\{\"op\":" "$skill"
}
