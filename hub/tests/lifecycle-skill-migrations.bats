#!/usr/bin/env bats
# BTS-20 — drift-guards for /pr, /stasis, /spec, /plan migrations onto the
# unified lifecycle-state primitive, plus cmd_recommend delegation.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
PR="$REPO_ROOT/.claude/commands/pr.md"
STASIS="$REPO_ROOT/.claude/skills/stasis/SKILL.md"
SPEC="$REPO_ROOT/.claude/skills/spec/SKILL.md"
PLAN="$REPO_ROOT/.claude/commands/plan.md"
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

# =========================================================================
# AC-11: /pr migrated
# =========================================================================

@test "AC-11: /pr command consumes lifecycle-state primitive" {
  grep -qF 'docs-check.sh lifecycle-state' "$PR"
}

@test "AC-11: /pr command does NOT call docs-check.sh validate as a separate state-parse step" {
  # The migration replaces step 3's separate validate call with a single
  # lifecycle-state envelope read. pr-guard remains as a separate behind-base
  # check (different concern). Allow narrative mentions of "validate" but
  # forbid the literal command invocation.
  local count
  count=$(grep -cE 'docs-check\.sh validate([^a-z-]|$)' "$PR" || true)
  if (( count > 0 )); then
    echo "regression: /pr still invokes docs-check.sh validate ($count times)" >&2
    return 1
  fi
}

# =========================================================================
# AC-12: /stasis pre-flight migrated
# =========================================================================

@test "AC-12: /stasis skill consumes lifecycle-state primitive" {
  grep -qF 'docs-check.sh lifecycle-state' "$STASIS"
}

@test "AC-12: /stasis skill pre-flight does NOT call validate as a separate state-parse step" {
  # /stasis still uses cmd_status for spec.work / plan_hash / content hashes
  # (metadata fetches, not state-parse). The validate call at step 1 should
  # be replaced with lifecycle-state.
  local count
  count=$(grep -cE 'docs-check\.sh validate([^a-z-]|$)' "$STASIS" || true)
  if (( count > 0 )); then
    echo "regression: /stasis still invokes docs-check.sh validate ($count times)" >&2
    return 1
  fi
}

# =========================================================================
# AC-13: /spec pre-flight migrated
# =========================================================================

@test "AC-13: /spec skill consumes lifecycle-state primitive" {
  grep -qF 'docs-check.sh lifecycle-state' "$SPEC"
}

@test "AC-13: /spec skill pre-flight does NOT call validate as a separate state-parse step" {
  local count
  count=$(grep -cE 'docs-check\.sh validate([^a-z-]|$)' "$SPEC" || true)
  if (( count > 0 )); then
    echo "regression: /spec still invokes docs-check.sh validate ($count times)" >&2
    return 1
  fi
}

# =========================================================================
# AC-14: /plan pre-flight gate
# =========================================================================

@test "AC-14: /plan command has lifecycle-state pre-flight" {
  grep -qF 'docs-check.sh lifecycle-state' "$PLAN"
}

@test "AC-14: /plan command refuses on illegal state" {
  # Drift-guard: prose must mention the legal states (spec-activated /
  # plan-written) and refuse otherwise. Match either state name.
  grep -qE 'spec-activated|plan-written' "$PLAN"
}

# =========================================================================
# AC-15: cmd_recommend delegates to cmd_lifecycle_state
# =========================================================================

@test "AC-15: cmd_recommend delegates to cmd_lifecycle_state" {
  # The refactor: cmd_recommend's body invokes cmd_lifecycle_state and reads
  # legal_next_actions[0]. Pin the delegation pattern.
  awk '/^cmd_recommend\(\)/,/^}/' "$SCRIPT" | grep -qF 'cmd_lifecycle_state'
}

@test "AC-15: cmd_recommend output schema unchanged ({next_action, reason})" {
  # Run cmd_recommend on the current repo and verify the JSON shape is
  # backwards-compatible (existing callers consume .next_action and .reason).
  set -e
  run bash "$SCRIPT" recommend
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | has("next_action") and has("reason")'
  echo "$output" | jq -e '.next_action | type == "string"'
  echo "$output" | jq -e '.reason | type == "string"'
}
