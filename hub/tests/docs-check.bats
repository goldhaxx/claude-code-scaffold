#!/usr/bin/env bats
# Tests for scripts/docs-check.sh
#
# Each test creates isolated temp directories with mock docs.
# Metadata lives in blockquote lines (> Key: value) after the heading.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

# ---------------------------------------------------------------------------
# Fixtures: create mock docs directory
# ---------------------------------------------------------------------------

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  DOCS=$(mktemp -d)
}

teardown() {
  rm -rf "$DOCS"
}

# ---------------------------------------------------------------------------
# Helper: create a spec.md with lifecycle metadata
# ---------------------------------------------------------------------------
create_spec() {
  local feature_id="${1:-my-feature}"
  local created="${2:-1742860800}"
  local status="${3:-In Progress}"
  cat > "$DOCS/spec.md" <<EOF
# Feature: Test Feature

> Feature: ${feature_id}
> Created: ${created}
> Status: ${status}

## Summary

This is the spec body content.

## Acceptance Criteria

- [ ] AC-1: Something testable
EOF
}

# ---------------------------------------------------------------------------
# Helper: create a plan.md with lifecycle metadata
# ---------------------------------------------------------------------------
create_plan() {
  local feature_id="${1:-my-feature}"
  local created="${2:-1742860900}"
  local spec_hash="${3:-abcd1234}"
  cat > "$DOCS/plan.md" <<EOF
# Implementation Plan: Test Feature

> Feature: ${feature_id}
> Created: ${created}
> Spec hash: ${spec_hash}

## Objective

Implement the test feature.

## Sequence

### Step 1: Do the thing
EOF
}

# ---------------------------------------------------------------------------
# Helper: create a checkpoint.md with lifecycle metadata
# ---------------------------------------------------------------------------
create_checkpoint() {
  local feature_id="${1:-my-feature}"
  local updated="${2:-1742861000}"
  local plan_hash="${3:-efgh5678}"
  cat > "$DOCS/checkpoint.md" <<EOF
# Checkpoint

> Feature: ${feature_id}
> Last updated: ${updated}
> Plan hash: ${plan_hash}

## Accomplished

- Did something.

## Next Steps

- Do more.

## Determinism Review

- **operations_reviewed:** 2
- **candidates_found:** 0
- No candidates this session.
EOF
}

# ===========================================================================
# Step 1: status — metadata extraction
# ===========================================================================

@test "status: extracts feature_id and status from spec.md" {
  create_spec "my-feature" "1742860800" "In Progress"
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]

  # Parse spec entry from JSON output
  spec_feature=$(echo "$output" | jq -r '.spec.feature_id')
  spec_status=$(echo "$output" | jq -r '.spec.status')
  spec_created=$(echo "$output" | jq -r '.spec.created')

  [ "$spec_feature" = "my-feature" ]
  [ "$spec_status" = "In Progress" ]
  [ "$spec_created" = "1742860800" ]
}

@test "status: extracts feature_id and spec_hash from plan.md" {
  create_plan "my-feature" "1742860900" "abcd1234"
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]

  plan_feature=$(echo "$output" | jq -r '.plan.feature_id')
  plan_created=$(echo "$output" | jq -r '.plan.created')
  plan_spec_hash=$(echo "$output" | jq -r '.plan.spec_hash')

  [ "$plan_feature" = "my-feature" ]
  [ "$plan_created" = "1742860900" ]
  [ "$plan_spec_hash" = "abcd1234" ]
}

@test "status: extracts feature_id and plan_hash from checkpoint.md" {
  create_checkpoint "my-feature" "1742861000" "efgh5678"
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]

  cp_feature=$(echo "$output" | jq -r '.checkpoint.feature_id')
  cp_updated=$(echo "$output" | jq -r '.checkpoint.last_updated')
  cp_plan_hash=$(echo "$output" | jq -r '.checkpoint.plan_hash')

  [ "$cp_feature" = "my-feature" ]
  [ "$cp_updated" = "1742861000" ]
  [ "$cp_plan_hash" = "efgh5678" ]
}

@test "status: includes computed content_hash for each document" {
  create_spec "my-feature" "1742860800" "In Progress"
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]

  content_hash=$(echo "$output" | jq -r '.spec.content_hash')
  # Hash should be 8 hex chars (sha256 truncated)
  [[ "$content_hash" =~ ^[0-9a-f]{8}$ ]]
}

@test "status: reports missing documents without error" {
  # Empty docs dir — no files at all
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]

  spec_exists=$(echo "$output" | jq -r '.spec.exists')
  plan_exists=$(echo "$output" | jq -r '.plan.exists')
  cp_exists=$(echo "$output" | jq -r '.checkpoint.exists')

  [ "$spec_exists" = "false" ]
  [ "$plan_exists" = "false" ]
  [ "$cp_exists" = "false" ]
}

