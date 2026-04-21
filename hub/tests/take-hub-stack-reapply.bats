#!/usr/bin/env bats
# Tests for pull-apply take-hub auto-reinvoking stack-apply.
# Spec: docs/specs/take-hub-stack-reapply.md (BTS-74, Feature 2 of 3)

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"
HUB_STACKS="$BATS_TEST_DIRNAME/../../hub/stacks"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  HUB=$(mktemp -d)
  NODE=$(mktemp -d)

  # Hub: needs the fastapi-sqlite stack and a settings.json under .claude/
  mkdir -p "$HUB/.ccanvil/scripts" "$HUB/.claude" "$HUB/hub/stacks"
  cp "$SCRIPT" "$HUB/.ccanvil/scripts/ccanvil-sync.sh"
  cp -R "$HUB_STACKS/fastapi-sqlite" "$HUB/hub/stacks/"

  # Hub's settings.json: NO stack hook entries (correctly stack-agnostic)
  cat > "$HUB/.claude/settings.json" <<'SEOF'
{
  "hooks": {
    "PreToolUse": []
  }
}
SEOF

  git -C "$HUB" init -q
  git -C "$HUB" -c user.email=test@test -c user.name=test add -A
  git -C "$HUB" -c user.email=test@test -c user.name=test commit -q -m "init hub"

  # Node: has settings.json WITH stack hook entries (representing pre-conflict state)
  mkdir -p "$NODE/.ccanvil/scripts" "$NODE/.claude"
  cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh"

  cat > "$NODE/.claude/settings.json" <<'SEOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/protect-db.sh"
          }
        ]
      }
    ]
  }
}
SEOF

  # Also create the hook file so stack-apply's copy phase is happy
  mkdir -p "$NODE/.claude/hooks"
  cp "$HUB/hub/stacks/fastapi-sqlite/hooks/protect-db.sh" "$NODE/.claude/hooks/protect-db.sh"
  chmod +x "$NODE/.claude/hooks/protect-db.sh"

  # Lockfile: settings.json is tracked as origin: hub with a conflict state
  local hub_hash node_hash
  hub_hash=$(shasum -a 256 "$HUB/.claude/settings.json" | awk '{print $1}')
  node_hash=$(shasum -a 256 "$NODE/.claude/settings.json" | awk '{print $1}')
  cat > "$NODE/.ccanvil/ccanvil.lock" <<LOCKEOF
{
  "hub_source": "$HUB",
  "hub_version": "test",
  "files": {
    ".claude/settings.json": {
      "origin": "hub",
      "hub_hash": "$hub_hash",
      "local_hash": "$node_hash",
      "status": "modified",
      "sync": "tracked"
    }
  }
}
LOCKEOF
}

teardown() {
  rm -rf "$HUB" "$NODE"
}

# Helper: seed active stacks list in .claude/ccanvil.json
seed_stacks() {
  local stacks_json="$1"  # e.g., '["fastapi-sqlite"]'
  mkdir -p "$NODE/.claude"
  echo "{\"stacks\": $stacks_json}" > "$NODE/.claude/ccanvil.json"
}

# Helper: run pull-apply in the node
run_pull_apply() {
  (cd "$NODE" && bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-apply "$@")
}

# =========================================================================
# AC-1: active stack → hook re-merged into settings.json after take-hub
# =========================================================================
@test "AC-1: take-hub on settings.json with active stack re-applies stack hook" {
  seed_stacks '["fastapi-sqlite"]'

  run_pull_apply ".claude/settings.json" take-hub

  # protect-db.sh hook entry must be present after take-hub
  local has_hook
  has_hook=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("protect-db.sh"))] | length' "$NODE/.claude/settings.json")
  [ "$has_hook" -ge 1 ]
}

# =========================================================================
# AC-2: no active stacks → behavior identical to pre-fix (hub version only)
# =========================================================================
@test "AC-2: take-hub on settings.json with no stacks performs no reapply" {
  # No .claude/ccanvil.json at all → treated as no active stacks
  run_pull_apply ".claude/settings.json" take-hub

  # settings.json should match hub's version: empty PreToolUse
  local hook_count
  hook_count=$(jq '.hooks.PreToolUse | length' "$NODE/.claude/settings.json")
  [ "$hook_count" = "0" ]
}

# =========================================================================
# AC-3: take-hub on non-settings.json → no reapply even with active stacks
# =========================================================================
@test "AC-3: take-hub on other files does not trigger reapply" {
  seed_stacks '["fastapi-sqlite"]'

  # Track a plain rules file; put hub and node versions on disk
  mkdir -p "$HUB/.claude/rules" "$NODE/.claude/rules"
  echo "hub content" > "$HUB/.claude/rules/tdd.md"
  echo "node content" > "$NODE/.claude/rules/tdd.md"

  # Re-commit hub to pick up the new rules file
  git -C "$HUB" -c user.email=test@test -c user.name=test add -A
  git -C "$HUB" -c user.email=test@test -c user.name=test commit -q -m "add rules"

  # Add lockfile entry for tdd.md
  local hh nh
  hh=$(shasum -a 256 "$HUB/.claude/rules/tdd.md" | awk '{print $1}')
  nh=$(shasum -a 256 "$NODE/.claude/rules/tdd.md" | awk '{print $1}')
  local tmp; tmp=$(mktemp)
  jq --arg hh "$hh" --arg nh "$nh" \
    '.files[".claude/rules/tdd.md"] = {"origin":"hub","hub_hash":$hh,"local_hash":$nh,"status":"modified","sync":"tracked"}' \
    "$NODE/.ccanvil/ccanvil.lock" > "$tmp" && mv "$tmp" "$NODE/.ccanvil/ccanvil.lock"

  # Snapshot settings.json before
  local before
  before=$(cat "$NODE/.claude/settings.json")

  run_pull_apply ".claude/rules/tdd.md" take-hub

  # settings.json must be byte-identical (no reapply triggered)
  local after
  after=$(cat "$NODE/.claude/settings.json")
  [ "$before" = "$after" ]
}

# =========================================================================
# AC-4: missing stack in the list → warn but don't abort other stacks
# =========================================================================
@test "AC-4: unknown stack in list emits warning, valid stack still applies" {
  seed_stacks '["fastapi-sqlite", "does-not-exist"]'

  run_pull_apply ".claude/settings.json" take-hub

  # fastapi-sqlite hook should still be merged back
  local has_hook
  has_hook=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("protect-db.sh"))] | length' "$NODE/.claude/settings.json")
  [ "$has_hook" -ge 1 ]
}

# =========================================================================
# AC-5: missing ccanvil.json → graceful no-op on reapply
# =========================================================================
@test "AC-5: missing .claude/ccanvil.json does not error" {
  rm -f "$NODE/.claude/ccanvil.json"

  run_pull_apply ".claude/settings.json" take-hub

  # settings.json matches hub (empty PreToolUse)
  local hook_count
  hook_count=$(jq '.hooks.PreToolUse | length' "$NODE/.claude/settings.json")
  [ "$hook_count" = "0" ]
}

# =========================================================================
# AC-6: successful reapply prints a human-readable line
# =========================================================================
@test "AC-6: reapply produces REAPPLIED STACK output line" {
  seed_stacks '["fastapi-sqlite"]'

  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' pull-apply .claude/settings.json take-hub"
  [ "$status" -eq 0 ]

  [[ "$output" == *"REAPPLIED STACK: fastapi-sqlite"* ]]
}
