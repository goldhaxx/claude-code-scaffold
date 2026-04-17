#!/usr/bin/env bats
# Tests for node UUID registration and registry migration
#
# Each test creates isolated temp directories simulating hub + node repos.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

UUID_V4_REGEX='^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  HUB=$(mktemp -d)
  NODE=$(mktemp -d)

  mkdir -p "$HUB/.claude/rules"
  mkdir -p "$HUB/.ccanvil/scripts"
  cp "$SCRIPT" "$HUB/.ccanvil/scripts/ccanvil-sync.sh"

  cat > "$HUB/.claude/rules/tdd.md" <<'HUBEOF'
# TDD Rules
<!-- NODE-SPECIFIC-START -->
HUBEOF

  git -C "$HUB" init -q
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "init"

  cp -R "$HUB/.claude" "$NODE/.claude"
  mkdir -p "$NODE/.ccanvil/scripts"
  cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh"

  git -C "$NODE" init -q
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "init node"
}

teardown() {
  rm -rf "$HUB" "$NODE"
}


# =========================================================================
# Step 1: UUID generation + dual storage (AC-1, AC-10)
# =========================================================================

@test "init: writes UUID to ccanvil.lock" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid // empty' "$NODE/.ccanvil/ccanvil.lock")
  [ -n "$uuid" ]
  [[ "$uuid" =~ $UUID_V4_REGEX ]]
}

@test "init: writes UUID to .claude/ccanvil.local.json" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid // empty' "$NODE/.claude/ccanvil.local.json")
  [ -n "$uuid" ]
  [[ "$uuid" =~ $UUID_V4_REGEX ]]
}

@test "init: UUID matches across both files" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local lock_uuid json_uuid
  lock_uuid=$(jq -r '.node_uuid' "$NODE/.ccanvil/ccanvil.lock")
  json_uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")
  [ "$lock_uuid" = "$json_uuid" ]
}

@test "init: UUID is lowercase" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")
  [ "$uuid" = "$(echo "$uuid" | tr '[:upper:]' '[:lower:]')" ]
}

@test "init: preserves existing UUID on re-init" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"
  local first
  first=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  # Re-init — should NOT regenerate
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"
  local second
  second=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  [ "$first" = "$second" ]
}

@test "init: fails on malformed UUID in ccanvil.json" {
  cd "$NODE"
  mkdir -p "$NODE/.claude"
  echo '{"node_uuid":"not-a-valid-uuid"}' > "$NODE/.claude/ccanvil.local.json"

  run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "invalid\|malformed\|uuid"
}


# =========================================================================
# Step 2: UUID recovery on lockfile regen (AC-2)
# =========================================================================

@test "init: recovers UUID from ccanvil.json when lockfile is deleted" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"
  local original
  original=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  # Delete lockfile, re-init
  rm -f "$NODE/.ccanvil/ccanvil.lock"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local recovered
  recovered=$(jq -r '.node_uuid' "$NODE/.ccanvil/ccanvil.lock")
  [ "$recovered" = "$original" ]
}


# =========================================================================
# Step 3: Path normalization (unit tests via eval)
# =========================================================================

@test "path helpers: normalize_path replaces HOME with tilde" {
  source "$NODE/.ccanvil/scripts/ccanvil-sync.sh" --source-only

  result=$(normalize_path "$HOME/projects/foo")
  [ "$result" = "~/projects/foo" ]
}

@test "path helpers: expand_path replaces tilde with HOME" {
  source "$NODE/.ccanvil/scripts/ccanvil-sync.sh" --source-only

  result=$(expand_path "~/projects/foo")
  [ "$result" = "$HOME/projects/foo" ]
}

@test "path helpers: absolute paths outside HOME pass through unchanged" {
  source "$NODE/.ccanvil/scripts/ccanvil-sync.sh" --source-only

  result=$(normalize_path "/tmp/not-in-home")
  [ "$result" = "/tmp/not-in-home" ]
}


# =========================================================================
# Step 4: UUID-keyed register (AC-3, AC-4)
# =========================================================================

@test "register: keys registry by UUID" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  # Registry should have entry keyed by UUID
  jq -e --arg u "$uuid" '.nodes[$u]' "$HUB/.ccanvil/registry.json"
}

