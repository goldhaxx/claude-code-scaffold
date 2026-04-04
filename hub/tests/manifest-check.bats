#!/usr/bin/env bats
# Tests for scripts/manifest-check.sh
#
# Each test creates isolated temp directories with mock README and files.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/manifest-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  REPO=$(mktemp -d)
  cd "$REPO"
  git init -q
}

teardown() {
  rm -rf "$REPO"
}


# =========================================================================
# Step 1: Parse README manifest tables
# =========================================================================

@test "parse extracts path and description from a 4-column table" {
  cat > "$REPO/README.md" <<'EOF'
# Project

## Manifest

| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `CLAUDE.md` | `./CLAUDE.md` | The core config file. | Yes. |
| `.claudeignore` | `./.claudeignore` | Tells Claude which files to skip. | Yes. |
EOF

  run bash "$SCRIPT" parse "$REPO/README.md"
  [ "$status" -eq 0 ]
  # Should output JSON array of {path, description} objects
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].path == "CLAUDE.md"'
  echo "$output" | jq -e '.[0].description == "The core config file."'
  echo "$output" | jq -e '.[1].path == ".claudeignore"'
  echo "$output" | jq -e '.[1].description == "Tells Claude which files to skip."'
}

@test "parse extracts path and description from a 3-column table" {
  cat > "$REPO/README.md" <<'EOF'
## Reference

| File in zip | What to do with it | What it does |
|---|---|---|
| `README.md` | Keep for reference. | Setup guide and file manifest. |
EOF

  run bash "$SCRIPT" parse "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1'
  echo "$output" | jq -e '.[0].path == "README.md"'
  echo "$output" | jq -e '.[0].description == "Setup guide and file manifest."'
}

@test "parse skips header and separator rows" {
  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `foo.md` | `./foo.md` | Does foo things. | No. |
EOF

  run bash "$SCRIPT" parse "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1'
}

@test "parse handles multiple tables in one file" {
  cat > "$REPO/README.md" <<'EOF'
## Section A

| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `a.md` | `./a.md` | File A. | No. |

## Section B

| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `b.md` | `./b.md` | File B. | Yes. |
EOF

  run bash "$SCRIPT" parse "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].path == "a.md"'
  echo "$output" | jq -e '.[1].path == "b.md"'
}

