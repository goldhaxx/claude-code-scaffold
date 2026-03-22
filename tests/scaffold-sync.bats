#!/usr/bin/env bats
# Tests for scripts/scaffold-sync.sh
#
# Each test creates isolated temp directories simulating hub + node repos.
# No real git remotes — everything is local and deterministic.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/scaffold-sync.sh"

# ---------------------------------------------------------------------------
# Fixtures: create mock hub and node directories
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
  mkdir -p "$HUB/docs/templates"
  mkdir -p "$HUB/scripts"

  # Copy the real script to the hub
  cp "$SCRIPT" "$HUB/scripts/scaffold-sync.sh"

  # Create a sample hub rule with delimiter
  cat > "$HUB/.claude/rules/tdd.md" <<'HUBEOF'
# TDD Rules

Always test first.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
HUBEOF

  # Create a sample hub command (no frontmatter)
  cat > "$HUB/.claude/commands/catchup.md" <<'HUBEOF'
Read the current state of the project.

Do NOT start implementing anything.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
HUBEOF

  # Create a sample hub agent (with YAML frontmatter)
  cat > "$HUB/.claude/agents/spec-writer.md" <<'HUBEOF'
---
name: spec-writer
description: "Writes specs"
---

# Spec Writer

Write specs from feature requests.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
HUBEOF

  # Create GUIDE.md with NODE-SPECIFIC-START delimiter
  cat > "$HUB/GUIDE.md" <<'HUBEOF'
# Scaffold Guide

Hub documentation here.

<!-- NODE-SPECIFIC-START -->
<!-- Everything above is managed by the scaffold hub. -->

## Project-Specific Features

_None yet._
HUBEOF

  # Create CLAUDE.md with HUB-MANAGED-START delimiter
  cat > "$HUB/CLAUDE.md" <<'HUBEOF'
# [Project Name]

Node identity here.

<!-- HUB-MANAGED-START -->

## Workflow

Hub methodology here.
HUBEOF

  # Copy the real sync script to the hub (so bootstrap doesn't fire on every test)
  cp "$SCRIPT" "$HUB/scripts/scaffold-sync.sh"

  # Create SCAFFOLD_CHANGELOG.md in hub (required by push-apply and promote)
  echo "# Scaffold Changelog" > "$HUB/SCAFFOLD_CHANGELOG.md"

  # Initialize a git repo in hub (needed for scaffold_version)
  git -C "$HUB" init -q
  git -C "$HUB" add -A
  git -C "$HUB" commit -q -m "init"

  # Set up node as a copy of hub, then init lockfile
  cp -R "$HUB/.claude" "$NODE/.claude"
  cp -R "$HUB/docs" "$NODE/docs" 2>/dev/null || true
  mkdir -p "$NODE/scripts"
  cp "$SCRIPT" "$NODE/scripts/scaffold-sync.sh"
  cp "$HUB/.claude/rules/tdd.md" "$NODE/.claude/rules/tdd.md"
  cp "$HUB/.claude/commands/catchup.md" "$NODE/.claude/commands/catchup.md"
  cp "$HUB/.claude/agents/spec-writer.md" "$NODE/.claude/agents/spec-writer.md"
  cp "$HUB/GUIDE.md" "$NODE/GUIDE.md"
  cp "$HUB/CLAUDE.md" "$NODE/CLAUDE.md"

  # Initialize node as a git repo (needed for pre-check and pull-finalize)
  git -C "$NODE" init -q
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "init node"

  # Run scaffold init in node
  cd "$NODE"
  bash "$NODE/scripts/scaffold-sync.sh" init "$HUB"

  # Commit the lockfile so the node is clean
  git -C "$NODE" add -A
  git -C "$NODE" commit -q -m "scaffold init"
}

teardown() {
  rm -rf "$HUB" "$NODE"
}


# =========================================================================
# section-merge tests
# =========================================================================

@test "section-merge: NODE-SPECIFIC-START — hub above, node below" {
  # Node has customized the node section
  cat > "$NODE/.claude/rules/tdd.md" <<'EOF'
# TDD Rules

Always test first.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->

## My Project Tests

Use pytest for everything.
EOF

  # Hub has updated the hub section
  cat > "$HUB/.claude/rules/tdd.md" <<'EOF'
# TDD Rules v2

Always test first. New hub content.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
EOF

  result=$(bash "$NODE/scripts/scaffold-sync.sh" section-merge "$HUB/.claude/rules/tdd.md" "$NODE/.claude/rules/tdd.md")

  # Hub section should be from hub (v2)
  echo "$result" | grep -q "TDD Rules v2"
  # Node section should be preserved
  echo "$result" | grep -q "My Project Tests"
  echo "$result" | grep -q "Use pytest for everything"
}