@test "status: reports unlinked when doc exists but has no metadata" {
  # Spec with no blockquote metadata
  cat > "$DOCS/spec.md" <<'EOF'
# Some Feature

## Summary

No metadata blockquote here.
EOF

  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]

  spec_exists=$(echo "$output" | jq -r '.spec.exists')
  spec_feature=$(echo "$output" | jq -r '.spec.feature_id')

  [ "$spec_exists" = "true" ]
  [ "$spec_feature" = "null" ]
}

@test "status: all three docs together produce complete JSON" {
  create_spec "my-feature" "1742860800" "In Progress"
  create_plan "my-feature" "1742860900" "abcd1234"
  create_checkpoint "my-feature" "1742861000" "efgh5678"

  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]

  # All three should exist and have feature_id
  spec_f=$(echo "$output" | jq -r '.spec.feature_id')
  plan_f=$(echo "$output" | jq -r '.plan.feature_id')
  cp_f=$(echo "$output" | jq -r '.checkpoint.feature_id')

  [ "$spec_f" = "my-feature" ]
  [ "$plan_f" = "my-feature" ]
  [ "$cp_f" = "my-feature" ]

  # All three should have content_hash
  spec_h=$(echo "$output" | jq -r '.spec.content_hash')
  plan_h=$(echo "$output" | jq -r '.plan.content_hash')
  cp_h=$(echo "$output" | jq -r '.checkpoint.content_hash')

  [[ "$spec_h" =~ ^[0-9a-f]{8}$ ]]
  [[ "$plan_h" =~ ^[0-9a-f]{8}$ ]]
  [[ "$cp_h" =~ ^[0-9a-f]{8}$ ]]
}

# ===========================================================================
# Step 2: content hashing — metadata vs body isolation
# ===========================================================================

@test "hash: changing metadata does not change content_hash" {
  create_spec "my-feature" "1742860800" "In Progress"
  run bash "$SCRIPT" status "$DOCS"
  hash_before=$(echo "$output" | jq -r '.spec.content_hash')

  # Change metadata only (status field)
  create_spec "my-feature" "1742860800" "Complete"
  run bash "$SCRIPT" status "$DOCS"
  hash_after=$(echo "$output" | jq -r '.spec.content_hash')

  [ "$hash_before" = "$hash_after" ]
}

@test "hash: changing body content changes content_hash" {
  create_spec "my-feature" "1742860800" "In Progress"
  run bash "$SCRIPT" status "$DOCS"
  hash_before=$(echo "$output" | jq -r '.spec.content_hash')

  # Append to body
  echo "## New Section" >> "$DOCS/spec.md"
  echo "Extra content that changes the hash." >> "$DOCS/spec.md"

  run bash "$SCRIPT" status "$DOCS"
  hash_after=$(echo "$output" | jq -r '.spec.content_hash')

  [ "$hash_before" != "$hash_after" ]
}

@test "hash: changing feature_id does not change content_hash" {
  create_spec "feature-a" "1742860800" "In Progress"
  run bash "$SCRIPT" status "$DOCS"
  hash_a=$(echo "$output" | jq -r '.spec.content_hash')

  create_spec "feature-b" "1742860800" "In Progress"
  run bash "$SCRIPT" status "$DOCS"
  hash_b=$(echo "$output" | jq -r '.spec.content_hash')

  [ "$hash_a" = "$hash_b" ]
}

@test "hash: changing timestamp does not change content_hash" {
  create_plan "my-feature" "1742860900" "abcd1234"
  run bash "$SCRIPT" status "$DOCS"
  hash_before=$(echo "$output" | jq -r '.plan.content_hash')

  create_plan "my-feature" "9999999999" "abcd1234"
  run bash "$SCRIPT" status "$DOCS"
  hash_after=$(echo "$output" | jq -r '.plan.content_hash')

  [ "$hash_before" = "$hash_after" ]
}

@test "hash: identical body across doc types produces same hash" {
  # Create spec and plan with identical body content
  cat > "$DOCS/spec.md" <<'EOF'
# Feature A

> Feature: test
> Created: 100

## Body

Same content here.
EOF

  cat > "$DOCS/plan.md" <<'EOF'
# Plan A

> Feature: test
> Created: 200
> Spec hash: abc

## Body

Same content here.
EOF

  run bash "$SCRIPT" status "$DOCS"
  spec_hash=$(echo "$output" | jq -r '.spec.content_hash')
  plan_hash=$(echo "$output" | jq -r '.plan.content_hash')

  [ "$spec_hash" = "$plan_hash" ]
}

# ===========================================================================
# Step 3: validate — aligned, stale, mismatched
# ===========================================================================

# Helper: create a fully linked set of docs with correct hashes
create_linked_docs() {
  create_spec "my-feature" "1742860800" "In Progress"

  # Compute spec's actual content hash for the plan
  local spec_hash
  spec_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.spec.content_hash')

  create_plan "my-feature" "1742860900" "$spec_hash"

  # Compute plan's actual content hash for the checkpoint
  local plan_hash
  plan_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.plan.content_hash')

  create_checkpoint "my-feature" "1742861000" "$plan_hash"
}

