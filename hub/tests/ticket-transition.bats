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
  # Isolate the is_valid_operation check: invoke with both args so we
  # exercise the full happy path rather than fall into the (correct but
  # unrelated) "role required" error path. Without registration,
  # cmd_resolve emits `ERROR: unknown operation "ticket.transition"`
  # and exits non-zero BEFORE the adapter runs.
  run bash "$OPS" resolve ticket.transition BTS-1 backlog --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
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
  set -e
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

@test "BTS-128 AC-2: resolver emits Linear save_issue payload with id + state" {
  set -e
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
    and .invocation.params.state == "fixture-backlog-uuid"
  '
}

# ===========================================================================
# Step 4 — All six roles (AC-3)
# ===========================================================================

@test "BTS-128 AC-3: role=triage resolves to fixture-triage-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.state == "fixture-triage-uuid"'
}

@test "BTS-128 AC-3: role=icebox resolves to fixture-icebox-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.state == "fixture-icebox-uuid"'
}

@test "BTS-128 AC-3: role=canceled resolves to fixture-canceled-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 canceled --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.state == "fixture-canceled-uuid"'
}

@test "BTS-128 AC-3: role=duplicate resolves to fixture-duplicate-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 duplicate --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.state == "fixture-duplicate-uuid"'
}

@test "BTS-128 AC-3: role=done resolves to fixture-done-uuid" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 done --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.id == "BTS-1" and .invocation.params.state == "fixture-done-uuid"'
}

# ===========================================================================
# Step 6 — Unknown role rejected (AC-7)
# ===========================================================================

@test "BTS-128 AC-7: unknown role rejected with vocabulary listing" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 nonsense --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  # Error message must name the offending role AND enumerate the valid set
  # so the user can self-correct without grepping the source.
  [[ "$output" =~ "nonsense" ]]
  [[ "$output" =~ "triage" ]]
  [[ "$output" =~ "backlog" ]]
  [[ "$output" =~ "done" ]]
}

# ===========================================================================
# Step 7 — Missing args (AC-6)
# ===========================================================================

@test "BTS-128 AC-6: missing id exits with 'id required'" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ticket id" ]]
}

@test "BTS-128 AC-6: missing role exits with 'role required' (distinct from id error)" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve ticket.transition BTS-1 --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "role" ]]
  # Must NOT match the id-required wording — errors are distinct.
  [[ ! "$output" =~ "ticket id" ]]
}

# ===========================================================================
# Step 8 — Unconfigured role fails loud (AC-5)
# ===========================================================================

@test "BTS-128 AC-5: role not in state_ids fails loud with role + config path" {
  _linear_config_missing_done
  run bash "$OPS" resolve ticket.transition BTS-1 done --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "done" ]]
  [[ "$output" =~ "state_ids" ]]
  # No silent-success payload when the lookup fails — config gap must
  # surface as an error the user can action.
  [[ ! "$output" =~ "mcp__claude_ai_Linear__save_issue" ]]
}

# ===========================================================================
# Step 9 — Local provider returns unsupported (AC-9)
# ===========================================================================

@test "BTS-128 AC-9: ticket.transition on local provider exits with 'unsupported'" {
  _local_config
  run bash "$OPS" resolve ticket.transition BTS-1 backlog --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "local" ]]
  [[ "$output" =~ "ticket.transition" ]]
  # No MCP payload leaks through — capability gap is explicit.
  [[ ! "$output" =~ "mcp__claude_ai_Linear__save_issue" ]]
}