@test "section-merge: local file has no delimiter — entire content becomes node section" {
  # Node file predates delimiters (no delimiter)
  cat > "$NODE/.claude/rules/tdd.md" <<'EOF'
# TDD Rules

My old custom content.
EOF

  result=$(bash "$NODE/scripts/scaffold-sync.sh" section-merge "$HUB/.claude/rules/tdd.md" "$NODE/.claude/rules/tdd.md")

  # Hub section should be from hub
  echo "$result" | grep -q "Always test first"
  # Delimiter should be present
  echo "$result" | grep -q "NODE-SPECIFIC-START"
  # Old local content should be migrated below delimiter
  echo "$result" | grep -q "My old custom content"
}

@test "section-merge: HUB-MANAGED-START — node above, hub below" {
  # Node has customized the node section (above delimiter)
  cat > "$NODE/CLAUDE.md" <<'EOF'
# My Awesome App

Custom node identity.

<!-- HUB-MANAGED-START -->

## Workflow

Hub methodology here.
EOF

  # Hub has updated the hub section (below delimiter)
  cat > "$HUB/CLAUDE.md" <<'EOF'
# [Project Name]

Node identity here.

<!-- HUB-MANAGED-START -->

## Workflow v2

Updated hub methodology.
EOF

  result=$(bash "$NODE/scripts/scaffold-sync.sh" section-merge "$HUB/CLAUDE.md" "$NODE/CLAUDE.md")

  # Node section should be preserved (from local)
  echo "$result" | grep -q "My Awesome App"
  echo "$result" | grep -q "Custom node identity"
  # Hub section should be updated (from scaffold)
  echo "$result" | grep -q "Workflow v2"
  echo "$result" | grep -q "Updated hub methodology"
}

@test "section-merge: empty node section handled gracefully" {
  # Node has delimiter but nothing below it
  cat > "$NODE/.claude/rules/tdd.md" <<'EOF'
# TDD Rules

Always test first.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
EOF

  # Hub updates hub section
  cat > "$HUB/.claude/rules/tdd.md" <<'EOF'
# TDD Rules v2

New hub content.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
EOF

  result=$(bash "$NODE/scripts/scaffold-sync.sh" section-merge "$HUB/.claude/rules/tdd.md" "$NODE/.claude/rules/tdd.md")

  # Should have v2 content
  echo "$result" | grep -q "TDD Rules v2"
  # Delimiter should be present
  echo "$result" | grep -q "NODE-SPECIFIC-START"
}

@test "section-merge: no delimiter in scaffold file — returns error" {
  cat > "$HUB/.claude/rules/no-delim.md" <<'EOF'
# A Rule

No delimiter here.
EOF

  cat > "$NODE/.claude/rules/no-delim.md" <<'EOF'
# A Rule

Local version.
EOF

  run bash "$NODE/scripts/scaffold-sync.sh" section-merge "$HUB/.claude/rules/no-delim.md" "$NODE/.claude/rules/no-delim.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no section delimiter"
}

@test "section-merge: YAML frontmatter preserved in agent file" {
  # Hub updates the agent but frontmatter stays
  cat > "$HUB/.claude/agents/spec-writer.md" <<'EOF'
---
name: spec-writer
description: "Writes specs v2"
---

# Spec Writer v2

Updated spec writing process.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
EOF

  # Node has custom content below delimiter
  cat > "$NODE/.claude/agents/spec-writer.md" <<'EOF'
---
name: spec-writer
description: "Writes specs"
---

# Spec Writer

Write specs from feature requests.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->

## Project Context

This project uses domain-driven design.
EOF

  result=$(bash "$NODE/scripts/scaffold-sync.sh" section-merge "$HUB/.claude/agents/spec-writer.md" "$NODE/.claude/agents/spec-writer.md")

  # Hub section should have v2 (including updated frontmatter from hub)
  echo "$result" | grep -q "Spec Writer v2"
  echo "$result" | grep -q 'description: "Writes specs v2"'
  # Node section should be preserved
  echo "$result" | grep -q "domain-driven design"
}