@test "validate: aligned when all hashes and feature_ids match" {
  create_linked_docs

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "aligned" ]
}

@test "validate: stale-plan when spec body changed after plan was written" {
  create_linked_docs

  # Modify spec body (not metadata)
  echo "## New requirement added" >> "$DOCS/spec.md"

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "stale-plan" ]
}

@test "validate: stale-checkpoint when plan body changed after checkpoint" {
  create_linked_docs

  # Modify plan body (not metadata)
  echo "### Step 99: New step" >> "$DOCS/plan.md"

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "stale-checkpoint" ]
}

@test "validate: mismatched when feature_ids differ" {
  create_spec "feature-a" "1742860800" "In Progress"
  create_plan "feature-b" "1742860900" "whatever"
  create_checkpoint "feature-c" "1742861000" "whatever"

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "mismatched" ]
}

@test "validate: stale-plan takes priority over stale-checkpoint" {
  create_linked_docs

  # Modify both spec and plan bodies
  echo "## Changed spec" >> "$DOCS/spec.md"
  echo "### Changed plan" >> "$DOCS/plan.md"

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  # stale-plan is more actionable (fix plan first, then checkpoint follows)
  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "stale-plan" ]
}

@test "validate: mismatched takes priority over stale" {
  create_spec "feature-a" "1742860800" "In Progress"

  local spec_hash
  spec_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.spec.content_hash')
  create_plan "feature-b" "1742860900" "$spec_hash"

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "mismatched" ]
}

# ===========================================================================
# Step 4: validate — missing docs and unlinked metadata
# ===========================================================================

@test "validate: only spec exists — reports plan and checkpoint missing" {
  create_spec "my-feature" "1742860800" "In Progress"

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  details=$(echo "$output" | jq -r '.details | join(", ")')
  [[ "$details" == *"plan.md missing"* ]]
  [[ "$details" == *"checkpoint.md missing"* ]]
}

@test "validate: all docs missing — reports all missing, no error" {
  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  details=$(echo "$output" | jq -r '.details | join(", ")')
  [[ "$details" == *"spec.md missing"* ]]
  [[ "$details" == *"plan.md missing"* ]]
  [[ "$details" == *"checkpoint.md missing"* ]]
}

@test "validate: doc exists but no metadata — reports unlinked" {
  cat > "$DOCS/spec.md" <<'EOF'
# Some Feature

No metadata here at all.
EOF
  cat > "$DOCS/plan.md" <<'EOF'
# Some Plan

No metadata here either.
EOF

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  details=$(echo "$output" | jq -r '.details | join(", ")')

  # Unlinked docs can't be validated — should report it
  [[ "$details" == *"unlinked"* ]] || [ "$result" = "unlinked" ]
}

@test "validate: spec + plan exist, checkpoint missing — still validates hashes" {
  create_spec "my-feature" "1742860800" "In Progress"
  local spec_hash
  spec_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.spec.content_hash')
  create_plan "my-feature" "1742860900" "$spec_hash"

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  details=$(echo "$output" | jq -r '.details | join(", ")')

  # Hashes match so far, but checkpoint is missing
  [[ "$details" == *"checkpoint.md missing"* ]]
  # Result should be aligned (what we can check is aligned)
  [ "$result" = "aligned" ]
}

# ===========================================================================
# Step 5: recommend — state machine
# ===========================================================================

@test "recommend: no docs → describe a feature" {
  run bash "$SCRIPT" recommend "$DOCS"
  [ "$status" -eq 0 ]

  action=$(echo "$output" | jq -r '.next_action')
  [[ "$action" == *"Describe a feature"* ]]
}

@test "recommend: spec only, no plan → run /plan" {
  create_spec "my-feature" "1742860800" "In Progress"

  run bash "$SCRIPT" recommend "$DOCS"
  [ "$status" -eq 0 ]

  action=$(echo "$output" | jq -r '.next_action')
  [[ "$action" == *"/plan"* ]]
}

@test "recommend: spec + plan linked, no checkpoint → ready to build" {
  create_spec "my-feature" "1742860800" "In Progress"
  local spec_hash
  spec_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.spec.content_hash')
  create_plan "my-feature" "1742860900" "$spec_hash"

  run bash "$SCRIPT" recommend "$DOCS"
  [ "$status" -eq 0 ]

  action=$(echo "$output" | jq -r '.next_action')
  [[ "$action" == *"build"* ]] || [[ "$action" == *"Build"* ]]
}

