#!/usr/bin/env bats
# Tests for scripts/manifest-check.sh
#
# Each test creates isolated temp directories with mock README and files.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/manifest-check.sh"

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
| `scripts/foo.sh` | `./scripts/foo.sh` | Runs foo. | No. |
EOF

  run bash "$SCRIPT" parse "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].path == "scripts/foo.sh"'
}

@test "parse works on the real README" {
  run bash "$SCRIPT" parse "$BATS_TEST_DIRNAME/../README.md"
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
  mkdir -p "$REPO/.claude/rules" "$REPO/scripts"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "#!/bin/bash" > "$REPO/scripts/sync.sh"

  # Create a manifest with these paths
  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `scripts/sync.sh` | `./scripts/sync.sh` | Sync script. | No. |
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
| `scripts/gone.sh` | `./scripts/gone.sh` | Missing script. | No. |
EOF

  mkdir -p "$REPO/.claude/rules"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"

  run bash "$SCRIPT" check-existence "$REPO/README.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.found | length == 1'
  echo "$output" | jq -e '.missing_from_disk | length == 1'
  echo "$output" | jq -e '.missing_from_disk[0].path == "scripts/gone.sh"'
}

@test "check-existence discovers untracked files in tracked directories" {
  mkdir -p "$REPO/.claude/rules" "$REPO/scripts"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "# Extra" > "$REPO/.claude/rules/extra.md"
  echo "#!/bin/bash" > "$REPO/scripts/sync.sh"

  # Manifest only has tdd.md and sync.sh — extra.md is untracked
  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `scripts/sync.sh` | `./scripts/sync.sh` | Sync script. | No. |
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

@test "check-existence works on real README against real repo" {
  cd "$BATS_TEST_DIRNAME/.."
  run bash "$SCRIPT" check-existence README.md
  [ "$status" -eq 0 ]
  # All found entries should be real files
  found=$(echo "$output" | jq '.found | length')
  [ "$found" -gt 0 ]
  # Missing from disk should be zero or very few (reference files not in project)
  missing=$(echo "$output" | jq '.missing_from_disk | length')
  [ "$missing" -lt 10 ]
}


# =========================================================================
# Step 3: manifest.lock init + hash comparison
# =========================================================================

@test "init creates manifest.lock with correct structure" {
  mkdir -p "$REPO/.claude/rules" "$REPO/scripts"
  echo "# TDD" > "$REPO/.claude/rules/tdd.md"
  echo "#!/bin/bash" > "$REPO/scripts/sync.sh"
  git add -A && git commit -q -m "init"

  cat > "$REPO/README.md" <<'EOF'
| File | Copy to | What it does | Customize? |
|---|---|---|---|
| `.claude/rules/tdd.md` | `./.claude/rules/tdd.md` | TDD rules. | No. |
| `scripts/sync.sh` | `./scripts/sync.sh` | Sync script. | No. |
EOF

  run bash "$SCRIPT" init "$REPO/README.md"
  [ "$status" -eq 0 ]
  [ -f "$REPO/.claude/manifest.lock" ]

  # Check structure
  jq -e '.meta.last_verified' "$REPO/.claude/manifest.lock"
  jq -e '.meta.commit' "$REPO/.claude/manifest.lock"
  jq -e '.entries[".claude/rules/tdd.md"].file_hash' "$REPO/.claude/manifest.lock"
  jq -e '.entries["scripts/sync.sh"].file_hash' "$REPO/.claude/manifest.lock"
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
| `scripts/gone.sh` | `./scripts/gone.sh` | Missing. | No. |
EOF

  bash "$SCRIPT" init "$REPO/README.md"

  # tdd.md should be in entries, gone.sh should not
  jq -e '.entries[".claude/rules/tdd.md"]' "$REPO/.claude/manifest.lock"
  run jq -e '.entries["scripts/gone.sh"]' "$REPO/.claude/manifest.lock"
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