# =========================================================================
# pull-plan tests
# =========================================================================

@test "pull-plan: unchanged files produce empty plan" {
  cd "$NODE"
  result=$(bash "$NODE/scripts/scaffold-sync.sh" pull-plan)

  # Should be an empty JSON array
  [ "$(echo "$result" | jq 'length')" -eq 0 ]
}

@test "pull-plan: scaffold change on clean file → auto-update" {
  cd "$NODE"

  # Modify hub version of tdd.md
  echo "# Updated TDD Rules" > "$HUB/.claude/rules/tdd.md"
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "update tdd"

  result=$(bash "$NODE/scripts/scaffold-sync.sh" pull-plan)

  echo "$result" | jq -e '.[] | select(.file == ".claude/rules/tdd.md" and .action == "auto-update")'
}

@test "pull-plan: both changed + has delimiter → section-merge" {
  cd "$NODE"

  # Modify hub version
  cat > "$HUB/.claude/rules/tdd.md" <<'EOF'
# TDD Rules v2

Updated hub content.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
EOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "update tdd"

  # Modify node version (add node-specific content)
  cat > "$NODE/.claude/rules/tdd.md" <<'EOF'
# TDD Rules

Always test first.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->

## Project tests
Use vitest.
EOF

  result=$(bash "$NODE/scripts/scaffold-sync.sh" pull-plan)

  echo "$result" | jq -e '.[] | select(.file == ".claude/rules/tdd.md" and .action == "section-merge")'
}

@test "pull-plan: non-markdown file with delimiter string is NOT section-merge" {
  cd "$NODE"

  # Create a separate .sh file that contains the delimiter as a literal string
  # (We can't overwrite scaffold-sync.sh since we need it to run pull-plan)
  mkdir -p "$HUB/scripts"
  cat > "$HUB/scripts/other-script.sh" <<'SEOF'
#!/usr/bin/env bash
# This script references <!-- NODE-SPECIFIC-START --> as a string literal
echo "hub version"
SEOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "add other-script"

  # Copy to node and init to get it in the lockfile
  cp "$HUB/scripts/other-script.sh" "$NODE/scripts/other-script.sh"
  bash "$NODE/scripts/scaffold-sync.sh" init "$HUB"

  # Now modify both sides so pull-plan sees a conflict
  cat > "$HUB/scripts/other-script.sh" <<'SEOF'
#!/usr/bin/env bash
# Updated with <!-- NODE-SPECIFIC-START --> literal
echo "hub v2"
SEOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "update other-script"

  cat > "$NODE/scripts/other-script.sh" <<'SEOF'
#!/usr/bin/env bash
echo "local version"
SEOF

  result=$(bash "$NODE/scripts/scaffold-sync.sh" pull-plan)

  # Should be conflict, NOT section-merge (because .sh is not .md)
  action=$(echo "$result" | jq -r '.[] | select(.file == "scripts/other-script.sh") | .action')
  [ "$action" = "conflict" ]
}

@test "pull-plan: node-only files are excluded from plan" {
  cd "$NODE"

  # Mark tdd.md as node-only
  bash "$NODE/scripts/scaffold-sync.sh" node-only ".claude/rules/tdd.md"

  # Modify hub version
  echo "# Changed" > "$HUB/.claude/rules/tdd.md"
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "update"

  result=$(bash "$NODE/scripts/scaffold-sync.sh" pull-plan)

  # tdd.md should NOT appear in the plan
  count=$(echo "$result" | jq '[.[] | select(.file == ".claude/rules/tdd.md")] | length')
  [ "$count" -eq 0 ]
}

@test "pull-plan: new file in scaffold → action is new" {
  cd "$NODE"

  # Add new file to hub
  cat > "$HUB/.claude/rules/new-rule.md" <<'EOF'
# New Rule

Brand new content.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
EOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "add new rule"

  result=$(bash "$NODE/scripts/scaffold-sync.sh" pull-plan)

  echo "$result" | jq -e '.[] | select(.file == ".claude/rules/new-rule.md" and .action == "new")'
}


# =========================================================================
# node-only / track / classify tests
# =========================================================================

