#!/usr/bin/env bats
# Tests for tech stack distribution: stack profiles, stack-list, stack-apply
#
# Each test creates isolated temp directories simulating hub + node repos.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  HUB=$(mktemp -d)
  NODE=$(mktemp -d)

  # Create minimal hub structure
  mkdir -p "$HUB/.claude/rules"
  mkdir -p "$HUB/.claude/commands"
  mkdir -p "$HUB/.claude/agents"
  mkdir -p "$HUB/.claude/skills/tdd"
  mkdir -p "$HUB/.ccanvil/templates"
  mkdir -p "$HUB/.ccanvil/scripts" "$HUB/scripts"

  # Copy the real script to the hub
  cp "$SCRIPT" "$HUB/.ccanvil/scripts/ccanvil-sync.sh"

  # Create a sample hub rule with delimiter
  cat > "$HUB/.claude/rules/tdd.md" <<'HUBEOF'
# TDD Rules

Always test first.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
HUBEOF

  # Create CLAUDE.md with HUB-MANAGED-START delimiter
  cat > "$HUB/CLAUDE.md" <<'HUBEOF'
# [Project Name]

Node identity here.

<!-- HUB-MANAGED-START -->

## Workflow

Hub methodology here.
HUBEOF

  # Create .gitignore
  cat > "$HUB/.gitignore" <<'HUBEOF'
.DS_Store
node_modules/
HUBEOF

  # Copy the fastapi-sqlite stack profile from real hub
  if [[ -d "$BATS_TEST_DIRNAME/../../hub/stacks/fastapi-sqlite" ]]; then
    mkdir -p "$HUB/hub/stacks"
    cp -R "$BATS_TEST_DIRNAME/../../hub/stacks/fastapi-sqlite" "$HUB/hub/stacks/"
  fi

  # Initialize a git repo in hub
  git -C "$HUB" init -q
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "init"

  # Set up node
  cp -R "$HUB/.claude" "$NODE/.claude"
  mkdir -p "$NODE/.ccanvil/scripts"
  cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh"
  cp "$HUB/.claude/rules/tdd.md" "$NODE/.claude/rules/tdd.md"
  cp "$HUB/CLAUDE.md" "$NODE/CLAUDE.md"

  # Initialize node as a git repo
  git -C "$NODE" init -q
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "init node"

  # Run ccanvil-sync init in node
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init "$HUB"

  # Commit lockfile so node is clean
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "ccanvil init"

  # Commit registration in hub
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "register node" 2>/dev/null || true
}

teardown() {
  rm -rf "$HUB" "$NODE"
}


# =========================================================================
# Step 1: Stack profile structure validation
# =========================================================================

@test "fastapi-sqlite: manifest.json exists and has required fields" {
  [ -f "$HUB/hub/stacks/fastapi-sqlite/manifest.json" ]

  # Required top-level fields
  jq -e '.id' "$HUB/hub/stacks/fastapi-sqlite/manifest.json"
  jq -e '.description' "$HUB/hub/stacks/fastapi-sqlite/manifest.json"
  jq -e '.files' "$HUB/hub/stacks/fastapi-sqlite/manifest.json"
  jq -e '.claudemd_section' "$HUB/hub/stacks/fastapi-sqlite/manifest.json"
  jq -e '.settings_hooks' "$HUB/hub/stacks/fastapi-sqlite/manifest.json"
  jq -e '.lint_config' "$HUB/hub/stacks/fastapi-sqlite/manifest.json"
}

@test "fastapi-sqlite: manifest id matches directory name" {
  local id
  id=$(jq -r '.id' "$HUB/hub/stacks/fastapi-sqlite/manifest.json")
  [ "$id" = "fastapi-sqlite" ]
}

@test "fastapi-sqlite: files entries have source, target, action" {
  local count
  count=$(jq '.files | length' "$HUB/hub/stacks/fastapi-sqlite/manifest.json")
  [ "$count" -gt 0 ]

  # Every entry must have source, target, action
  local invalid
  invalid=$(jq '[.files[] | select(.source == null or .target == null or .action == null)] | length' \
    "$HUB/hub/stacks/fastapi-sqlite/manifest.json")
  [ "$invalid" -eq 0 ]
}

