#!/usr/bin/env bats
# Tests for cmd_register auto-commit of .claude/ccanvil.local.json.
# Spec: docs/specs/register-auto-commit.md (BTS-74, Feature 1 of 3)
#
# Mirrors the commit_hub_file pattern on the node side so broadcast's
# dirty-worktree pre-check passes on first register.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  HUB=$(mktemp -d)
  NODE=$(mktemp -d)

  # Minimal hub with its own git repo and ccanvil dir
  mkdir -p "$HUB/.ccanvil/scripts"
  cp "$SCRIPT" "$HUB/.ccanvil/scripts/ccanvil-sync.sh"
  git -C "$HUB" init -q
  git -C "$HUB" -c user.email=test@test -c user.name=test add -A
  git -C "$HUB" -c user.email=test@test -c user.name=test commit -q -m "init hub"

  # Minimal node as a git repo with a lockfile pointing at the hub
  mkdir -p "$NODE/.ccanvil/scripts" "$NODE/.claude"
  cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh"
  cat > "$NODE/.ccanvil/ccanvil.lock" <<LOCKEOF
{
  "hub_source": "$HUB",
  "hub_version": "test",
  "files": {}
}
LOCKEOF

  # .ccanvil and .claude should be tracked so git add/commit isn't a surprise
  git -C "$NODE" init -q
  git -C "$NODE" -c user.email=test@test -c user.name=test add -A
  git -C "$NODE" -c user.email=test@test -c user.name=test commit -q -m "init node"

  # Git identity for subsequent commits made by the script
  git -C "$NODE" config user.email "test@test"
  git -C "$NODE" config user.name "test"
}

teardown() {
  rm -rf "$HUB" "$NODE"
}

# -------------------------------------------------------------------------
# AC-1: first-time register commits .claude/ccanvil.local.json
# -------------------------------------------------------------------------
@test "AC-1: first-time register commits .claude/ccanvil.local.json" {
  (cd "$NODE" && bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" register)

  # File exists
  [ -f "$NODE/.claude/ccanvil.local.json" ]

  # Working tree has no untracked or modified state for this file
  run git -C "$NODE" status --porcelain .claude/ccanvil.local.json
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # A commit that touches the file exists on HEAD
  run git -C "$NODE" log --oneline -- .claude/ccanvil.local.json
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# -------------------------------------------------------------------------
# AC-2: re-running register on an unchanged node makes no new commit
# -------------------------------------------------------------------------
@test "AC-2: re-register with unchanged UUID file creates no new commit" {
  (cd "$NODE" && bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" register)

  local first_sha
  first_sha=$(git -C "$NODE" rev-parse HEAD)

  (cd "$NODE" && bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" register)

  local second_sha
  second_sha=$(git -C "$NODE" rev-parse HEAD)

  [ "$first_sha" = "$second_sha" ]
}

# -------------------------------------------------------------------------
# AC-3: unrelated uncommitted changes are NOT picked up in the register commit
# -------------------------------------------------------------------------
@test "AC-3: register commits only .claude/ccanvil.local.json (not other dirty files)" {
  # Introduce an unrelated uncommitted change in a neutral file
  echo "unrelated" > "$NODE/NOTES.md"
  git -C "$NODE" add NOTES.md
  git -C "$NODE" commit -q -m "seed notes"
  echo "dirty" >> "$NODE/NOTES.md"

  (cd "$NODE" && bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" register)

  # The unrelated file remains dirty after register
  run git -C "$NODE" status --porcelain NOTES.md
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  # The latest commit touched only .claude/ccanvil.local.json
  local files
  files=$(git -C "$NODE" show --name-only --pretty=format: HEAD)
  [[ "$files" == *".claude/ccanvil.local.json"* ]]
  [[ "$files" != *"NOTES.md"* ]]
}

# -------------------------------------------------------------------------
# AC-4: non-git directory: graceful no-op (no error)
# -------------------------------------------------------------------------
@test "AC-4: register in non-git directory exits 0 without commit attempt" {
  # Remove git repo entirely
  rm -rf "$NODE/.git"

  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' register"
  [ "$status" -eq 0 ]

  # File is still created, just not committed
  [ -f "$NODE/.claude/ccanvil.local.json" ]
}

# -------------------------------------------------------------------------
# AC-5: commit message format
# -------------------------------------------------------------------------
@test "AC-5: commit message matches 'chore(ccanvil): register node <name> [<uuid>]'" {
  (cd "$NODE" && bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" register)

  local msg
  msg=$(git -C "$NODE" log -1 --format=%s -- .claude/ccanvil.local.json)

  local node_name
  node_name=$(basename "$NODE")

  [[ "$msg" == "chore(ccanvil): register node $node_name ["* ]]
  [[ "$msg" == *"]" ]]
}