@test "register: entry contains path in tilde-form" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid path
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")
  path=$(jq -r --arg u "$uuid" '.nodes[$u].path' "$HUB/.ccanvil/registry.json")

  # Path should not contain absolute $HOME (unless NODE is outside $HOME)
  if [[ "$NODE" == "$HOME"/* ]]; then
    [[ "$path" == "~/"* ]]
  else
    [ -n "$path" ]
  fi
}

@test "register: entry has name, registered_at fields" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  jq -e --arg u "$uuid" '.nodes[$u].name' "$HUB/.ccanvil/registry.json"
  jq -e --arg u "$uuid" '.nodes[$u].registered_at' "$HUB/.ccanvil/registry.json"
}

@test "register: re-registering from same UUID updates existing entry (no duplicate)" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  # Call register again
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" register

  # Registry should have exactly one entry for this UUID
  local count
  count=$(jq --arg u "$uuid" '[.nodes | to_entries[] | select(.key == $u)] | length' "$HUB/.ccanvil/registry.json")
  [ "$count" -eq 1 ]

  # Total node count should also be 1 (no path-keyed sibling)
  local total
  total=$(jq '.nodes | length' "$HUB/.ccanvil/registry.json")
  [ "$total" -eq 1 ]
}

@test "register: moving node and re-registering updates path field" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  # Simulate move: copy node to new location, register from there
  local MOVED
  MOVED=$(mktemp -d)
  cp -R "$NODE"/. "$MOVED/"
  cd "$MOVED"
  bash "$MOVED/.ccanvil/scripts/ccanvil-sync.sh" register

  # path field should now reflect MOVED, not NODE
  local path
  path=$(jq -r --arg u "$uuid" '.nodes[$u].path' "$HUB/.ccanvil/registry.json")
  local expanded
  expanded="${path/#\~/$HOME}"
  [ "$expanded" = "$MOVED" ]

  rm -rf "$MOVED"
}


# =========================================================================
# Step 5: registry list includes UUID (AC-9)
# =========================================================================

@test "registry: output includes UUID for each node" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  local output
  output=$(bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" registry)
  echo "$output" | grep -q "$uuid"
}


# =========================================================================
# Step 8: Migration (AC-7, AC-8)
# =========================================================================

@test "migration: path-keyed entries are converted to UUID-keyed on broadcast" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  # Seed legacy path-keyed entry by overwriting registry
  local registry="$HUB/.ccanvil/registry.json"
  jq --arg p "$NODE" --arg u "$uuid" '
    .nodes = {($p): {"name": "node", "registered_at": "0"}}
  ' "$registry" > "$registry.tmp" && mv "$registry.tmp" "$registry"

  # Commit node for broadcast pre-check cleanliness
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "ccanvil init" 2>/dev/null || true
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "seed legacy" 2>/dev/null || true

  # Run broadcast — should migrate
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" broadcast --dry-run >/dev/null 2>&1 || true

  # After migration, entry keyed by UUID exists, path-keyed entry gone
  jq -e --arg u "$uuid" '.nodes[$u]' "$registry"
  local has_path_key
  has_path_key=$(jq --arg p "$NODE" '.nodes | has($p)' "$registry")
  [ "$has_path_key" = "false" ]
}

@test "migration: is idempotent on already-migrated registry" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "ccanvil init" 2>/dev/null || true
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "register" 2>/dev/null || true

  # Snapshot registry
  local before
  before=$(cat "$HUB/.ccanvil/registry.json")

  # Run broadcast — should not modify registry
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" broadcast --dry-run >/dev/null 2>&1 || true

  local after
  after=$(cat "$HUB/.ccanvil/registry.json")
  [ "$before" = "$after" ]
}


# =========================================================================
# Step 6-7: Broadcast iteration + stale path detection (AC-5, AC-6)
# =========================================================================

@test "broadcast: stale path (UUID in registry, path gone) prints STALE and skips" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  local uuid
  uuid=$(jq -r '.node_uuid' "$NODE/.claude/ccanvil.local.json")

  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "ccanvil init" 2>/dev/null || true
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "register" 2>/dev/null || true

  # Move/delete node
  rm -rf "$NODE"

  cd "$HUB"
  local output
  output=$(bash "$HUB/.ccanvil/scripts/ccanvil-sync.sh" broadcast 2>&1 || true)

  echo "$output" | grep -qi "STALE"
  echo "$output" | grep -q "$uuid"

  # Recreate NODE so teardown doesn't error
  mkdir -p "$NODE"
}