@test "recommend: stale-plan → re-run /plan" {
  create_spec "my-feature" "1742860800" "In Progress"
  local spec_hash
  spec_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.spec.content_hash')
  create_plan "my-feature" "1742860900" "$spec_hash"

  # Modify spec body to make plan stale
  echo "## New requirement" >> "$DOCS/spec.md"

  run bash "$SCRIPT" recommend "$DOCS"
  [ "$status" -eq 0 ]

  action=$(echo "$output" | jq -r '.next_action')
  [[ "$action" == *"/plan"* ]]
}

@test "recommend: all aligned with checkpoint → /clear and /catchup" {
  create_linked_docs

  run bash "$SCRIPT" recommend "$DOCS"
  [ "$status" -eq 0 ]

  action=$(echo "$output" | jq -r '.next_action')
  [[ "$action" == *"/clear"* ]] || [[ "$action" == *"/catchup"* ]] || [[ "$action" == *"Continue"* ]]
}

@test "recommend: mismatched → reconcile feature IDs" {
  create_spec "feature-a" "1742860800" "In Progress"
  create_plan "feature-b" "1742860900" "whatever"

  run bash "$SCRIPT" recommend "$DOCS"
  [ "$status" -eq 0 ]

  action=$(echo "$output" | jq -r '.next_action')
  reason=$(echo "$output" | jq -r '.reason')

  # Should indicate a problem to fix
  [[ "$reason" == *"mismatch"* ]] || [[ "$reason" == *"different"* ]]
}

@test "recommend: includes reason field" {
  create_spec "my-feature" "1742860800" "In Progress"

  run bash "$SCRIPT" recommend "$DOCS"
  [ "$status" -eq 0 ]

  reason=$(echo "$output" | jq -r '.reason')
  [ "$reason" != "null" ]
  [ -n "$reason" ]
}

# ===========================================================================
# Step 6: template metadata fields
# ===========================================================================

TEMPLATES="$BATS_TEST_DIRNAME/../../.ccanvil/templates"