@test "node-only: marks file as node-only in lockfile" {
  cd "$NODE"
  bash "$NODE/scripts/scaffold-sync.sh" node-only ".claude/rules/tdd.md"

  sync=$(jq -r '.files[".claude/rules/tdd.md"].sync' "$NODE/.claude/scaffold.lock")
  [ "$sync" = "node-only" ]
}

@test "node-only: idempotent — running twice doesn't error" {
  cd "$NODE"
  bash "$NODE/scripts/scaffold-sync.sh" node-only ".claude/rules/tdd.md"
  run bash "$NODE/scripts/scaffold-sync.sh" node-only ".claude/rules/tdd.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already node-only"
}

@test "track: restores node-only file to tracked state" {
  cd "$NODE"
  bash "$NODE/scripts/scaffold-sync.sh" node-only ".claude/rules/tdd.md"
  bash "$NODE/scripts/scaffold-sync.sh" track ".claude/rules/tdd.md"

  sync=$(jq -r '.files[".claude/rules/tdd.md"].sync' "$NODE/.claude/scaffold.lock")
  [ "$sync" = "tracked" ]
}

@test "node-only: file not in lockfile → error" {
  cd "$NODE"
  run bash "$NODE/scripts/scaffold-sync.sh" node-only "nonexistent.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not tracked"
}


# =========================================================================
# accept-new tests
# =========================================================================

@test "accept-new: refuses to overwrite existing local file" {
  cd "$NODE"

  # File already exists locally
  cat > "$NODE/.claude/rules/existing.md" <<'EOF'
# Existing Rule

My custom content I don't want to lose.
EOF

  # Same file exists in hub
  cat > "$HUB/.claude/rules/existing.md" <<'EOF'
# Hub Rule

Different content from hub.
EOF

  run bash "$NODE/scripts/scaffold-sync.sh" pull-apply ".claude/rules/existing.md" accept-new
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "already exists"

  # Local content should be unchanged
  grep -q "My custom content" "$NODE/.claude/rules/existing.md"
}

@test "accept-new: copies file and adds lockfile entry" {
  cd "$NODE"

  # Add new file to hub
  cat > "$HUB/.claude/rules/new-rule.md" <<'EOF'
# New Rule

Fresh content.
EOF

  bash "$NODE/scripts/scaffold-sync.sh" pull-apply ".claude/rules/new-rule.md" accept-new

  # File should exist locally
  [ -f "$NODE/.claude/rules/new-rule.md" ]
  grep -q "Fresh content" "$NODE/.claude/rules/new-rule.md"

  # Lockfile should have entry
  jq -e '.files[".claude/rules/new-rule.md"]' "$NODE/.claude/scaffold.lock"
  status=$(jq -r '.files[".claude/rules/new-rule.md"].status' "$NODE/.claude/scaffold.lock")
  [ "$status" = "clean" ]
}


# =========================================================================
# init tests
# =========================================================================

@test "init: creates lockfile with correct structure" {
  cd "$NODE"
  [ -f "$NODE/.claude/scaffold.lock" ]

  # Check required top-level fields
  jq -e '.scaffold_source' "$NODE/.claude/scaffold.lock"
  jq -e '.scaffold_version' "$NODE/.claude/scaffold.lock"
  jq -e '.synced_at' "$NODE/.claude/scaffold.lock"
  jq -e '.files' "$NODE/.claude/scaffold.lock"
}

@test "init: files matching tracked patterns are in lockfile" {
  cd "$NODE"

  # Our setup created tdd.md, catchup.md, spec-writer.md — all should be tracked
  jq -e '.files[".claude/rules/tdd.md"]' "$NODE/.claude/scaffold.lock"
  jq -e '.files[".claude/commands/catchup.md"]' "$NODE/.claude/scaffold.lock"
  jq -e '.files[".claude/agents/spec-writer.md"]' "$NODE/.claude/scaffold.lock"
}

@test "init: clean files have matching hashes" {
  cd "$NODE"

  status=$(jq -r '.files[".claude/rules/tdd.md"].status' "$NODE/.claude/scaffold.lock")
  [ "$status" = "clean" ]

  scaffold_hash=$(jq -r '.files[".claude/rules/tdd.md"].scaffold_hash' "$NODE/.claude/scaffold.lock")
  local_hash=$(jq -r '.files[".claude/rules/tdd.md"].local_hash' "$NODE/.claude/scaffold.lock")
  [ "$scaffold_hash" = "$local_hash" ]
}


# =========================================================================
# hash helper tests
# =========================================================================