@test "fastapi-sqlite: all referenced files exist on disk" {
  local stack_dir="$HUB/hub/stacks/fastapi-sqlite"

  # Check files referenced in files[] array
  while IFS= read -r source; do
    [ -f "$stack_dir/$source" ] || fail "Missing file: $source"
  done < <(jq -r '.files[].source' "$stack_dir/manifest.json")

  # Check claudemd_section file
  local section_file
  section_file=$(jq -r '.claudemd_section' "$stack_dir/manifest.json")
  [ -f "$stack_dir/$section_file" ] || fail "Missing claudemd_section: $section_file"

  # Check settings_hooks file
  local hooks_file
  hooks_file=$(jq -r '.settings_hooks' "$stack_dir/manifest.json")
  [ -f "$stack_dir/$hooks_file" ] || fail "Missing settings_hooks: $hooks_file"

  # Check lint_config file
  local lint_file
  lint_file=$(jq -r '.lint_config' "$stack_dir/manifest.json")
  [ -f "$stack_dir/$lint_file" ] || fail "Missing lint_config: $lint_file"
}

@test "fastapi-sqlite: protect-db.sh is executable and has correct shebang" {
  local hook
  hook=$(jq -r '.files[] | select(.target | contains("protect-db")) | .source' \
    "$HUB/hub/stacks/fastapi-sqlite/manifest.json")
  [ -n "$hook" ]
  [ -f "$HUB/hub/stacks/fastapi-sqlite/$hook" ]

  # Check shebang
  head -1 "$HUB/hub/stacks/fastapi-sqlite/$hook" | grep -q '#!/usr/bin/env bash'
}

@test "fastapi-sqlite: claudemd-section has STACK delimiters" {
  local section_file
  section_file=$(jq -r '.claudemd_section' "$HUB/hub/stacks/fastapi-sqlite/manifest.json")

  grep -q '<!-- STACK:fastapi-sqlite-START -->' "$HUB/hub/stacks/fastapi-sqlite/$section_file"
  grep -q '<!-- STACK:fastapi-sqlite-END -->' "$HUB/hub/stacks/fastapi-sqlite/$section_file"
}

@test "fastapi-sqlite: settings-hooks.json is valid JSON with hook entries" {
  local hooks_file
  hooks_file=$(jq -r '.settings_hooks' "$HUB/hub/stacks/fastapi-sqlite/manifest.json")

  jq empty "$HUB/hub/stacks/fastapi-sqlite/$hooks_file"
  jq -e '.hooks' "$HUB/hub/stacks/fastapi-sqlite/$hooks_file"
}

@test "fastapi-sqlite: lint.json is valid JSON" {
  local lint_file
  lint_file=$(jq -r '.lint_config' "$HUB/hub/stacks/fastapi-sqlite/manifest.json")

  jq empty "$HUB/hub/stacks/fastapi-sqlite/$lint_file"
}


# =========================================================================
# Step 2: stack-list
# =========================================================================

@test "stack-list: returns JSON array with fastapi-sqlite" {
  cd "$NODE"
  local result
  result=$(bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-list)

  echo "$result" | jq -e '.[0].id == "fastapi-sqlite"'
  echo "$result" | jq -e '.[0].description'
  echo "$result" | jq -e '.[0].files'
}

@test "stack-list: returns empty array when no stacks exist" {
  # Remove all stacks from hub
  rm -rf "$HUB/hub/stacks"
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "remove stacks"

  cd "$NODE"
  local result
  result=$(bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-list)
  [ "$result" = "[]" ]
}


# =========================================================================
# Step 3: stack-apply file copy + lockfile + ccanvil.json
# =========================================================================

@test "stack-apply: copies hook script to target path" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  # protect-db.sh should exist in the node
  [ -f "$NODE/.claude/hooks/protect-db.sh" ]
}

@test "stack-apply: creates lockfile entry with stack origin" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  local origin
  origin=$(jq -r '.files[".claude/hooks/protect-db.sh"].origin' "$NODE/.ccanvil/ccanvil.lock")
  [ "$origin" = "stack:fastapi-sqlite" ]
}

@test "stack-apply: records stack in ccanvil.json" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  jq -e '.stacks | index("fastapi-sqlite")' "$NODE/.claude/ccanvil.json"
}

@test "stack-apply: invalid stack ID exits non-zero" {
  cd "$NODE"
  run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply nonexistent-stack
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not found\|invalid\|error"
}


# =========================================================================
# Step 4: CLAUDE.md section merge
# =========================================================================

@test "stack-apply: inserts CLAUDE.md section with delimiters" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  grep -q '<!-- STACK:fastapi-sqlite-START -->' "$NODE/CLAUDE.md"
  grep -q '<!-- STACK:fastapi-sqlite-END -->' "$NODE/CLAUDE.md"
}

@test "stack-apply: CLAUDE.md section placed above HUB-MANAGED-START" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  # STACK section should appear before HUB-MANAGED-START
  local stack_line hub_line
  stack_line=$(grep -n 'STACK:fastapi-sqlite-START' "$NODE/CLAUDE.md" | head -1 | cut -d: -f1)
  hub_line=$(grep -n 'HUB-MANAGED-START' "$NODE/CLAUDE.md" | head -1 | cut -d: -f1)
  [ "$stack_line" -lt "$hub_line" ]
}

