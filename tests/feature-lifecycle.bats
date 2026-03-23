#!/usr/bin/env bats
# Tests for branch-based feature lifecycle
#
# Covers: scaffold config, list-specs, activate, complete, validate/recommend
# multi-spec, hooks, and worktree compatibility.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/docs-check.sh"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)

  # Initialize a git repo so branch operations work
  git -C "$PROJECT" init -q
  git -C "$PROJECT" config user.email "test@test.com"
  git -C "$PROJECT" config user.name "Test"

  # Create minimal project structure
  mkdir -p "$PROJECT/docs/specs"
  mkdir -p "$PROJECT/.claude"

  # Copy the real script
  cp "$SCRIPT" "$PROJECT/scripts/docs-check.sh" 2>/dev/null || {
    mkdir -p "$PROJECT/scripts"
    cp "$SCRIPT" "$PROJECT/scripts/docs-check.sh"
  }
  chmod +x "$PROJECT/scripts/docs-check.sh"

  # Initial commit so we have a branch
  touch "$PROJECT/.gitkeep"
  git -C "$PROJECT" add -A
  git -C "$PROJECT" commit -q -m "init"
}

teardown() {
  rm -rf "$PROJECT"
}

# ---------------------------------------------------------------------------
# Step 1: Scaffold config (AC-14, AC-15)
# ---------------------------------------------------------------------------

@test "scaffold-config: reads feature toggle from scaffold.json" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features": {"pr_review": true}}
EOF
  run "$PROJECT/scripts/docs-check.sh" config-get pr_review "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "scaffold-config: returns false for missing key" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features": {"pr_review": true}}
EOF
  run "$PROJECT/scripts/docs-check.sh" config-get nonexistent "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "scaffold-config: returns false when scaffold.json missing" {
  # No scaffold.json created
  run "$PROJECT/scripts/docs-check.sh" config-get pr_review "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "scaffold-config: returns false when scaffold.json is empty object" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{}
EOF
  run "$PROJECT/scripts/docs-check.sh" config-get pr_review "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

# ---------------------------------------------------------------------------
# Step 2: list-specs (AC-1, AC-4)
# ---------------------------------------------------------------------------

@test "list-specs: returns JSON array with spec metadata" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Draft

## Summary
Auth feature.
EOF
  run "$PROJECT/scripts/docs-check.sh" list-specs "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].feature_id == "auth-system"'
  echo "$output" | jq -e '.[0].status == "Draft"'
  echo "$output" | jq -e '.[0].created == "1774200000"'
}

@test "list-specs: returns multiple specs sorted" {
  cat > "$PROJECT/docs/specs/alpha.md" <<'EOF'
# Feature: Alpha

> Feature: alpha
> Created: 1774200000
> Status: Ready
EOF
  cat > "$PROJECT/docs/specs/beta.md" <<'EOF'
# Feature: Beta

> Feature: beta
> Created: 1774200100
> Status: Draft
EOF
  run "$PROJECT/scripts/docs-check.sh" list-specs "$PROJECT/docs"
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "list-specs: empty specs directory returns empty array" {
  # docs/specs/ exists but is empty
  run "$PROJECT/scripts/docs-check.sh" list-specs "$PROJECT/docs"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "list-specs: missing specs directory returns empty array" {
  rmdir "$PROJECT/docs/specs"
  run "$PROJECT/scripts/docs-check.sh" list-specs "$PROJECT/docs"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---------------------------------------------------------------------------
# Step 3: activate (AC-2, AC-5)
# ---------------------------------------------------------------------------

@test "activate: creates branch with correct naming convention" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add spec"

  run "$PROJECT/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  [ "$status" -eq 0 ]

  # Verify branch name follows convention
  local branch
  branch=$(git -C "$PROJECT" branch --show-current)
  [ "$branch" = "claude/feat/auth-system" ]
}

@test "activate: copies spec to docs/spec.md" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add spec"

  "$PROJECT/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  [ -f "$PROJECT/docs/spec.md" ]
  grep -q "auth-system" "$PROJECT/docs/spec.md"
}

@test "activate: updates spec status to In Progress" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add spec"

  "$PROJECT/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  grep -q "Status: In Progress" "$PROJECT/docs/specs/auth-system.md"
}

@test "activate: fails if another spec is In Progress" {
  cat > "$PROJECT/docs/specs/first.md" <<'EOF'
# Feature: First

> Feature: first
> Created: 1774200000
> Status: In Progress

## Summary
First feature.
EOF
  cat > "$PROJECT/docs/specs/second.md" <<'EOF'
# Feature: Second

> Feature: second
> Created: 1774200100
> Status: Ready

## Summary
Second feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add specs"

  run "$PROJECT/scripts/docs-check.sh" activate second "$PROJECT/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "first"
}

@test "activate: fails if feature-id not found" {
  run "$PROJECT/scripts/docs-check.sh" activate nonexistent "$PROJECT/docs"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Step 4: complete (AC-3, AC-18)
# ---------------------------------------------------------------------------

@test "complete: updates spec status to Complete" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: In Progress

## Summary
Auth feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add spec"

  run "$PROJECT/scripts/docs-check.sh" complete auth-system "$PROJECT/docs"
  [ "$status" -eq 0 ]
  grep -q "Status: Complete" "$PROJECT/docs/specs/auth-system.md"
}

