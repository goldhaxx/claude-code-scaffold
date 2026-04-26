#!/usr/bin/env bats
# BTS-22 — stasis history directory + checkpoint cleanup.
#
# Persists per-session stasis files in docs/sessions/<epoch>-<feature_id>.md
# so /stasis and /recall can read recent sessions without git archeology.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"
REPO_ROOT="$BATS_TEST_DIRNAME/../.."

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/docs"
}

teardown() {
  rm -rf "$PROJECT"
}

# Write a session-kind stasis at $1 with feature_id $2 and last-updated $3.
_write_stasis() {
  local path="$1"
  local feature_id="$2"
  local last_updated="$3"
  cat > "$path" <<EOF
# Stasis

> Feature: $feature_id
> Kind: session
> Last updated: $last_updated

## Accomplished

Test session.

## Determinism Review

- operations_reviewed: 0
- candidates_found: 0

No candidates this session.
EOF
}

# Write a feature-kind stasis with > Created: instead of > Last updated:.
_write_feature_stasis() {
  local path="$1"
  local feature_id="$2"
  local created="$3"
  cat > "$path" <<EOF
# Stasis

> Feature: $feature_id
> Kind: feature
> Created: $created
> Plan hash: abc123

## Accomplished

Test feature stasis.
EOF
}

# =========================================================================
# AC-1: archive-stasis happy path
# =========================================================================

@test "AC-1: archives docs/stasis.md to docs/sessions/<epoch>-<id>.md" {
  set -e
  _write_stasis "$PROJECT/docs/stasis.md" "session-test-feature" "1700000000"
  run bash "$SCRIPT" archive-stasis --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.archived == true'
  echo "$output" | jq -e '.path == "docs/sessions/1700000000-session-test-feature.md"'
  [ -f "$PROJECT/docs/sessions/1700000000-session-test-feature.md" ]
  # Byte-identical content.
  diff -q "$PROJECT/docs/stasis.md" "$PROJECT/docs/sessions/1700000000-session-test-feature.md"
}

@test "AC-1: feature-kind stasis with > Created: also archives" {
  set -e
  _write_feature_stasis "$PROJECT/docs/stasis.md" "bts-x-feature" "1750000000"
  run bash "$SCRIPT" archive-stasis --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.archived == true'
  [ -f "$PROJECT/docs/sessions/1750000000-bts-x-feature.md" ]
}

# =========================================================================
# AC-1 idempotency: identical content → no-op
# =========================================================================

@test "AC-1: idempotent — identical content emits archived:false" {
  set -e
  _write_stasis "$PROJECT/docs/stasis.md" "session-x" "1700000000"
  run bash "$SCRIPT" archive-stasis --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.archived == true'

  # Second call — same content.
  run bash "$SCRIPT" archive-stasis --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.archived == false'
  echo "$output" | jq -e '.reason == "already-archived"'
}

# =========================================================================
# AC-2: filename collision with non-identical content
# =========================================================================

@test "AC-2: collision with different content → non-zero exit" {
  set -e
  _write_stasis "$PROJECT/docs/stasis.md" "session-x" "1700000000"
  bash "$SCRIPT" archive-stasis --project-dir "$PROJECT" >/dev/null

  # Mutate docs/stasis.md so it differs from the archived copy, but keep
  # the same feature_id + last-updated so the destination filename collides.
  echo "EXTRA LINE — divergent content" >> "$PROJECT/docs/stasis.md"

  run bash "$SCRIPT" archive-stasis --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  # Error JSON should mention collision.
  [[ "$output" == *"collision"* ]] || [[ "$stderr" == *"collision"* ]]
}

# =========================================================================
# AC-3: missing/malformed input
# =========================================================================

@test "AC-3: missing docs/stasis.md → non-zero exit" {
  run --separate-stderr bash "$SCRIPT" archive-stasis --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"stasis"* ]]
}

@test "AC-3: stasis missing > Feature: → non-zero exit" {
  set -e
  cat > "$PROJECT/docs/stasis.md" <<EOF
# Stasis

> Last updated: 1700000000

## Accomplished

No feature line.
EOF
  run --separate-stderr bash "$SCRIPT" archive-stasis --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Feature"* || "$stderr" == *"feature"* ]]
}

@test "AC-3: stasis missing both > Last updated: and > Created: → non-zero exit" {
  set -e
  cat > "$PROJECT/docs/stasis.md" <<EOF
# Stasis

> Feature: session-x
> Kind: session

## Accomplished

No epoch.
EOF
  run --separate-stderr bash "$SCRIPT" archive-stasis --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Last updated"* || "$stderr" == *"Created"* || "$stderr" == *"epoch"* ]]
}

# =========================================================================
# AC-7: sessions-list
# =========================================================================

@test "AC-7: sessions-list returns sorted-newest-first JSON array" {
  set -e
  mkdir -p "$PROJECT/docs/sessions"
  _write_stasis "$PROJECT/docs/sessions/1700000000-session-a.md" "session-a" "1700000000"
  _write_stasis "$PROJECT/docs/sessions/1800000000-session-b.md" "session-b" "1800000000"
  _write_stasis "$PROJECT/docs/sessions/1750000000-session-c.md" "session-c" "1750000000"

  run bash "$SCRIPT" sessions-list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 3'
  echo "$output" | jq -e '.[0].epoch == 1800000000'
  echo "$output" | jq -e '.[1].epoch == 1750000000'
  echo "$output" | jq -e '.[2].epoch == 1700000000'
  echo "$output" | jq -e '.[0].feature_id == "session-b"'
  echo "$output" | jq -e '.[0].path == "docs/sessions/1800000000-session-b.md"'
}

