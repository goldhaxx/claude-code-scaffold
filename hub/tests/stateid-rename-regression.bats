#!/usr/bin/env bats
# BTS-139 — regression guard: operations.sh resolver outputs must NEVER
# contain the key `stateId`. Linear MCP's save_issue / list_issues tools
# accept `state` ("type, name, or ID"). Passing `stateId` is silently
# ignored and captures fall through to the team's default state (Backlog).
#
# This file exists to prevent re-introduction of `stateId` — even a
# partial rename that only covers operations.sh but leaves one jq
# emission intact will be caught here.

bats_require_minimum_version 1.5.0

OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude"
  # Seed a Linear-provider node config matching ccanvil's own setup.
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {
      "linear": {
        "mechanism": "mcp",
        "idea_label": "idea"
      }
    }
  }
}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{
  "integrations": {
    "routing": { "idea": "linear" },
    "providers": {
      "linear": {
        "project": "ccanvil",
        "team": "Blocktech Solutions",
        "state_ids": {
          "triage":    "11111111-1111-1111-1111-111111111111",
          "backlog":   "22222222-2222-2222-2222-222222222222",
          "icebox":    "33333333-3333-3333-3333-333333333333",
          "canceled":  "44444444-4444-4444-4444-444444444444",
          "duplicate": "55555555-5555-5555-5555-555555555555",
          "done":      "66666666-6666-6666-6666-666666666666"
        }
      }
    }
  }
}
JSON
}

teardown() {
  rm -rf "$PROJECT"
}

# ---------------------------------------------------------------------------
# AC-1: idea.add resolution uses `state` (not `stateId`)
# ---------------------------------------------------------------------------

@test "BTS-139 AC-1: idea.add resolve emits params.state, never params.stateId" {
  set -e
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "11111111-1111-1111-1111-111111111111"'
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

# ---------------------------------------------------------------------------
# AC-2: ticket.transition for every role uses `state` (not `stateId`)
# ---------------------------------------------------------------------------

@test "BTS-139 AC-2: ticket.transition BTS-X triage emits params.state" {
  set -e
  run bash "$OPS" resolve ticket.transition BTS-X triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "11111111-1111-1111-1111-111111111111"'
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

@test "BTS-139 AC-2: ticket.transition BTS-X backlog emits params.state" {
  set -e
  run bash "$OPS" resolve ticket.transition BTS-X backlog --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "22222222-2222-2222-2222-222222222222"'
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

@test "BTS-139 AC-2: ticket.transition BTS-X icebox emits params.state" {
  set -e
  run bash "$OPS" resolve ticket.transition BTS-X icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "33333333-3333-3333-3333-333333333333"'
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

@test "BTS-139 AC-2: ticket.transition BTS-X canceled emits params.state" {
  set -e
  run bash "$OPS" resolve ticket.transition BTS-X canceled --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "44444444-4444-4444-4444-444444444444"'
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

@test "BTS-139 AC-2: ticket.transition BTS-X duplicate emits params.state" {
  set -e
  run bash "$OPS" resolve ticket.transition BTS-X duplicate --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "55555555-5555-5555-5555-555555555555"'
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

@test "BTS-139 AC-2: ticket.transition BTS-X done emits params.state" {
  set -e
  run bash "$OPS" resolve ticket.transition BTS-X done --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "66666666-6666-6666-6666-666666666666"'
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

# ---------------------------------------------------------------------------
# AC-3: idea.triage mutations use `state` (not `stateId`)
# ---------------------------------------------------------------------------

@test "BTS-139 AC-3: idea.triage resolve emits no stateId key in params" {
  set -e
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # idea.triage resolves to a list_issues for Triage state — uses state (for
  # filtering), not stateId.
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

# ---------------------------------------------------------------------------
# AC-4: idea.review-icebox uses `state` (not `stateId`)
# ---------------------------------------------------------------------------

@test "BTS-139 AC-4: idea.review-icebox resolve emits no stateId key in params" {
  set -e
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

# ---------------------------------------------------------------------------
# AC-5: unconfigured state → params.state absent (not empty string)
# ---------------------------------------------------------------------------

@test "BTS-139 AC-5: unconfigured state_ids → params.state key absent (neither state nor stateId)" {
  set -e
  # Rebuild config WITHOUT state_ids at all.
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{
  "integrations": {
    "routing": { "idea": "linear" },
    "providers": {
      "linear": {
        "project": "ccanvil",
        "team": "Blocktech Solutions"
      }
    }
  }
}
JSON
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # Neither state nor stateId should appear when no state_ids is configured.
  echo "$output" | jq -e '.invocation.params | has("state") | not'
  echo "$output" | jq -e '.invocation.params | has("stateId") | not'
}

# ---------------------------------------------------------------------------
# Meta: operations.sh source has no literal `"stateId":` jq emission
# ---------------------------------------------------------------------------

@test "BTS-139 source-level guard: operations.sh has no '\"stateId\":' literal emission" {
  # This catches regression even if the tests above are somehow bypassed —
  # looks for the literal jq emission string in the source.
  ! grep -qE '"stateId"[[:space:]]*:' "$OPS"
}
