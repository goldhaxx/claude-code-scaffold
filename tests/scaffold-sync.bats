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

  # Create a non-markdown script (should NOT be treated as section-merge)
  cat > "$HUB/scripts/scaffold-sync.sh" <<'HUBEOF'
#!/usr/bin/env bash
# This script contains <!-- NODE-SPECIFIC-START --> as a literal string
echo "hello"
HUBEOF

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

  # Run init in node
  cd "$NODE"
  bash "$NODE/scripts/scaffold-sync.sh" init "$HUB"
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