@test "AC-7: --limit caps the number of returned entries" {
  set -e
  mkdir -p "$PROJECT/docs/sessions"
  for ts in 1700 1750 1800 1850 1900; do
    _write_stasis "$PROJECT/docs/sessions/${ts}000000-session-${ts}.md" "session-${ts}" "${ts}000000"
  done

  run bash "$SCRIPT" sessions-list --limit 3 --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 3'
  echo "$output" | jq -e '.[0].epoch == 1900000000'
}

@test "AC-7: empty docs/sessions/ → empty JSON array" {
  set -e
  mkdir -p "$PROJECT/docs/sessions"
  run bash "$SCRIPT" sessions-list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 0'
}

@test "AC-7: missing docs/sessions/ → empty JSON array (no error)" {
  set -e
  run bash "$SCRIPT" sessions-list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 0'
}

# =========================================================================
# AC-7: malformed-file resilience
# =========================================================================

@test "AC-7: malformed file is skipped with stderr warning, valid files returned" {
  set -e
  mkdir -p "$PROJECT/docs/sessions"
  _write_stasis "$PROJECT/docs/sessions/1700000000-valid.md" "valid" "1700000000"
  # Malformed: no metadata.
  echo "Just some text, no metadata." > "$PROJECT/docs/sessions/1750000000-bad.md"

  run --separate-stderr bash "$SCRIPT" sessions-list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # Only the valid file makes it into output.
  echo "$output" | jq -e 'length == 1'
  echo "$output" | jq -e '.[0].feature_id == "valid"'
  # Stderr warns about the bad file.
  [[ "$stderr" == *"bad.md"* ]] || [[ "$stderr" == *"malformed"* ]] || [[ "$stderr" == *"skip"* ]]
}

# =========================================================================
# AC-5: cmd_complete and cmd_land do NOT touch docs/sessions/
# =========================================================================

@test "AC-5: cmd_complete function body does not reference docs/sessions" {
  set -e
  local start end
  start=$(grep -n '^cmd_complete()' "$SCRIPT" | head -1 | cut -d: -f1)
  [ -n "$start" ]
  end=$(awk -v s="$start" 'NR > s && /^cmd_[a-z_]+\(\)/ { print NR; exit }' "$SCRIPT")
  [ -n "$end" ]
  ! sed -n "${start},${end}p" "$SCRIPT" | grep -q "docs/sessions"
}

@test "AC-5: cmd_land function body does not reference docs/sessions" {
  set -e
  local start end
  start=$(grep -n '^cmd_land()' "$SCRIPT" | head -1 | cut -d: -f1)
  [ -n "$start" ]
  end=$(awk -v s="$start" 'NR > s && /^cmd_[a-z_]+\(\)/ { print NR; exit }' "$SCRIPT")
  [ -n "$end" ]
  ! sed -n "${start},${end}p" "$SCRIPT" | grep -q "docs/sessions"
}

# =========================================================================
# AC-4: /stasis skill drift-guard
# =========================================================================

@test "AC-4: /stasis skill prose references archive-stasis after the stasis commit" {
  set -e
  local skill="$REPO_ROOT/.claude/skills/stasis/SKILL.md"
  [ -f "$skill" ]
  grep -F -q "archive-stasis" "$skill"
  # Position: archive-stasis must appear AFTER the docs: stasis commit line.
  local commit_line archive_line
  commit_line=$(grep -n 'commit -m "docs: stasis' "$skill" | head -1 | cut -d: -f1)
  archive_line=$(grep -n 'archive-stasis' "$skill" | head -1 | cut -d: -f1)
  [ -n "$commit_line" ]
  [ -n "$archive_line" ]
  [ "$archive_line" -gt "$commit_line" ]
}

# =========================================================================
# AC-8: /recall skill drift-guard
# =========================================================================

@test "AC-8: /recall skill prose references sessions-list with --limit 3" {
  set -e
  local skill="$REPO_ROOT/.claude/skills/recall/SKILL.md"
  [ -f "$skill" ]
  grep -F -q "sessions-list" "$skill"
  grep -F -q -- "--limit 3" "$skill"
}

@test "AC-8: /recall skill retains git-show fallback for fresh nodes" {
  set -e
  local skill="$REPO_ROOT/.claude/skills/recall/SKILL.md"
  # Either the original git show command or an explicit fallback note.
  grep -E "git show .*stasis\.md|fallback" "$skill" > /dev/null
}

# =========================================================================
# AC-9: checkpoint cleanup drift-guard
# =========================================================================

@test "AC-9: no active producer of docs/checkpoint.md outside legacy guards" {
  set -e
  # Whitelisted: cmd_legacy_refs_scan body (defensive scan pattern) and
  # cmd_migrate_stasis_artifact body (one-time downstream migration).
  # Search for write-shaped references: > docs/checkpoint, write to checkpoint, etc.
  local matches
  matches=$(grep -rln 'docs/checkpoint\.md' \
    "$REPO_ROOT/.claude/skills" \
    "$REPO_ROOT/.claude/commands" \
    "$REPO_ROOT/.claude/rules" \
    2>/dev/null || true)
  [ -z "$matches" ]
}

# =========================================================================
# AC-10: CLAUDE.md mentions docs/sessions/
# =========================================================================

@test "AC-10: CLAUDE.md Architecture section lists sessions/ archive" {
  set -e
  local claudemd="$REPO_ROOT/CLAUDE.md"
  [ -f "$claudemd" ]
  # Architecture section references sessions/ (tree-diagram form).
  grep -F -q "sessions/" "$claudemd"
  # And the same file references docs/ (sanity).
  grep -F -q "docs/" "$claudemd"
}