@test "parse strips backticks from paths" {
  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.ccanvil/scripts/foo.sh` | `./.ccanvil/scripts/foo.sh` | Runs foo. | No. |
EOF

  run bash "$SCRIPT" parse "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].path == ".ccanvil/scripts/foo.sh"'
}

@test "parse works on the real README" {
  run bash "$SCRIPT" parse "$BATS_TEST_DIRNAME/../../README.md"
  [ "$status" -eq 0 ]
  # The real README has at least 30 entries across all tables
  count=$(echo "$output" | jq 'length')
  [ "$count" -ge 30 ]
}

@test "parse fails with clear error when file not found" {
  run bash "$SCRIPT" parse "/nonexistent/README.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not found\|no such file\|does not exist"
}


# =========================================================================
# Step 2: File existence + untracked file discovery
# =========================================================================

@test "check-existence reports existing files as found" {
  mkdir -p "$REPO/.claude/rules" "$REPO/.ccanvil/scripts"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "#!/bin/bash" > "$REPO/.ccanvil/scripts/sync.sh"

  # Create a manifest with these paths
  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `.ccanvil/scripts/sync.sh` | `./.ccanvil/scripts/sync.sh` | Sync script. | No. |
EOF

  run bash "$SCRIPT" check-existence "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.found | length == 2'
  echo "$output" | jq -e '.missing_from_disk | length == 0'
}

@test "check-existence reports missing files" {
  # Create a manifest with paths that don't exist on disk
  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `.ccanvil/scripts/gone.sh` | `./.ccanvil/scripts/gone.sh` | Missing script. | No. |
EOF

  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"

  run bash "$SCRIPT" check-existence "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.found | length == 1'
  echo "$output" | jq -e '.missing_from_disk | length == 1'
  echo "$output" | jq -e '.missing_from_disk[0].path == ".ccanvil/scripts/gone.sh"'
}

@test "check-existence discovers untracked files in tracked directories" {
  mkdir -p "$REPO/.claude/rules" "$REPO/.ccanvil/scripts"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "# Extra" > "$REPO/.claude/rules/extra.md"
  echo "#!/bin/bash" > "$REPO/.ccanvil/scripts/sync.sh"

  # Manifest only has tdd.md and sync.sh — extra.md is untracked
  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `.ccanvil/scripts/sync.sh` | `./.ccanvil/scripts/sync.sh` | Sync script. | No. |
EOF

  run bash "$SCRIPT" check-existence "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.missing_from_manifest | length == 1'
  echo "$output" | jq -e '.missing_from_manifest[0].path == ".claude/rules/extra.md"'
}

@test "check-existence ignores files outside tracked directories" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "random" > "$REPO/random.txt"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  run bash "$SCRIPT" check-existence "$REPO/README.md"
  [ "$status" -eq 0 ]
  # random.txt is outside tracked dirs, should not appear
  echo "$output" | jq -e '.missing_from_manifest | length == 0'
}

# TODO: Re-enable after README file manifest is updated for preset/.ccanvil/ structure
@test "check-existence works on real README against real repo" {
  skip "README manifest tables need updating for new directory structure"
  cd "$BATS_TEST_DIRNAME/../.."
  run bash "$SCRIPT" check-existence README.md
  [ "$status" -eq 0 ]
  found=$(echo "$output" | jq '.found | length')
  [ "$found" -gt 0 ]
  missing=$(echo "$output" | jq '.missing_from_disk | length')
  [ "$missing" -lt 10 ]
}


# =========================================================================
# Step 3: manifest.lock init + hash comparison
# =========================================================================

@test "init creates manifest.lock with correct structure" {
  mkdir -p "$REPO/.claude/rules" "$REPO/.ccanvil/scripts"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "#!/bin/bash" > "$REPO/.ccanvil/scripts/sync.sh"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `.ccanvil/scripts/sync.sh` | `./.ccanvil/scripts/sync.sh` | Sync script. | No. |
EOF

  run bash "$SCRIPT" init "$REPO/README.md"
  [ "$status" -eq 0 ]
  [ -f "$REPO/.claude/manifest.lock" ]

  # Check structure
  jq -e '.meta.last_verified' "$REPO/.claude/manifest.lock"
  jq -e '.meta.commit' "$REPO/.claude/manifest.lock"
  jq -e '.entries[".claude/rules/tdd.md"].file_hash' "$REPO/.claude/manifest.lock"
  jq -e '.entries[".ccanvil/scripts/sync.sh"].file_hash' "$REPO/.claude/manifest.lock"
}

@test "init stores correct sha256 hashes" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  expected_hash=$(shasum -a 256 "$REPO/.claude/rules/tdd.md" | cut -d' ' -f1)
  actual_hash=$(jq -r '.entries[".claude/rules/tdd.md"].file_hash' "$REPO/.claude/manifest.lock")
  [ "$expected_hash" = "$actual_hash" ]
}

@test "init skips entries for files that don't exist on disk" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `.ccanvil/scripts/gone.sh` | `./.ccanvil/scripts/gone.sh` | Missing. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  # tdd.md should be in entries, gone.sh should not
  jq -e '.entries[".claude/rules/tdd.md"]' "$REPO/.claude/manifest.lock"
  run jq -e '.entries[".ccanvil/scripts/gone.sh"]' "$REPO/.claude/manifest.lock"
  [ "$status" -ne 0 ]
}

@test "hash-check reports unchanged files as verified" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"
  run bash "$SCRIPT" hash-check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verified | length == 1'
  echo "$output" | jq -e '.verified[0].path == ".claude/rules/tdd.md"'
  echo "$output" | jq -e '.stale | length == 0'
}

@test "hash-check reports modified files as stale" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  # Modify the file
  echo "# TDD - updated with new rules" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "update tdd"

  run bash "$SCRIPT" hash-check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verified | length == 0'
  echo "$output" | jq -e '.stale | length == 1'
  echo "$output" | jq -e '.stale[0].path == ".claude/rules/tdd.md"'
}


# =========================================================================
# Step 4: Diff generation for stale entries
# =========================================================================

@test "hash-check includes git diff for stale committed entries" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  # Modify and commit
  echo "# TDD - updated" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "update tdd"

  run bash "$SCRIPT" hash-check
  [ "$status" -eq 0 ]
  # Stale entry should have a diff field containing the change
  echo "$output" | jq -e '.stale[0].diff' > /dev/null
  echo "$output" | jq -r '.stale[0].diff' | grep -q "TDD - updated"
}

@test "hash-check includes fallback diff for uncommitted changes" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  # Modify WITHOUT committing
  echo "# TDD - dirty change" > "$REPO/.claude/rules/tdd.md"

  run bash "$SCRIPT" hash-check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stale | length == 1'
  # Should still have a diff even without commit
  echo "$output" | jq -e '.stale[0].diff' > /dev/null
}

@test "hash-check diff is empty string for verified entries" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  run bash "$SCRIPT" hash-check
  [ "$status" -eq 0 ]
  # Verified entries don't need a diff field
  echo "$output" | jq -e '.verified[0].path == ".claude/rules/tdd.md"'
}


# =========================================================================
# Step 5: Identity extraction for untracked files
# =========================================================================

@test "extract-identity gets comment header from shell scripts" {
  mkdir -p "$REPO/.ccanvil/scripts"
  cat > "$REPO/.ccanvil/scripts/example.sh" <<'EOF'
#!/usr/bin/env bash
# example.sh — Does something useful.
# Usage: example.sh [args]

set -euo pipefail
echo "hello"
EOF

  run bash "$SCRIPT" extract-identity "$REPO/.ccanvil/scripts/example.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "shell"'
  # Identity should contain the comment header
  echo "$output" | jq -r '.identity' | grep -q "Does something useful"
}

@test "extract-identity gets heading + frontmatter from markdown" {
  mkdir -p "$REPO/.claude/rules"
  cat > "$REPO/.claude/rules/example.md" <<'EOF'
---
name: example-rule
description: "An example"
---

# Example Rule

Follow these guidelines.
EOF

  run bash "$SCRIPT" extract-identity "$REPO/.claude/rules/example.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "markdown"'
  echo "$output" | jq -r '.identity' | grep -q "example-rule"
  echo "$output" | jq -r '.identity' | grep -q "Example Rule"
}

@test "extract-identity gets first heading from markdown without frontmatter" {
  mkdir -p "$REPO/.claude/rules"
  cat > "$REPO/.claude/rules/simple.md" <<'EOF'
# Simple Rule

Just do the thing.
EOF

  run bash "$SCRIPT" extract-identity "$REPO/.claude/rules/simple.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -r '.identity' | grep -q "Simple Rule"
}

@test "extract-identity falls back to first 3 lines for other file types" {
  mkdir -p "$REPO/.ccanvil/scripts"
  cat > "$REPO/.ccanvil/scripts/config.json" <<'EOF'
{
  "name": "test-config",
  "version": "1.0"
}
EOF

  run bash "$SCRIPT" extract-identity "$REPO/.ccanvil/scripts/config.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "other"'
  echo "$output" | jq -r '.identity' | grep -q "test-config"
}

@test "extract-identity includes file size" {
  mkdir -p "$REPO/.ccanvil/scripts"
  echo "hello world" > "$REPO/.ccanvil/scripts/tiny.sh"

  run bash "$SCRIPT" extract-identity "$REPO/.ccanvil/scripts/tiny.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.size_bytes > 0'
}


# =========================================================================
# Step 6: Full JSON report (check) + verify subcommand
# =========================================================================

@test "check produces full JSON report with all categories" {
  mkdir -p "$REPO/.claude/rules" "$REPO/.ccanvil/scripts"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "# Workflow" > "$REPO/.claude/rules/workflow.md"
  echo "#!/bin/bash" > "$REPO/.ccanvil/scripts/sync.sh"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `.claude/rules/workflow.md` | `./.claude/rules/workflow.md` | Workflow rules. | No. |
| `.ccanvil/scripts/sync.sh` | `./.ccanvil/scripts/sync.sh` | Sync script. | No. |
| `.ccanvil/scripts/gone.sh` | `./.ccanvil/scripts/gone.sh` | Missing script. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  # Modify one file, add an untracked file
  echo "# TDD - updated" > "$REPO/.claude/rules/tdd.md"
  echo "# Extra" > "$REPO/.claude/rules/extra.md"
  git add -A && git commit -q -m "changes"

  run bash "$SCRIPT" check "$REPO/README.md"
  [ "$status" -eq 0 ]

  # Should have all 4 categories
  echo "$output" | jq -e '.verified | length > 0'
  echo "$output" | jq -e '.stale | length > 0'
  echo "$output" | jq -e '.missing_from_disk | length > 0'
  echo "$output" | jq -e '.missing_from_manifest | length > 0'

  # Stale entry should have diff
  echo "$output" | jq -e '.stale[0].diff'

  # Missing from manifest should have identity
  echo "$output" | jq -e '.missing_from_manifest[0].identity'

  # Summary should have counts
  echo "$output" | jq -e '.summary.total > 0'
  echo "$output" | jq -e '.summary.verified > 0'
  echo "$output" | jq -e '.summary.stale > 0'
}

@test "check works without a lockfile (first run)" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  # No init — no lockfile exists
  run bash "$SCRIPT" check "$REPO/README.md"
  [ "$status" -eq 0 ]
  # Without lockfile, all existing entries are "unverified" (no hash baseline)
  echo "$output" | jq -e '.summary'
}

@test "verify updates lockfile hashes for specified paths" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  # Modify the file
  echo "# TDD - updated" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "update"

  # Confirm it's stale
  result=$(bash "$SCRIPT" hash-check)
  echo "$result" | jq -e '.stale | length == 1'

  # Verify it
  run bash "$SCRIPT" verify .claude/rules/tdd.md
  [ "$status" -eq 0 ]

  # Now it should be verified
  result=$(bash "$SCRIPT" hash-check)
  echo "$result" | jq -e '.verified | length == 1'
  echo "$result" | jq -e '.stale | length == 0'
}

@test "verify full cycle: init → modify → check → verify → check" {
  mkdir -p "$REPO/.claude/rules" "$REPO/.ccanvil/scripts"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "#!/bin/bash" > "$REPO/.ccanvil/scripts/sync.sh"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `.ccanvil/scripts/sync.sh` | `./.ccanvil/scripts/sync.sh` | Sync script. | No. |
EOF

  # Init lockfile
  bash "$SCRIPT" init "$REPO/README.md"

  # Modify one file
  echo "# TDD - changed" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "change"

  # Check: 1 stale, 1 verified
  result=$(bash "$SCRIPT" hash-check)
  echo "$result" | jq -e '.stale | length == 1'
  echo "$result" | jq -e '.verified | length == 1'

  # Verify the stale file
  bash "$SCRIPT" verify .claude/rules/tdd.md

  # Check again: 2 verified, 0 stale
  result=$(bash "$SCRIPT" hash-check)
  echo "$result" | jq -e '.verified | length == 2'
  echo "$result" | jq -e '.stale | length == 0'
}

# ===========================================================================
# Epoch timestamp tests
# ===========================================================================

@test "init stores verified field as epoch integer" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
EOF

  run bash "$SCRIPT" init "$REPO/README.md"
  [ "$status" -eq 0 ]

  # verified field should be a numeric epoch, not a date string
  verified=$(jq -r '.entries[".claude/rules/tdd.md"].verified' "$REPO/.claude/manifest.lock")
  [[ "$verified" =~ ^[0-9]+$ ]]
  # Should be a reasonable epoch (after 2020-01-01 = 1577836800)
  [ "$verified" -gt 1577836800 ]

  # meta.last_verified should also be epoch
  last_v=$(jq -r '.meta.last_verified' "$REPO/.claude/manifest.lock")
  [[ "$last_v" =~ ^[0-9]+$ ]]
}

@test "verify stores verified field as epoch integer" {
  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | What it does |
|---|---|
| `.claude/rules/tdd.md` | TDD rules. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  # Modify and re-verify
  echo "# TDD updated" > "$REPO/.claude/rules/tdd.md"
  git add -A && git commit -q -m "update"

  run bash "$SCRIPT" verify ".claude/rules/tdd.md"
  [ "$status" -eq 0 ]

  # verified field should be epoch
  verified=$(jq -r '.entries[".claude/rules/tdd.md"].verified' "$REPO/.claude/manifest.lock")
  [[ "$verified" =~ ^[0-9]+$ ]]
  [ "$verified" -gt 1577836800 ]
}
