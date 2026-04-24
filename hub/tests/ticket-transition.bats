#!/usr/bin/env bats
# Tests for ticket.transition — provider-neutral role-based Linear state transitions.
# BTS-128 (ticket-transition) — 6 phases, 12 TDD steps.

OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.ccanvil" "$PROJECT/.claude"
}

teardown() {
  rm -rf "$PROJECT"
}

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

_linear_config_with_state_ids() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {
      "linear": {
        "mechanism": "mcp",
        "project": "Test Project",
        "team": "Test Team",
        "workspace": "testws",
        "state_ids": {
          "triage":    "fixture-triage-uuid",
          "backlog":   "fixture-backlog-uuid",
          "icebox":    "fixture-icebox-uuid",
          "canceled":  "fixture-canceled-uuid",
          "duplicate": "fixture-duplicate-uuid",
          "done":      "fixture-done-uuid"
        }
      }
    },
    "routing": { "idea": "linear" }
  }
}
JSON
}

_linear_config_missing_done() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {
      "linear": {
        "mechanism": "mcp",
        "project": "Test Project",
        "team": "Test Team",
        "workspace": "testws",
        "state_ids": {
          "triage":    "fixture-triage-uuid",
          "backlog":   "fixture-backlog-uuid",
          "icebox":    "fixture-icebox-uuid",
          "canceled":  "fixture-canceled-uuid",
          "duplicate": "fixture-duplicate-uuid"
        }
      }
    },
    "routing": { "idea": "linear" }
  }
}
JSON
}

_local_config() {
  rm -f "$PROJECT/.claude/ccanvil.json"
}

# ===========================================================================
# Step 1 — Operation registration (AC-1)
# ===========================================================================

@test "BTS-128 AC-1: ticket.transition is a registered operation" {
  _linear_config_with_state_ids
  # Single-arg invocation isolates the is_valid_operation check from the
  # multi-arg parser (Step 2 extends the parser). Without registration,
  # cmd_resolve emits `ERROR: unknown operation "ticket.transition"`.
  run bash "$OPS" resolve ticket.transition BTS-1 --project-dir "$PROJECT"
  [[ ! "$output" =~ "unknown operation" ]]
}

# ===========================================================================
# Step 2 — Argument parser (AC-8)
# ===========================================================================

@test "BTS-128 AC-8: parser accepts a second positional arg after the operation" {
  _linear_config_with_state_ids
  # Pre-parser-extension: "backlog" is rejected by the *) catch-all as
  # "Unknown option: backlog". Post-extension: parsed as OP_ARG2.
  run bash "$OPS" resolve ticket.transition BTS-1 backlog --project-dir "$PROJECT"
  [[ ! "$output" =~ "Unknown option:" ]]
}

@test "BTS-128 AC-8: single-arg operations still parse unchanged (regression)" {
  _local_config
  # backlog.get is a long-standing single-arg op. The parser extension
  # MUST NOT change its behavior — emits the same JSON shape with
  # command substituting OP_ARGS into "cat docs/specs/BTS-42.md".
  run bash "$OPS" resolve backlog.get BTS-42 --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mechanism == "bash"'
  echo "$output" | jq -e '.invocation.command == "cat docs/specs/BTS-42.md"'
}

# ===========================================================================
# Step 3 — Happy-path resolver on Linear provider (AC-2)
# ===========================================================================

@test "BTS-128 AC-2: resolver emits Linear save_issue payload with id + stateId" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 backlog --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # Single combined jq -e — asserts every field at once, avoiding the
  # BTS-127 pattern where only the final jq -e governs test exit status.
  echo "$output" | jq -e '
    .provider == "linear"
    and .mechanism == "mcp"
    and .invocation.tool == "mcp__claude_ai_Linear__save_issue"
    and .invocation.params.id == "BTS-1"
    and .invocation.params.stateId == "fixture-backlog-uuid"
  '
}

# ===========================================================================
# Step 4 — All six roles (AC-3)
# ===========================================================================

@test "BTS-128 AC-3: role=triage resolves to fixture-triage-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.stateId == "fixture-triage-uuid"'
}

@test "BTS-128 AC-3: role=icebox resolves to fixture-icebox-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.stateId == "fixture-icebox-uuid"'
}

@test "BTS-128 AC-3: role=canceled resolves to fixture-canceled-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 canceled --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.stateId == "fixture-canceled-uuid"'
}

@test "BTS-128 AC-3: role=duplicate resolves to fixture-duplicate-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 duplicate --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.stateId == "fixture-duplicate-uuid"'
}

@test "BTS-128 AC-3: role=done resolves to fixture-done-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 done --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.stateId == "fixture-done-uuid"'
}