@test "template: spec.md has Feature placeholder" {
  run grep -c "^> Feature: \[" "$TEMPLATES/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "template: spec.md uses epoch placeholder for Created" {
  run grep -c "^> Created: \[epoch\]" "$TEMPLATES/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "template: plan.md has Feature and Spec hash placeholders" {
  run grep -c "^> Feature: \[" "$TEMPLATES/plan.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run grep -c "^> Spec hash: \[" "$TEMPLATES/plan.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "template: plan.md uses epoch placeholder for Created" {
  run grep -c "^> Created: \[epoch\]" "$TEMPLATES/plan.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "template: checkpoint.md has Feature and Plan hash placeholders" {
  run grep -c "^> Feature: \[" "$TEMPLATES/checkpoint.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run grep -c "^> Plan hash: \[" "$TEMPLATES/checkpoint.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "template: checkpoint.md uses epoch placeholder for Last updated" {
  run grep -c "^> Last updated: \[epoch\]" "$TEMPLATES/checkpoint.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "template: checkpoint.md has pre-checkpoint reminder" {
  run grep -c "plan before checkpoint" "$TEMPLATES/checkpoint.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ===========================================================================
# Step 1: Checkpoint template — Determinism Review section (AC-1)
# ===========================================================================

@test "template: checkpoint.md has Determinism Review section" {
  run grep -c "^## Determinism Review" "$TEMPLATES/checkpoint.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "template: checkpoint.md has operations_reviewed field" {
  run grep -c "operations_reviewed" "$TEMPLATES/checkpoint.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "template: checkpoint.md has candidates_found field" {
  run grep -c "candidates_found" "$TEMPLATES/checkpoint.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ===========================================================================
# Step 2: validate — missing-determinism-review (AC-4)
# ===========================================================================

@test "validate: missing-determinism-review when checkpoint has no review section" {
  # Create linked docs, then replace checkpoint without review section
  create_linked_docs
  local plan_hash
  plan_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.plan.content_hash')
  cat > "$DOCS/checkpoint.md" <<EOF
# Checkpoint

> Feature: my-feature
> Last updated: 1742861000
> Plan hash: ${plan_hash}

## Accomplished

- Did something.

## Next Steps

- Do more.
EOF

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "missing-determinism-review" ]
}

@test "validate: aligned when checkpoint has Determinism Review section" {
  create_linked_docs

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "aligned" ]
}

@test "validate: missing-determinism-review when section exists but is empty" {
  # Create linked docs, then replace checkpoint with empty review section
  create_linked_docs
  local plan_hash
  plan_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.plan.content_hash')
  cat > "$DOCS/checkpoint.md" <<EOF
# Checkpoint

> Feature: my-feature
> Last updated: 1742861000
> Plan hash: ${plan_hash}

## Accomplished

- Did something.

## Determinism Review

EOF

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | jq -r '.result')
  [ "$result" = "missing-determinism-review" ]
}

@test "validate: missing-determinism-review has detail message" {
  # Create linked docs, then replace checkpoint without review section
  create_linked_docs
  local plan_hash
  plan_hash=$(bash "$SCRIPT" status "$DOCS" | jq -r '.plan.content_hash')
  cat > "$DOCS/checkpoint.md" <<EOF
# Checkpoint

> Feature: my-feature
> Last updated: 1742861000
> Plan hash: ${plan_hash}

## Accomplished

- Did something.
EOF

  run bash "$SCRIPT" validate "$DOCS"
  [ "$status" -eq 0 ]

  details=$(echo "$output" | jq -r '.details | join(", ")')
  [[ "$details" == *"determinism review"* ]] || [[ "$details" == *"Determinism Review"* ]]
}

# ===========================================================================
# Step 3: audit-session — basic pattern scanning (AC-5, AC-6)
# ===========================================================================

# Helper: create a git repo with commits containing stochastic patterns
create_audit_repo() {
  local repo
  repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"

  # Initial commit
  echo "echo hello" > "$repo/setup.sh"
  git -C "$repo" add setup.sh
  git -C "$repo" commit -q -m "initial commit"

  echo "$repo"
}

@test "audit-session: detects cp command in diff" {
  local repo
  repo=$(create_audit_repo)

  # Add a file with a manual cp command
  cat > "$repo/deploy.sh" <<'SCRIPT'
#!/bin/bash
cp src/config.json dist/config.json
echo "deployed"
SCRIPT
  git -C "$repo" add deploy.sh
  git -C "$repo" commit -q -m "add deploy script"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -ge 1 ]

  # Should find the cp pattern
  pattern=$(echo "$output" | jq -r '.patterns_found[0].pattern')
  [ "$pattern" = "cp" ]

  rm -rf "$repo"
}

@test "audit-session: detects multiple pattern types" {
  local repo
  repo=$(create_audit_repo)

  cat > "$repo/hack.sh" <<'SCRIPT'
#!/bin/bash
jq '.version' package.json
shasum -a 256 file.txt
git -C /other/repo status
SCRIPT
  git -C "$repo" add hack.sh
  git -C "$repo" commit -q -m "add hack script"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -ge 3 ]

  rm -rf "$repo"
}

@test "audit-session: outputs valid JSON with patterns_found and summary" {
  local repo
  repo=$(create_audit_repo)

  echo 'cp foo bar' > "$repo/task.sh"
  git -C "$repo" add task.sh
  git -C "$repo" commit -q -m "add task"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  # Validate JSON structure
  echo "$output" | jq -e '.patterns_found' > /dev/null
  echo "$output" | jq -e '.summary.total' > /dev/null
  echo "$output" | jq -e '.summary.by_category' > /dev/null

  rm -rf "$repo"
}

@test "audit-session: clean diff produces zero findings" {
  local repo
  repo=$(create_audit_repo)

  echo 'echo "no stochastic patterns here"' > "$repo/clean.sh"
  git -C "$repo" add clean.sh
  git -C "$repo" commit -q -m "add clean script"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -eq 0 ]

  patterns_count=$(echo "$output" | jq -r '.patterns_found | length')
  [ "$patterns_count" -eq 0 ]

  rm -rf "$repo"
}

@test "audit-session: each finding has pattern, file, line, context" {
  local repo
  repo=$(create_audit_repo)

  echo 'cp src/a.txt dst/a.txt' > "$repo/move.sh"
  git -C "$repo" add move.sh
  git -C "$repo" commit -q -m "add move"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  # Check fields on first finding
  echo "$output" | jq -e '.patterns_found[0].pattern' > /dev/null
  echo "$output" | jq -e '.patterns_found[0].file' > /dev/null
  echo "$output" | jq -e '.patterns_found[0].line' > /dev/null
  echo "$output" | jq -e '.patterns_found[0].context' > /dev/null

  rm -rf "$repo"
}

# ===========================================================================
# Step 4: audit-session --since flag (AC-7)
# ===========================================================================

@test "audit-session: --since flag limits scan range" {
  local repo
  repo=$(create_audit_repo)

  # Old commit with cp pattern
  echo 'cp old/a.txt old/b.txt' > "$repo/old.sh"
  git -C "$repo" add old.sh
  git -C "$repo" commit -q -m "old commit with cp"

  local midpoint
  midpoint=$(git -C "$repo" rev-parse HEAD)

  # New commit without patterns
  echo 'echo clean' > "$repo/new.sh"
  git -C "$repo" add new.sh
  git -C "$repo" commit -q -m "clean commit"

  # Scan only from midpoint — should NOT find the old cp
  run bash "$SCRIPT" audit-session --since "$midpoint" "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -eq 0 ]

  rm -rf "$repo"
}

# ===========================================================================
# Step 5: audit-session allowlist (AC-8)
# ===========================================================================