@test "hash: returns sha256 for existing file" {
  echo "test content" > "$NODE/test.txt"
  cd "$NODE"
  result=$(bash "$NODE/scripts/scaffold-sync.sh" hash "$NODE/test.txt")
  # Output format is: <hash>  <filepath>
  hash_part=$(echo "$result" | awk '{print $1}')
  [ -n "$hash_part" ]
  [ ${#hash_part} -eq 64 ]  # sha256 hex digest is 64 chars
}

@test "hash: returns MISSING for nonexistent file" {
  cd "$NODE"
  result=$(bash "$NODE/scripts/scaffold-sync.sh" hash "$NODE/nonexistent.txt")
  # Output format is: MISSING  <filepath>
  hash_part=$(echo "$result" | awk '{print $1}')
  [ "$hash_part" = "MISSING" ]
}


# =========================================================================
# pre-check tests
# =========================================================================

@test "pre-check: passes when both repos are clean" {
  cd "$NODE"
  run bash "$NODE/scripts/scaffold-sync.sh" pre-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
}

@test "pre-check: fails when hub has uncommitted changes" {
  cd "$NODE"
  echo "dirty" > "$HUB/dirty.txt"
  run bash "$NODE/scripts/scaffold-sync.sh" pre-check
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "scaffold repo has uncommitted"
}

@test "pre-check: fails when node has uncommitted changes" {
  cd "$NODE"
  echo "dirty" > "$NODE/dirty.txt"
  run bash "$NODE/scripts/scaffold-sync.sh" pre-check
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "this project has uncommitted"
}


# =========================================================================
# pull-finalize tests
# =========================================================================

@test "pull-finalize: creates a git commit with sync summary" {
  cd "$NODE"

  # Modify hub and run a pull-auto to create real changes
  cat > "$HUB/.claude/rules/tdd.md" <<'EOF'
# TDD Rules v2

Updated hub content.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
EOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "update tdd"

  bash "$NODE/scripts/scaffold-sync.sh" pull-auto

  # Finalize should commit
  bash "$NODE/scripts/scaffold-sync.sh" pull-finalize

  # Verify a commit was created
  local last_msg
  last_msg=$(git -C "$NODE" log -1 --format='%s')
  echo "$last_msg" | grep -q "chore(scaffold): pull from hub"

  # Working tree should be clean after finalize
  local status
  status=$(git -C "$NODE" status --porcelain)
  [ -z "$status" ]
}

@test "pull-finalize: commit message lists synced files" {
  cd "$NODE"

  # Modify hub
  cat > "$HUB/.claude/commands/catchup.md" <<'EOF'
Updated catchup command.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
EOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "update catchup"

  bash "$NODE/scripts/scaffold-sync.sh" pull-auto
  bash "$NODE/scripts/scaffold-sync.sh" pull-finalize

  # Commit body should list the changed file
  local body
  body=$(git -C "$NODE" log -1 --format='%b')
  echo "$body" | grep -q "catchup.md"
}


# =========================================================================
# adopt-clean / adopt-conflict tests
# =========================================================================

@test "pull-plan: new file in scaffold + identical local copy → adopt-clean" {
  cd "$NODE"

  # Add file to hub
  cat > "$HUB/.claude/rules/new-rule.md" <<'EOF'
# New Rule
Same content.
EOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "add new rule"

  # Manually copy the same file to node (simulates prior manual copy)
  cp "$HUB/.claude/rules/new-rule.md" "$NODE/.claude/rules/new-rule.md"
  git -C "$NODE" add -A && git -C "$NODE" commit -q -m "manual copy"

  result=$(bash "$NODE/scripts/scaffold-sync.sh" pull-plan)

  echo "$result" | jq -e '.[] | select(.file == ".claude/rules/new-rule.md" and .action == "adopt-clean")'
}

@test "pull-plan: new file in scaffold + different local copy → adopt-conflict" {
  cd "$NODE"

  # Add file to hub
  cat > "$HUB/.claude/rules/new-rule.md" <<'EOF'
# New Rule
Hub version.
EOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "add new rule"

  # Create different local version
  cat > "$NODE/.claude/rules/new-rule.md" <<'EOF'
# New Rule
Local version with custom content.
EOF
  git -C "$NODE" add -A && git -C "$NODE" commit -q -m "local version"

  result=$(bash "$NODE/scripts/scaffold-sync.sh" pull-plan)

  echo "$result" | jq -e '.[] | select(.file == ".claude/rules/new-rule.md" and .action == "adopt-conflict")'
}

@test "pull-auto: adopt-clean files are tracked in lockfile" {
  cd "$NODE"

  # Add file to hub
  cat > "$HUB/.claude/rules/new-rule.md" <<'EOF'
# New Rule
Same content.
EOF
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "add new rule"

  # Copy identical file to node
  cp "$HUB/.claude/rules/new-rule.md" "$NODE/.claude/rules/new-rule.md"
  git -C "$NODE" add -A && git -C "$NODE" commit -q -m "manual copy"

  bash "$NODE/scripts/scaffold-sync.sh" pull-auto

  # Should now be in lockfile as clean
  status=$(jq -r '.files[".claude/rules/new-rule.md"].status' "$NODE/.claude/scaffold.lock")
  [ "$status" = "clean" ]
}


# =========================================================================
# bootstrap tests
# =========================================================================

@test "pre-check: bootstraps stale sync script from hub" {
  cd "$NODE"

  # Modify the hub's sync script (simulate newer version)
  echo '# updated' >> "$HUB/scripts/scaffold-sync.sh"
  git -C "$HUB" add -A && git -C "$HUB" commit -q -m "update sync script"

  # Node's script is now stale
  run bash "$NODE/scripts/scaffold-sync.sh" pre-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BOOTSTRAPPED"

  # Local script should now match hub
  local hub_h node_h
  hub_h=$(shasum -a 256 "$HUB/scripts/scaffold-sync.sh" | awk '{print $1}')
  node_h=$(shasum -a 256 "$NODE/scripts/scaffold-sync.sh" | awk '{print $1}')
  [ "$hub_h" = "$node_h" ]
}


# =========================================================================
# push-candidates tests
# =========================================================================

@test "push-candidates: clean files are not candidates" {
  cd "$NODE"
  result=$(bash "$NODE/scripts/scaffold-sync.sh" push-candidates)
  # All files should be clean from init, so no candidates
  [ "$(echo "$result" | jq 'length')" -eq 0 ]
}

@test "push-candidates: modified file is a candidate" {
  cd "$NODE"

  # Modify a tracked file locally
  echo "# Local improvement" >> "$NODE/.claude/rules/tdd.md"

  # Demote first to mark as modified
  bash "$NODE/scripts/scaffold-sync.sh" demote ".claude/rules/tdd.md"

  result=$(bash "$NODE/scripts/scaffold-sync.sh" push-candidates)
  echo "$result" | jq -e '.[] | select(.file == ".claude/rules/tdd.md" and .has_diff == true)'
}

@test "push-candidates: node-only files are excluded" {
  cd "$NODE"

  # Mark as node-only then modify
  bash "$NODE/scripts/scaffold-sync.sh" node-only ".claude/rules/tdd.md"
  echo "# Local only" >> "$NODE/.claude/rules/tdd.md"

  result=$(bash "$NODE/scripts/scaffold-sync.sh" push-candidates)
  count=$(echo "$result" | jq '[.[] | select(.file == ".claude/rules/tdd.md")] | length')
  [ "$count" -eq 0 ]
}

@test "push-candidates: specific file filter works" {
  cd "$NODE"

  # Demote two files
  bash "$NODE/scripts/scaffold-sync.sh" demote ".claude/rules/tdd.md"
  bash "$NODE/scripts/scaffold-sync.sh" demote ".claude/commands/catchup.md"

  result=$(bash "$NODE/scripts/scaffold-sync.sh" push-candidates ".claude/rules/tdd.md")
  count=$(echo "$result" | jq 'length')
  [ "$count" -eq 1 ]
  echo "$result" | jq -e '.[] | select(.file == ".claude/rules/tdd.md")'
}


# =========================================================================
# push-apply tests
# =========================================================================

@test "push-apply: copies file to scaffold and updates lockfile" {
  cd "$NODE"

  # Modify locally and demote
  echo "# Enhanced TDD" >> "$NODE/.claude/rules/tdd.md"
  bash "$NODE/scripts/scaffold-sync.sh" demote ".claude/rules/tdd.md"

  bash "$NODE/scripts/scaffold-sync.sh" push-apply ".claude/rules/tdd.md" "enhanced TDD rules"

  # File should be in scaffold
  grep -q "Enhanced TDD" "$HUB/.claude/rules/tdd.md"

  # Lockfile should be updated
  status=$(jq -r '.files[".claude/rules/tdd.md"].status' "$NODE/.claude/scaffold.lock")
  [ "$status" = "clean" ]
}


# =========================================================================
# promote tests
# =========================================================================

@test "promote: copies local-only file to scaffold with git commit" {
  cd "$NODE"

  # Create a new local file
  cat > "$NODE/.claude/rules/local-rule.md" <<'EOF'
# Local Rule

A useful rule.
EOF

  # Add to lockfile as local-only
  local h
  h=$(shasum -a 256 "$NODE/.claude/rules/local-rule.md" | awk '{print $1}')
  local tmp; tmp=$(mktemp)
  jq --arg f ".claude/rules/local-rule.md" --arg h "$h" \
    '.files[$f] = {"origin": "local", "scaffold_hash": null, "local_hash": $h, "status": "local-only", "sync": "tracked"}' \
    "$NODE/.claude/scaffold.lock" > "$tmp"
  mv "$tmp" "$NODE/.claude/scaffold.lock"

  bash "$NODE/scripts/scaffold-sync.sh" promote ".claude/rules/local-rule.md"

  # File should exist in scaffold
  [ -f "$HUB/.claude/rules/local-rule.md" ]
  grep -q "A useful rule" "$HUB/.claude/rules/local-rule.md"

  # Lockfile should show promoted
  status=$(jq -r '.files[".claude/rules/local-rule.md"].status' "$NODE/.claude/scaffold.lock")
  [ "$status" = "promoted" ]

  # Scaffold should have a new commit
  git -C "$HUB" log -1 --format='%s' | grep -q "local-rule"
}

@test "promote: skips already-clean files" {
  cd "$NODE"
  run bash "$NODE/scripts/scaffold-sync.sh" promote ".claude/rules/tdd.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "SKIP\|already"
}


# =========================================================================
# demote tests
# =========================================================================

@test "demote: marks clean file as modified" {
  cd "$NODE"

  status_before=$(jq -r '.files[".claude/rules/tdd.md"].status' "$NODE/.claude/scaffold.lock")
  [ "$status_before" = "clean" ]

  bash "$NODE/scripts/scaffold-sync.sh" demote ".claude/rules/tdd.md"

  status_after=$(jq -r '.files[".claude/rules/tdd.md"].status' "$NODE/.claude/scaffold.lock")
  [ "$status_after" = "modified" ]
}

@test "demote: rejects non-clean files" {
  cd "$NODE"
  # Demote first to make it modified
  bash "$NODE/scripts/scaffold-sync.sh" demote ".claude/rules/tdd.md"
  # Try to demote again
  run bash "$NODE/scripts/scaffold-sync.sh" demote ".claude/rules/tdd.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "already.*modified\|effectively demoted"
}


# =========================================================================
# Sync hardening: guard infrastructure (AC-5)
# =========================================================================

@test "guard_fail: exits with code 3 and GUARD_FAIL prefix" {
  cd "$NODE"
  # Source the script to access guard_fail directly, then call it
  run bash -c 'source "$1" --source-only 2>/dev/null; guard_fail "cp" ".claude/rules/tdd.md" "test reason"' _ "$NODE/scripts/scaffold-sync.sh"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "GUARD_FAIL: cp on .claude/rules/tdd.md: test reason"
}

# =========================================================================
# Sync hardening: jq validation guard (AC-3, AC-13)
# =========================================================================

@test "jq guard: invalid lockfile JSON triggers guard_fail before mv" {
  cd "$NODE"
  # Save original lockfile for comparison
  local original_hash
  original_hash=$(shasum -a 256 "$NODE/.claude/scaffold.lock" | awk '{print $1}')

  # Corrupt the lockfile to invalid JSON so jq output will be invalid
  echo "NOT JSON" > "$NODE/.claude/scaffold.lock"

  # Attempt a lock-update — should guard_fail because jq produces invalid output
  run bash "$NODE/scripts/scaffold-sync.sh" lock-update ".claude/rules/tdd.md" "status" "modified"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "GUARD_FAIL:"

  # Lockfile should still be the corrupted version (not replaced with jq garbage)
  [ "$(cat "$NODE/.claude/scaffold.lock")" = "NOT JSON" ]
}
