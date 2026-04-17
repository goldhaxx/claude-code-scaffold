#!/usr/bin/env bats
# Tests for ccanvil-sync.sh pull-globals subcommand

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  HUB=$(mktemp -d)
  NODE=$(mktemp -d)
  FAKE_HOME=$(mktemp -d)

  mkdir -p "$HUB/.claude/rules"
  mkdir -p "$HUB/.ccanvil/scripts"
  mkdir -p "$HUB/global-commands"
  cp "$SCRIPT" "$HUB/.ccanvil/scripts/ccanvil-sync.sh"

  cat > "$HUB/.claude/rules/tdd.md" <<'HUBEOF'
# TDD
<!-- NODE-SPECIFIC-START -->
HUBEOF

  # Seed the hub's global-commands directory with a ccanvil-owned file
  cat > "$HUB/global-commands/ccanvil-init.md" <<'HUBEOF'
Initialize a new project using the ccanvil preset. (Invoked as /ccanvil-init.)
HUBEOF

  git -C "$HUB" init -q
  git -C "$HUB" -c user.email=t@t.com -c user.name=t add -A
  git -C "$HUB" -c user.email=t@t.com -c user.name=t commit -q -m "init"

  cp -R "$HUB/.claude" "$NODE/.claude"
  mkdir -p "$NODE/.ccanvil/scripts"
  cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh"
  git -C "$NODE" init -q
  git -C "$NODE" -c user.email=t@t.com -c user.name=t add -A
  git -C "$NODE" -c user.email=t@t.com -c user.name=t commit -q -m "init node"

  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"
}

teardown() {
  rm -rf "$HUB" "$NODE" "$FAKE_HOME"
}


# =========================================================================
# Step 2: Happy path (AC-3, AC-8)
# =========================================================================

@test "pull-globals: copies hub ccanvil-*.md to ~/.claude/commands/" {
  cd "$NODE"
  HOME="$FAKE_HOME" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals
  [ "$status" -eq 0 ]

  [ -f "$FAKE_HOME/.claude/commands/ccanvil-init.md" ]
  grep -q "ccanvil-init" "$FAKE_HOME/.claude/commands/ccanvil-init.md"
}

@test "pull-globals: outputs JSON summary with copied count" {
  cd "$NODE"
  HOME="$FAKE_HOME" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.copied == 1'
  echo "$output" | jq -e '.skipped == 0'
  echo "$output" | jq -e '.conflicts == 0'
}

@test "pull-globals: creates ~/.claude/commands/ if missing" {
  cd "$NODE"
  # FAKE_HOME exists but no .claude/commands inside it
  [ ! -d "$FAKE_HOME/.claude/commands" ]

  HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals >/dev/null
  [ -d "$FAKE_HOME/.claude/commands" ]
}

@test "pull-globals: fails with clear error when \$HOME unset" {
  cd "$NODE"
  HOME="" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "HOME"
}

@test "pull-globals: empty hub global-commands outputs zero counts" {
  rm -f "$HUB"/global-commands/*.md

  cd "$NODE"
  HOME="$FAKE_HOME" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.copied == 0'
  echo "$output" | jq -e '.conflicts == 0'
}


# =========================================================================
# Step 3: Skip unchanged + conflict detection (AC-4)
# =========================================================================

@test "pull-globals: skips file when hub and local hashes match" {
  cd "$NODE"
  HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals >/dev/null

  # Run again — should skip, not recopy
  HOME="$FAKE_HOME" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.copied == 0'
  echo "$output" | jq -e '.skipped == 1'
}

@test "pull-globals: reports conflict when local differs; does not overwrite" {
  cd "$NODE"
  # Seed a differing local file
  mkdir -p "$FAKE_HOME/.claude/commands"
  echo "local custom content" > "$FAKE_HOME/.claude/commands/ccanvil-init.md"
  local custom_hash
  custom_hash=$(shasum -a 256 "$FAKE_HOME/.claude/commands/ccanvil-init.md" | awk '{print $1}')

  local json
  json=$(HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals 2>/dev/null)
  echo "$json" | jq -e '.conflicts == 1'
  echo "$json" | jq -e '.copied == 0'

  # Local file NOT overwritten
  local post_hash
  post_hash=$(shasum -a 256 "$FAKE_HOME/.claude/commands/ccanvil-init.md" | awk '{print $1}')
  [ "$custom_hash" = "$post_hash" ]
}


# =========================================================================
# Step 4: --force (AC-5)
# =========================================================================

@test "pull-globals --force: overwrites conflicted local file" {
  cd "$NODE"
  mkdir -p "$FAKE_HOME/.claude/commands"
  echo "local custom content" > "$FAKE_HOME/.claude/commands/ccanvil-init.md"

  HOME="$FAKE_HOME" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --force
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.copied == 1'
  echo "$output" | jq -e '.conflicts == 0'

  # Local now matches hub
  local hub_hash local_hash
  hub_hash=$(shasum -a 256 "$HUB/global-commands/ccanvil-init.md" | awk '{print $1}')
  local_hash=$(shasum -a 256 "$FAKE_HOME/.claude/commands/ccanvil-init.md" | awk '{print $1}')
  [ "$hub_hash" = "$local_hash" ]
}


# =========================================================================
# Step 5: User namespace sacrosanct (AC-6)
# =========================================================================

@test "pull-globals: never touches files without ccanvil-* prefix" {
  cd "$NODE"
  mkdir -p "$FAKE_HOME/.claude/commands"
  echo "my personal command" > "$FAKE_HOME/.claude/commands/my-personal-command.md"
  echo "something else" > "$FAKE_HOME/.claude/commands/init.md"
  local personal_hash init_hash
  personal_hash=$(shasum -a 256 "$FAKE_HOME/.claude/commands/my-personal-command.md" | awk '{print $1}')
  init_hash=$(shasum -a 256 "$FAKE_HOME/.claude/commands/init.md" | awk '{print $1}')

  HOME="$FAKE_HOME" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --force
  [ "$status" -eq 0 ]

  # Both untouched
  [ "$personal_hash" = "$(shasum -a 256 "$FAKE_HOME/.claude/commands/my-personal-command.md" | awk '{print $1}')" ]
  [ "$init_hash" = "$(shasum -a 256 "$FAKE_HOME/.claude/commands/init.md" | awk '{print $1}')" ]
}

@test "pull-globals: ignores non-ccanvil hub files (doesn't propagate user-prefix)" {
  cd "$NODE"
  # Seed a non-prefixed file in hub's global-commands
  echo "unprefixed hub file" > "$HUB/global-commands/random.md"
  git -C "$HUB" -c user.email=t@t.com -c user.name=t add -A
  git -C "$HUB" -c user.email=t@t.com -c user.name=t commit -q -m "add random"

  HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals >/dev/null

  # Only ccanvil-* propagated; random.md stays in hub only
  [ -f "$FAKE_HOME/.claude/commands/ccanvil-init.md" ]
  [ ! -f "$FAKE_HOME/.claude/commands/random.md" ]
}