@test "audit-session: allowlists scripts/*.sh — no false positives" {
  local repo
  repo=$(create_audit_repo)

  # Create a scripts/ dir with patterns that should be allowlisted
  mkdir -p "$repo/.ccanvil/scripts"
  cat > "$repo/.ccanvil/scripts/sync.sh" <<'SCRIPT'
#!/bin/bash
cp "$hub_file" "$node_file"
jq '.status' lockfile.json
shasum -a 256 "$file"
git -C "$other_repo" status
SCRIPT
  git -C "$repo" add .ccanvil/scripts/sync.sh
  git -C "$repo" commit -q -m "add sync script"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -eq 0 ]

  rm -rf "$repo"
}

@test "audit-session: same patterns in non-script files ARE reported" {
  local repo
  repo=$(create_audit_repo)

  # Same patterns but in a non-scripts directory
  mkdir -p "$repo/.ccanvil/scripts"
  cat > "$repo/.ccanvil/scripts/sync.sh" <<'SCRIPT'
#!/bin/bash
cp "$hub_file" "$node_file"
SCRIPT
  cat > "$repo/deploy.sh" <<'SCRIPT'
#!/bin/bash
cp src/config.json dist/
SCRIPT
  git -C "$repo" add .ccanvil/scripts/sync.sh deploy.sh
  git -C "$repo" commit -q -m "add both"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -eq 1 ]

  file=$(echo "$output" | jq -r '.patterns_found[0].file')
  [ "$file" = "deploy.sh" ]

  rm -rf "$repo"
}

@test "audit-session: without --since defaults to last 10 commits" {
  local repo
  repo=$(create_audit_repo)

  echo 'cp a b' > "$repo/task.sh"
  git -C "$repo" add task.sh
  git -C "$repo" commit -q -m "add task"

  # No --since flag
  run bash "$SCRIPT" audit-session "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -ge 1 ]

  rm -rf "$repo"
}

# ===========================================================================
# Step 6: audit-session commit message scanning (AC-9)
# ===========================================================================

@test "audit-session: flags 'manually ran' in commit messages" {
  local repo
  repo=$(create_audit_repo)

  echo 'echo clean' > "$repo/clean.sh"
  git -C "$repo" add clean.sh
  git -C "$repo" commit -q -m "manually ran the deploy script to fix prod"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -ge 1 ]

  pattern=$(echo "$output" | jq -r '[.patterns_found[] | select(.pattern == "commit-message")] | length')
  [ "$pattern" -ge 1 ]

  rm -rf "$repo"
}

@test "audit-session: flags 'workaround' in commit messages" {
  local repo
  repo=$(create_audit_repo)

  echo 'echo ok' > "$repo/fix.sh"
  git -C "$repo" add fix.sh
  git -C "$repo" commit -q -m "workaround for missing script command"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -ge 1 ]

  rm -rf "$repo"
}

@test "audit-session: flags 'had to' in commit messages" {
  local repo
  repo=$(create_audit_repo)

  echo 'echo fixed' > "$repo/patch.sh"
  git -C "$repo" add patch.sh
  git -C "$repo" commit -q -m "had to copy the file manually because sync broke"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -ge 1 ]

  rm -rf "$repo"
}

# ===========================================================================
# Step 7: Workflow rule — checkpoint flow and checklist (AC-2, AC-3)
# ===========================================================================

RULES="$BATS_TEST_DIRNAME/../../.claude/rules"

