#!/usr/bin/env bats
# Tests for stasis-recall migration logic in ccanvil-sync.sh.
# Spec: docs/specs/stasis-recall.md AC-31 through AC-34.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  NODE=$(mktemp -d)
  mkdir -p "$NODE/.ccanvil/scripts" "$NODE/docs" "$NODE/.claude/commands"
  cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh"
  git -C "$NODE" init -q
  git -C "$NODE" config user.email test@test.com
  git -C "$NODE" config user.name test
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "init node"
}

teardown() {
  rm -rf "$NODE"
}

@test "migrate-stasis-artifact: renames docs/checkpoint.md → docs/stasis.md" {
  echo "stasis content" > "$NODE/docs/checkpoint.md"
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "add checkpoint"

  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  [ "$status" -eq 0 ]
  [ -f "$NODE/docs/stasis.md" ]
  [ ! -f "$NODE/docs/checkpoint.md" ]
}

@test "migrate-stasis-artifact: no-op when neither file exists" {
  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  [ "$status" -eq 0 ]
  [ ! -f "$NODE/docs/stasis.md" ]
  [ ! -f "$NODE/docs/checkpoint.md" ]
}

@test "migrate-stasis-artifact: no-op when only stasis.md exists (already migrated)" {
  echo "stasis content" > "$NODE/docs/stasis.md"
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "existing stasis"

  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  [ "$status" -eq 0 ]
  [ -f "$NODE/docs/stasis.md" ]
}

@test "migrate-stasis-artifact: aborts with non-zero exit when both files exist" {
  echo "old content" > "$NODE/docs/checkpoint.md"
  echo "new content" > "$NODE/docs/stasis.md"
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "conflicting state"

  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  [ "$status" -ne 0 ]
  # Both files remain untouched for user inspection
  [ -f "$NODE/docs/checkpoint.md" ]
  [ -f "$NODE/docs/stasis.md" ]
}

@test "migrate-stasis-artifact: idempotent — running twice produces no change" {
  echo "stasis content" > "$NODE/docs/checkpoint.md"
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "add checkpoint"

  bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  local first_head
  first_head=$(git -C "$NODE" rev-parse HEAD)

  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  [ "$status" -eq 0 ]
  local second_head
  second_head=$(git -C "$NODE" rev-parse HEAD)
  # No new commit on second run
  [ "$first_head" = "$second_head" ]
}

@test "migrate-stasis-artifact: deletes .claude/commands/catchup.md when present" {
  echo "catchup content" > "$NODE/.claude/commands/catchup.md"
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "add catchup"

  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  [ "$status" -eq 0 ]
  [ ! -f "$NODE/.claude/commands/catchup.md" ]
}

@test "migrate-stasis-artifact: no-op when catchup.md is absent" {
  # Only ensure dir exists; no catchup file
  run bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  [ "$status" -eq 0 ]
}

@test "migrate-stasis-artifact: commits the rename to preserve git history" {
  echo "stasis content" > "$NODE/docs/checkpoint.md"
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "add checkpoint"

  bash -c "cd '$NODE' && bash '$NODE/.ccanvil/scripts/ccanvil-sync.sh' migrate-stasis-artifact"
  # A new commit should exist on HEAD
  local last_msg
  last_msg=$(git -C "$NODE" log -1 --format=%s)
  [[ "$last_msg" == *"stasis"* ]] || [[ "$last_msg" == *"migrate"* ]]
  # History preserved — git log --follow should find the rename
  run git -C "$NODE" log --follow --oneline -- "docs/stasis.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 1 ]
}
