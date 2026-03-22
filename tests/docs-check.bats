#!/usr/bin/env bats
# Tests for scripts/docs-check.sh
#
# Each test creates isolated temp directories with mock docs.
# Metadata lives in blockquote lines (> Key: value) after the heading.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/docs-check.sh"

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

TEMPLATES="$BATS_TEST_DIRNAME/../docs/templates"

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
