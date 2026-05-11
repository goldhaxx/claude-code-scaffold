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
  set -e
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
  set -e
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
  set -e
  cd "$NODE"
  HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals >/dev/null

  # Run again — should skip, not recopy
  HOME="$FAKE_HOME" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.copied == 0'
  echo "$output" | jq -e '.skipped == 1'
}

@test "pull-globals: reports conflict when local differs; does not overwrite" {
  set -e
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
  set -e
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


# =========================================================================
# BTS-315: --check (staleness probe, non-mutating)
# =========================================================================

# AC-1: envelope shape + idempotency
@test "pull-globals --check: emits envelope keys (stale, missing, up_to_date_count); no writes; idempotent" {
  set -e
  cd "$NODE"

  # Seed a second hub file so the envelope shape is exercised with >1 entry.
  echo "second hub command" > "$HUB/global-commands/ccanvil-other.md"

  # First run — no local files yet, so all two are missing.
  local out1
  out1=$(HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --check)

  # Envelope contains the required top-level keys.
  echo "$out1" | jq -e 'has("stale_count")'
  echo "$out1" | jq -e 'has("stale")'
  echo "$out1" | jq -e 'has("missing_count")'
  echo "$out1" | jq -e 'has("missing")'
  echo "$out1" | jq -e 'has("up_to_date_count")'

  # No writes — FAKE_HOME/.claude/commands/ is not even created when it
  # didn't exist (BTS-315: --check must be strictly read-only).
  [ ! -d "$FAKE_HOME/.claude/commands" ]
  [ ! -f "$FAKE_HOME/.claude/commands/ccanvil-init.md" ]
  [ ! -f "$FAKE_HOME/.claude/commands/ccanvil-other.md" ]

  # Idempotent: a second run produces byte-identical stdout.
  local out2
  out2=$(HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --check)
  [ "$out1" = "$out2" ]
}

# AC-2: hash mismatch → stale[] with both hashes populated
@test "pull-globals --check: hash mismatch surfaces file in stale[] with hub_hash + local_hash" {
  set -e
  cd "$NODE"

  # Seed a divergent local copy.
  mkdir -p "$FAKE_HOME/.claude/commands"
  echo "local divergent content" > "$FAKE_HOME/.claude/commands/ccanvil-init.md"

  local out
  out=$(HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --check)

  echo "$out" | jq -e '.stale_count == 1'
  echo "$out" | jq -e '.missing_count == 0'
  echo "$out" | jq -e '.up_to_date_count == 0'
  echo "$out" | jq -e '.stale | length == 1'
  echo "$out" | jq -e '.stale[0].name == "ccanvil-init.md"'
  echo "$out" | jq -e '.stale[0].hub_hash | type == "string" and length > 0'
  echo "$out" | jq -e '.stale[0].local_hash | type == "string" and length > 0'
  echo "$out" | jq -e '.stale[0].hub_hash != .stale[0].local_hash'
}

# AC-3: hub file with no local → missing[]
@test "pull-globals --check: hub file with no local file surfaces in missing[]" {
  set -e
  cd "$NODE"

  local out
  out=$(HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --check)

  echo "$out" | jq -e '.missing_count == 1'
  echo "$out" | jq -e '.missing | length == 1'
  echo "$out" | jq -e '.missing[0].name == "ccanvil-init.md"'
  echo "$out" | jq -e '.stale_count == 0'
  echo "$out" | jq -e '.up_to_date_count == 0'
}

# AC-8: degenerate empty-hub case → zero counts, empty arrays
@test "pull-globals --check: empty hub global-commands emits zero envelope with [] arrays (not null)" {
  set -e
  cd "$NODE"
  rm -f "$HUB"/global-commands/*.md

  local out
  out=$(HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --check)

  echo "$out" | jq -e '.stale_count == 0'
  echo "$out" | jq -e '.missing_count == 0'
  echo "$out" | jq -e '.up_to_date_count == 0'
  echo "$out" | jq -e '.stale == []'
  echo "$out" | jq -e '.missing == []'
}

# AC-5: error paths preserved under --check
@test "pull-globals --check: \$HOME unset → non-zero exit" {
  cd "$NODE"
  HOME="" run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --check
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "HOME"
}

# AC-6: namespace scope — non-ccanvil-* files never reported
@test "pull-globals --check: non-ccanvil-* files in ~/.claude/commands are never reported" {
  set -e
  cd "$NODE"
  mkdir -p "$FAKE_HOME/.claude/commands"
  echo "user owned tool" > "$FAKE_HOME/.claude/commands/user-owned-tool.md"
  echo "another personal" > "$FAKE_HOME/.claude/commands/my-helper.md"

  local out
  out=$(HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals --check)

  # Envelope mentions neither user-owned file.
  ! echo "$out" | jq -r '..|strings' | grep -q "user-owned-tool"
  ! echo "$out" | jq -r '..|strings' | grep -q "my-helper"
}

# AC-7: pull-globals (no --check) envelope unchanged
@test "pull-globals (no --check): existing copy/skip/conflict envelope unchanged; no staleness keys" {
  set -e
  cd "$NODE"
  local out
  out=$(HOME="$FAKE_HOME" bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" pull-globals)

  echo "$out" | jq -e 'has("copied")'
  echo "$out" | jq -e 'has("skipped")'
  echo "$out" | jq -e 'has("conflicts")'
  echo "$out" | jq -e 'has("stale_count") | not'
  echo "$out" | jq -e 'has("missing_count") | not'
}
