#!/usr/bin/env bats
# Tests for pull-plan stack-origin classification (BTS-73 / spec: pull-plan-stack-origin)
#
# Bug: cmd_pull_plan flags files with `origin: stack:<id>` as "removed from hub"
# because it only scans the hub root, not hub/stacks/<id>/.
#
# Fix (Option B): short-circuit non-hub origins in the removed-from-hub check.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  HUB=$(mktemp -d)
  NODE=$(mktemp -d)

  # Minimal hub: just a root with a git repo (pull-plan calls get_hub_source)
  mkdir -p "$HUB/.ccanvil/scripts"
  cp "$SCRIPT" "$HUB/.ccanvil/scripts/ccanvil-sync.sh"
  git -C "$HUB" init -q
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "init hub"

  # Node setup: create a minimal lockfile directly, skipping `init` so we can
  # control the origin field on each entry precisely.
  mkdir -p "$NODE/.ccanvil"
  cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh" 2>/dev/null || {
    mkdir -p "$NODE/.ccanvil/scripts"
    cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh"
  }

  cat > "$NODE/.ccanvil/ccanvil.lock" <<LOCKEOF
{
  "hub_source": "$HUB",
  "hub_version": "test",
  "files": {}
}
LOCKEOF
}

teardown() {
  rm -rf "$HUB" "$NODE"
}

# Helper: add a lockfile entry
add_entry() {
  local file="$1" origin="$2" hub_hash="$3" local_hash="$4" status="$5"
  local lock="$NODE/.ccanvil/ccanvil.lock"
  local tmp
  tmp=$(mktemp)
  jq --arg f "$file" --arg o "$origin" --arg hh "$hub_hash" --arg lh "$local_hash" --arg s "$status" \
    '.files[$f] = {"origin": $o, "hub_hash": $hh, "local_hash": $lh, "status": $s, "sync": "tracked"}' \
    "$lock" > "$tmp"
  mv "$tmp" "$lock"
}

# Helper: run pull-plan in the node dir, capture JSON
run_pull_plan() {
  (cd "$NODE" && bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-plan)
}

# =========================================================================
# AC-1: stack-origin file absent from hub root is NOT flagged as removed
# =========================================================================

@test "AC-1: stack-origin file absent from hub root produces no plan entry" {
  # Create a fake hash so lockfile looks real
  local h
  h=$(echo "fake" | shasum -a 256 | awk '{print $1}')

  # File is tracked with origin: stack:fastapi-sqlite but does NOT exist at hub root.
  # This is the normal state for stack files (they live at hub/stacks/<id>/...).
  add_entry ".claude/hooks/protect-db.sh" "stack:fastapi-sqlite" "$h" "$h" "clean"

  # Create the local file so local_hash doesn't mismatch MISSING
  mkdir -p "$NODE/.claude/hooks"
  echo "fake" > "$NODE/.claude/hooks/protect-db.sh"

  local plan
  plan=$(run_pull_plan)

  # Plan must NOT contain an entry for this file under any action.
  local count
  count=$(echo "$plan" | jq '[.[] | select(.file == ".claude/hooks/protect-db.sh")] | length')
  [ "$count" = "0" ]
}

# =========================================================================
# AC-2: hub-origin file absent from hub root IS flagged as removed (regression)
# =========================================================================

@test "AC-2: hub-origin file absent from hub root produces action:removed" {
  local h
  h=$(echo "fake" | shasum -a 256 | awk '{print $1}')

  add_entry ".claude/rules/deleted.md" "hub" "$h" "$h" "clean"
  mkdir -p "$NODE/.claude/rules"
  echo "fake" > "$NODE/.claude/rules/deleted.md"

  local plan
  plan=$(run_pull_plan)

  local action
  action=$(echo "$plan" | jq -r '[.[] | select(.file == ".claude/rules/deleted.md")][0].action')
  [ "$action" = "removed" ]
}

# =========================================================================
# AC-3: stack-origin file present on disk is ignored by pull-plan
# =========================================================================

@test "AC-3: stack-origin file with local copy produces no plan entry" {
  local h
  h=$(echo "fake" | shasum -a 256 | awk '{print $1}')

  add_entry ".claude/hooks/protect-db.sh" "stack:fastapi-sqlite" "$h" "$h" "clean"
  mkdir -p "$NODE/.claude/hooks"
  echo "fake" > "$NODE/.claude/hooks/protect-db.sh"

  local plan
  plan=$(run_pull_plan)

  local count
  count=$(echo "$plan" | jq '[.[] | select(.file == ".claude/hooks/protect-db.sh")] | length')
  [ "$count" = "0" ]
}

# =========================================================================
# AC-4: local-origin file is skipped (existing behavior preserved)
# =========================================================================

@test "AC-4: local-origin file is skipped" {
  local h
  h=$(echo "fake" | shasum -a 256 | awk '{print $1}')

  add_entry ".claude/rules/node-specific.md" "local" "null" "$h" "local-only"
  mkdir -p "$NODE/.claude/rules"
  echo "fake" > "$NODE/.claude/rules/node-specific.md"

  local plan
  plan=$(run_pull_plan)

  local count
  count=$(echo "$plan" | jq '[.[] | select(.file == ".claude/rules/node-specific.md")] | length')
  [ "$count" = "0" ]
}

# =========================================================================
# AC-5: malformed stack origin (empty stack id) is treated as non-hub
# =========================================================================

@test "AC-5: stack: origin with empty id is skipped (non-hub short-circuit)" {
  local h
  h=$(echo "fake" | shasum -a 256 | awk '{print $1}')

  add_entry ".claude/hooks/weird.sh" "stack:" "$h" "$h" "clean"
  mkdir -p "$NODE/.claude/hooks"
  echo "fake" > "$NODE/.claude/hooks/weird.sh"

  local plan
  plan=$(run_pull_plan)

  local count
  count=$(echo "$plan" | jq '[.[] | select(.file == ".claude/hooks/weird.sh")] | length')
  [ "$count" = "0" ]
}