@test "workflow: references determinism review via self-review.md" {
  run grep -c "Determinism review.*self-review" "$RULES/workflow.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "self-review: specifies mandatory Determinism Review section" {
  run grep -c "Determinism Review.*mandatory" "$RULES/self-review.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "self-review: has judgment criteria for flagging operations" {
  # Check for the key criteria from self-review.md
  run grep -c "computable\|script.*hook\|meaningful context" "$RULES/self-review.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "self-review: requires entry even when no candidates found" {
  run grep -c "No candidates" "$RULES/self-review.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ===========================================================================
# Step 8: Self-review.md update
# ===========================================================================

@test "self-review: references mandatory Determinism Review section" {
  run grep -c "Determinism Review" "$RULES/self-review.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "self-review: references the checkpoint template" {
  run grep -c "checkpoint.md\|checkpoint template" "$RULES/self-review.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ===========================================================================
# Step 9: /catchup integration (AC-10, AC-11)
# ===========================================================================

COMMANDS="$BATS_TEST_DIRNAME/../../.claude/commands"

@test "catchup: surfaces Determinism Review from checkpoint" {
  run grep -c "Determinism Review" "$COMMANDS/catchup.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "catchup: runs audit-session" {
  run grep -c "audit-session" "$COMMANDS/catchup.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ===========================================================================
# Step 10: Documentation — README and GUIDE
# ===========================================================================

README="$BATS_TEST_DIRNAME/../../README.md"
GUIDE="$BATS_TEST_DIRNAME/../../.ccanvil/guide/command-reference.md"

@test "readme: mentions audit-session in scripts description" {
  run grep -c "audit-session" "$README"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "guide: mentions audit-session in command reference" {
  run grep -c "audit-session" "$GUIDE"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "audit-session: clean commit messages produce no findings" {
  local repo
  repo=$(create_audit_repo)

  echo 'echo ok' > "$repo/feature.sh"
  git -C "$repo" add feature.sh
  git -C "$repo" commit -q -m "feat: add new feature implementation"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  total=$(echo "$output" | jq -r '.summary.total')
  [ "$total" -eq 0 ]

  rm -rf "$repo"
}


# =========================================================================
# idea management tests
# =========================================================================

@test "idea-add: creates ideas.md with UID and epoch timestamp" {
  [ ! -f "$DOCS/ideas.md" ]
  run bash "$SCRIPT" idea-add "test idea one" "$DOCS"
  [ "$status" -eq 0 ]
  [ -f "$DOCS/ideas.md" ]
  grep -q "test idea one" "$DOCS/ideas.md"
  grep -q "status:new" "$DOCS/ideas.md"
  # New format: - [ ] <4-hex-uid> <epoch>: text <!-- status:new -->
  grep -qE '^\- \[ \] [0-9a-f]{4} [0-9]+: test idea one <!-- status:new -->' "$DOCS/ideas.md"
}

@test "idea-add: appends to existing file" {
  echo "- [ ] a1b2 1776000000: first idea <!-- status:new -->" > "$DOCS/ideas.md"
  run bash "$SCRIPT" idea-add "second idea" "$DOCS"
  [ "$status" -eq 0 ]
  local count
  count=$(grep -c "status:" "$DOCS/ideas.md")
  [ "$count" -eq 2 ]
}

@test "idea-list: outputs JSON array with id and created fields" {
  cat > "$DOCS/ideas.md" <<'EOF'
# Ideas

- [ ] a1b2 1776000001: first idea <!-- status:new -->
- [x] c3d4 1776000002: second idea <!-- status:promoted -->
- [x] e5f6 1776000003: third idea <!-- status:dismissed -->
EOF
  run bash "$SCRIPT" idea-list "$DOCS"
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 3 ]
  # Check new fields: id and created
  local first_id first_created first_status
  first_id=$(echo "$output" | jq -r '.[0].id')
  first_created=$(echo "$output" | jq -r '.[0].created')
  first_status=$(echo "$output" | jq -r '.[0].status')
  [ "$first_id" = "a1b2" ]
  [ "$first_created" = "1776000001" ]
  [ "$first_status" = "new" ]
}

@test "idea-list: parses legacy date format (backwards compatible)" {
  cat > "$DOCS/ideas.md" <<'EOF'
# Ideas

- [ ] 2026-04-01: legacy idea <!-- status:new -->
- [x] c3d4 1776000002: new format idea <!-- status:promoted -->
EOF
  run bash "$SCRIPT" idea-list "$DOCS"
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
  # Legacy entry gets num-based id and date as created
  local legacy_id legacy_created
  legacy_id=$(echo "$output" | jq -r '.[0].id')
  legacy_created=$(echo "$output" | jq -r '.[0].created')
  [ "$legacy_id" = "1" ]
  [ "$legacy_created" = "2026-04-01" ]
  # New format entry has proper uid and epoch
  local new_id new_created
  new_id=$(echo "$output" | jq -r '.[1].id')
  new_created=$(echo "$output" | jq -r '.[1].created')
  [ "$new_id" = "c3d4" ]
  [ "$new_created" = "1776000002" ]
}

@test "idea-list: filters by status" {
  cat > "$DOCS/ideas.md" <<'EOF'
# Ideas

- [ ] a1b2 1776000001: first idea <!-- status:new -->
- [x] c3d4 1776000002: second idea <!-- status:promoted -->
- [ ] e5f6 1776000003: third idea <!-- status:new -->
EOF
  run bash "$SCRIPT" idea-list --status new "$DOCS"
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "idea-count: returns correct totals" {
  cat > "$DOCS/ideas.md" <<'EOF'
# Ideas

- [ ] a1b2 1776000001: alpha <!-- status:new -->
- [ ] c3d4 1776000002: beta <!-- status:new -->
- [x] e5f6 1776000003: gamma <!-- status:promoted -->
- [x] 1a2b 1776000004: delta <!-- status:dismissed -->
- [x] 3c4d 1776000005: epsilon <!-- status:merged:BTS-99 -->
EOF
  run bash "$SCRIPT" idea-count "$DOCS"
  [ "$status" -eq 0 ]
  local total new promoted dismissed
  total=$(echo "$output" | jq '.total')
  new=$(echo "$output" | jq '.new')
  promoted=$(echo "$output" | jq '.promoted')
  dismissed=$(echo "$output" | jq '.dismissed')
  [ "$total" -eq 5 ]
  [ "$new" -eq 2 ]
  [ "$promoted" -eq 1 ]
  [ "$dismissed" -eq 1 ]
}

@test "idea-update: updates by UID" {
  cat > "$DOCS/ideas.md" <<'EOF'
# Ideas

- [ ] a1b2 1776000001: first idea <!-- status:new -->
- [ ] c3d4 1776000002: second idea <!-- status:new -->
EOF
  run bash "$SCRIPT" idea-update c3d4 promoted "$DOCS"
  [ "$status" -eq 0 ]
  grep -q "\[x\].*c3d4.*second idea.*status:promoted" "$DOCS/ideas.md"
  grep -q "\[ \].*a1b2.*first idea.*status:new" "$DOCS/ideas.md"
}

@test "idea-update: falls back to numeric index" {
  cat > "$DOCS/ideas.md" <<'EOF'
# Ideas

- [ ] a1b2 1776000001: first idea <!-- status:new -->
- [ ] c3d4 1776000002: second idea <!-- status:new -->
EOF
  run bash "$SCRIPT" idea-update 2 promoted "$DOCS"
  [ "$status" -eq 0 ]
  grep -q "\[x\].*second idea.*status:promoted" "$DOCS/ideas.md"
  grep -q "\[ \].*first idea.*status:new" "$DOCS/ideas.md"
}

@test "idea-update: nonexistent UID exits with error" {
  cat > "$DOCS/ideas.md" <<'EOF'
# Ideas

- [ ] a1b2 1776000001: first idea <!-- status:new -->
EOF
  run bash "$SCRIPT" idea-update zzzz promoted "$DOCS"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not found"
}

@test "idea-count: empty file returns all zeros" {
  run bash "$SCRIPT" idea-count "$DOCS"
  [ "$status" -eq 0 ]
  local total
  total=$(echo "$output" | jq '.total')
  [ "$total" -eq 0 ]
}


# =========================================================================
# radar-gather tests
# =========================================================================

@test "radar-gather: outputs valid JSON with required fields" {
  run bash "$SCRIPT" radar-gather "$DOCS"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("active_spec")' >/dev/null
  echo "$output" | jq -e 'has("completed_recent")' >/dev/null
  echo "$output" | jq -e 'has("ideas")' >/dev/null
  echo "$output" | jq -e 'has("roadmap")' >/dev/null
  echo "$output" | jq -e 'has("backlog")' >/dev/null
}

@test "radar-gather: includes active spec when present" {
  create_spec "test-feat" "1742860800" "In Progress"
  run bash "$SCRIPT" radar-gather "$DOCS"
  [ "$status" -eq 0 ]
  local fid
  fid=$(echo "$output" | jq -r '.active_spec.feature_id')
  [ "$fid" = "test-feat" ]
}

@test "radar-gather: includes roadmap active theme" {
  mkdir -p "$DOCS"
  cat > "$DOCS/roadmap.md" <<'EOF'
# Roadmap

## Vision
Build great things.

## Active Theme
Infrastructure hardening

## Up Next
1. Feature X
EOF
  run bash "$SCRIPT" radar-gather "$DOCS"
  [ "$status" -eq 0 ]
  local theme
  theme=$(echo "$output" | jq -r '.roadmap.active_theme')
  [ "$theme" = "Infrastructure hardening" ]
}

@test "radar-gather: handles missing roadmap gracefully" {
  run bash "$SCRIPT" radar-gather "$DOCS"
  [ "$status" -eq 0 ]
  local exists
  exists=$(echo "$output" | jq -r '.roadmap.exists')
  [ "$exists" = "false" ]
}

@test "radar-gather: includes idea counts" {
  mkdir -p "$DOCS"
  cat > "$DOCS/ideas.md" <<'EOF'
# Ideas

- [ ] 2026-04-01: idea one <!-- status:new -->
- [ ] 2026-04-02: idea two <!-- status:new -->
EOF
  run bash "$SCRIPT" radar-gather "$DOCS"
  [ "$status" -eq 0 ]
  local new_count
  new_count=$(echo "$output" | jq '.ideas.new')
  [ "$new_count" -eq 2 ]
}

# ===========================================================================
# YAML frontmatter metadata parsing
# ===========================================================================

@test "status: extracts metadata from YAML frontmatter spec" {
  cat > "$DOCS/spec.md" <<'EOF'
---
Feature: yaml-feature
Created: 1742860800
Status: In Progress
---

## Summary

This spec uses YAML frontmatter.
EOF
  run bash "$SCRIPT" status "$DOCS"
  [ "$status" -eq 0 ]

  spec_feature=$(echo "$output" | jq -r '.spec.feature_id')
  spec_status=$(echo "$output" | jq -r '.spec.status')
  spec_created=$(echo "$output" | jq -r '.spec.created')

  [ "$spec_feature" = "yaml-feature" ]
  [ "$spec_status" = "In Progress" ]
  [ "$spec_created" = "1742860800" ]
}