@test "complete: clears assumptions.md if it exists" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: In Progress

## Summary
Auth feature.
EOF
  echo "- **Auth**: Chose JWT over sessions" > "$PROJECT/docs/assumptions.md"
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add spec"

  "$PROJECT/scripts/docs-check.sh" complete auth-system "$PROJECT/docs"
  # File should exist but be empty
  [ -f "$PROJECT/docs/assumptions.md" ]
  [ ! -s "$PROJECT/docs/assumptions.md" ]
}

@test "complete: fails if spec is not In Progress" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add spec"

  run "$PROJECT/scripts/docs-check.sh" complete auth-system "$PROJECT/docs"
  [ "$status" -eq 1 ]
}

@test "complete: fails if feature-id not found" {
  run "$PROJECT/scripts/docs-check.sh" complete nonexistent "$PROJECT/docs"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Step 5: validate/recommend multi-spec (AC-17, AC-23, AC-24)
# ---------------------------------------------------------------------------

@test "validate: no spec.md with specs in backlog returns no-active-spec" {
  # Specs exist in docs/specs/ but no docs/spec.md
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  run "$PROJECT/scripts/docs-check.sh" validate "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "no-active-spec"'
}

@test "validate: works unchanged on feature branch with spec.md" {
  # Create spec + plan on a feature branch
  cat > "$PROJECT/docs/spec.md" <<'EOF'
# Feature: Test

> Feature: test-feat
> Created: 1774200000
> Status: In Progress

## Summary
Test.
EOF
  cat > "$PROJECT/docs/plan.md" <<'EOF'
# Implementation Plan: Test

> Feature: test-feat
> Created: 1774200000
> Spec hash: placeholder
> Based on: docs/spec.md

## Objective
Test.
EOF
  run "$PROJECT/scripts/docs-check.sh" validate "$PROJECT/docs"
  [ "$status" -eq 0 ]
  # Should NOT be no-active-spec since spec.md exists
  local result
  result=$(echo "$output" | jq -r '.result')
  [ "$result" != "no-active-spec" ]
}

@test "recommend: no spec.md with Ready specs suggests activate" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  run "$PROJECT/scripts/docs-check.sh" recommend "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.next_action | test("activate")'
}

@test "recommend: no spec.md and no Ready specs suggests describe" {
  # Empty specs dir, no spec.md
  run "$PROJECT/scripts/docs-check.sh" recommend "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.next_action | test("Describe|describe")'
}

# ---------------------------------------------------------------------------
# Step 6: Branch naming hook (AC-6)
# ---------------------------------------------------------------------------

@test "branch-name-lint: warns on non-convention branch name" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/branch-name-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git checkout -b my-bad-branch"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "convention\|warning\|claude/"
}

@test "branch-name-lint: no warning on convention branch name" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/branch-name-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git checkout -b claude/feat/my-feature"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  # Should have no warning output (or minimal)
  [[ ! "$output" =~ "WARNING" ]]
}

@test "branch-name-lint: ignores non-branch-creation commands" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/branch-name-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ -z "$output" || ! "$output" =~ "WARNING" ]]
}

@test "branch-name-lint: handles git switch -c" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/branch-name-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git switch -c bad-name"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "convention\|warning\|claude/"
}

# ---------------------------------------------------------------------------
# Step 7: Commit message lint hook (AC-9)
# ---------------------------------------------------------------------------

@test "commit-msg-lint: no warning on conventional commit" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/commit-msg-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(auth): add login flow\""}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "WARNING" ]]
}

@test "commit-msg-lint: warns on non-conventional commit" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/commit-msg-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fixed some stuff\""}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "warning\|conventional"
}

@test "commit-msg-lint: accepts type without scope" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/commit-msg-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"docs: update README\""}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "WARNING" ]]
}

@test "commit-msg-lint: ignores non-commit commands" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/commit-msg-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ -z "$output" || ! "$output" =~ "WARNING" ]]
}

@test "commit-msg-lint: handles heredoc commit messages" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/commit-msg-lint.sh"
  # Heredoc commits don't use -m, so hook should skip them
  input='{"tool_name":"Bash","tool_input":{"command":"git commit"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ -z "$output" || ! "$output" =~ "WARNING" ]]
}

# ---------------------------------------------------------------------------
# Step 11: Worktree compatibility (AC-19, AC-21)
# ---------------------------------------------------------------------------

@test "worktree: .gitignore contains .claude/worktrees/" {
  grep -q ".claude/worktrees/" "$BATS_TEST_DIRNAME/../.gitignore"
}

@test "worktree: .claudeignore contains .claude/worktrees/" {
  grep -q ".claude/worktrees/" "$BATS_TEST_DIRNAME/../.claudeignore"
}

@test "worktree: validate works from subdirectory" {
  # Create a spec so validate has something to work with
  cat > "$PROJECT/docs/spec.md" <<'EOF'
# Feature: Test

> Feature: test-feat
> Created: 1774200000
> Status: In Progress

## Summary
Test.
EOF
  mkdir -p "$PROJECT/src"
  # Run from a subdirectory — should still find docs relative to project root
  run "$PROJECT/scripts/docs-check.sh" validate "$PROJECT/docs"
  [ "$status" -eq 0 ]
}

@test "activate: fails on dirty worktree" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  # Don't commit — leave dirty
  run "$PROJECT/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  [ "$status" -eq 1 ]
}