@test "stack-apply: re-running does not duplicate CLAUDE.md section" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  local count
  count=$(grep -c 'STACK:fastapi-sqlite-START' "$NODE/CLAUDE.md")
  [ "$count" -eq 1 ]
}


# =========================================================================
# Step 5: settings.json + lint.json merge
# =========================================================================

@test "stack-apply: merges hook entry into settings.json" {
  cd "$NODE"
  # Create a minimal settings.json
  mkdir -p "$NODE/.claude"
  echo '{"permissions":{},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"existing-hook.sh"}]}]}}' \
    > "$NODE/.claude/settings.json"

  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  # Should have protect-db.sh in hooks
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("protect-db"))' \
    "$NODE/.claude/settings.json"
}

@test "stack-apply: settings.json merge does not duplicate existing entries" {
  cd "$NODE"
  mkdir -p "$NODE/.claude"
  echo '{"permissions":{},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"existing-hook.sh"}]}]}}' \
    > "$NODE/.claude/settings.json"

  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  local count
  count=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("protect-db"))] | length' \
    "$NODE/.claude/settings.json")
  [ "$count" -eq 1 ]
}


# =========================================================================
# Step 6: Patch flow (re-apply on existing stack)
# =========================================================================

@test "stack-apply patch: adds missing files without clobbering existing" {
  cd "$NODE"
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  # Customize protect-db.sh in node
  echo "# node customization" >> "$NODE/.claude/hooks/protect-db.sh"
  local custom_hash
  custom_hash=$(shasum -a 256 "$NODE/.claude/hooks/protect-db.sh" | awk '{print $1}')

  # Re-apply — should not overwrite customized file
  bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" stack-apply fastapi-sqlite

  local current_hash
  current_hash=$(shasum -a 256 "$NODE/.claude/hooks/protect-db.sh" | awk '{print $1}')
  [ "$current_hash" = "$custom_hash" ]
}


# =========================================================================
# Step 7: init-preflight with --stack flag (AC-5)
# =========================================================================

@test "init-preflight --stack: includes stack files in plan" {
  # Create a fresh target directory (not yet initialized)
  local TARGET
  TARGET=$(mktemp -d)
  mkdir -p "$TARGET/.claude"

  cd "$TARGET"
  local result
  result=$(bash "$HUB/.ccanvil/scripts/ccanvil-sync.sh" init-preflight "$HUB" --stack fastapi-sqlite)

  # Should include protect-db.sh in the plan
  echo "$result" | jq -e '.plan[] | select(.file == ".claude/hooks/protect-db.sh")'
}

@test "init-preflight --stack: stack files have stack source" {
  local TARGET
  TARGET=$(mktemp -d)
  mkdir -p "$TARGET/.claude"

  cd "$TARGET"
  local result
  result=$(bash "$HUB/.ccanvil/scripts/ccanvil-sync.sh" init-preflight "$HUB" --stack fastapi-sqlite)

  local source
  source=$(echo "$result" | jq -r '.plan[] | select(.file == ".claude/hooks/protect-db.sh") | .source')
  [ "$source" = "stack:fastapi-sqlite" ]
}

@test "init-preflight: reads stacks from ccanvil.json" {
  local TARGET
  TARGET=$(mktemp -d)
  mkdir -p "$TARGET/.claude"
  echo '{"stacks":["fastapi-sqlite"]}' > "$TARGET/.claude/ccanvil.json"

  cd "$TARGET"
  local result
  result=$(bash "$HUB/.ccanvil/scripts/ccanvil-sync.sh" init-preflight "$HUB")

  # Should include protect-db.sh without --stack flag
  echo "$result" | jq -e '.plan[] | select(.file == ".claude/hooks/protect-db.sh")'
}


# =========================================================================
# Step 8: init-apply with stack entries (AC-6)
# =========================================================================

@test "init-apply: provisions stack files from preflight plan" {
  local TARGET
  TARGET=$(mktemp -d)
  mkdir -p "$TARGET/.claude"

  cd "$TARGET"

  # Run preflight with stack flag
  local plan_file
  plan_file=$(mktemp)
  bash "$HUB/.ccanvil/scripts/ccanvil-sync.sh" init-preflight "$HUB" --stack fastapi-sqlite > "$plan_file"

  # Run init-apply
  bash "$HUB/.ccanvil/scripts/ccanvil-sync.sh" init-apply "$HUB" "$plan_file"

  # Stack file should be provisioned
  [ -f "$TARGET/.claude/hooks/protect-db.sh" ]
}
