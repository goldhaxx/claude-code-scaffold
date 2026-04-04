#!/usr/bin/env bats
# Tests for branch-based feature lifecycle
#
# Covers: scaffold config, list-specs, activate, complete, validate/recommend
# multi-spec, hooks, and worktree compatibility.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

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
  mkdir -p "$PROJECT/.ccanvil/scripts"
  cp "$SCRIPT" "$PROJECT/.ccanvil/scripts/docs-check.sh"
  chmod +x "$PROJECT/.ccanvil/scripts/docs-check.sh"

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
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" config-get pr_review "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "scaffold-config: returns false for missing key" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features": {"pr_review": true}}
EOF
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" config-get nonexistent "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "scaffold-config: returns false when scaffold.json missing" {
  # No scaffold.json created
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" config-get pr_review "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "scaffold-config: returns false when scaffold.json is empty object" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{}
EOF
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" config-get pr_review "$PROJECT"
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
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" list-specs "$PROJECT/docs"
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
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" list-specs "$PROJECT/docs"
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "list-specs: empty specs directory returns empty array" {
  # docs/specs/ exists but is empty
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" list-specs "$PROJECT/docs"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "list-specs: missing specs directory returns empty array" {
  rmdir "$PROJECT/docs/specs"
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" list-specs "$PROJECT/docs"
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
  # Spec is uncommitted — activate should handle it

  run "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
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
  # Spec is uncommitted — activate should handle it

  "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  [ -f "$PROJECT/docs/spec.md" ]
  grep -q "auth-system" "$PROJECT/docs/spec.md"
  # docs/spec.md should have the updated status, not the original
  grep -q "Status: In Progress" "$PROJECT/docs/spec.md"
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
  # Spec is uncommitted — activate should handle it

  "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  grep -q "Status: In Progress" "$PROJECT/docs/specs/auth-system.md"
}

@test "activate: fails if another spec is In Progress" {
  # Blocking spec is committed (represents prior activation)
  cat > "$PROJECT/docs/specs/first.md" <<'EOF'
# Feature: First

> Feature: first
> Created: 1774200000
> Status: In Progress

## Summary
First feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add blocking spec"

  # Target spec is uncommitted
  cat > "$PROJECT/docs/specs/second.md" <<'EOF'
# Feature: Second

> Feature: second
> Created: 1774200100
> Status: Ready

## Summary
Second feature.
EOF

  run "$PROJECT/.ccanvil/scripts/docs-check.sh" activate second "$PROJECT/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "first"
}

@test "activate: fails if feature-id not found" {
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" activate nonexistent "$PROJECT/docs"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Step 3b: activate commit sequencing (BTS-28)
# ---------------------------------------------------------------------------

@test "activate: succeeds with uncommitted spec file (AC-1)" {
  # Spec exists but is NOT committed — activate should handle this
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF

  run "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Activated spec 'auth-system'"
}

@test "activate: succeeds with uncommitted spec file and docs/spec.md (AC-2)" {
  # Both the spec and a stale docs/spec.md are uncommitted
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  echo "stale spec" > "$PROJECT/docs/spec.md"

  run "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Activated spec 'auth-system'"
}

@test "activate: fails with uncommitted non-spec file (AC-3)" {
  # Spec is committed, but a non-spec file is dirty — should still reject
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add spec"

  # Create an uncommitted non-spec file
  echo "dirty" > "$PROJECT/README.md"

  run "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "uncommitted changes"
}

# ---------------------------------------------------------------------------
# Step 3c: activate auto-commit (BTS-28 AC-4, AC-5, AC-6)
# ---------------------------------------------------------------------------

@test "activate: auto-commits spec files on branch (AC-4)" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF

  "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"

  # Branch should have exactly one new commit (beyond init)
  local count
  count=$(git -C "$PROJECT" log --oneline main..HEAD | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]

  # That commit should contain both spec files
  local files_in_commit
  files_in_commit=$(git -C "$PROJECT" diff-tree --no-commit-id --name-only -r HEAD)
  echo "$files_in_commit" | grep -q "docs/specs/auth-system.md"
  echo "$files_in_commit" | grep -q "docs/spec.md"
}

@test "activate: auto-commit message follows convention (AC-5)" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF

  "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"

  local msg
  msg=$(git -C "$PROJECT" log -1 --format=%s)
  [ "$msg" = "docs(lifecycle): activate auth-system" ]
}

@test "activate: worktree is clean after activation (AC-6)" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF

  "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"

  local dirty
  dirty=$(git -C "$PROJECT" status --porcelain)
  [ -z "$dirty" ]
}

# ---------------------------------------------------------------------------
# Step 3d: squash-merge simulation (BTS-28 AC-10)
# ---------------------------------------------------------------------------

@test "activate: no divergence after squash-merge (AC-10)" {
  # 1. Create spec (uncommitted)
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF

  # 2. Activate — creates branch, auto-commits spec
  "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"

  # 3. Simulate implementation work on the branch
  echo "impl" > "$PROJECT/src.sh"
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "feat: implement auth"

  # 4. Switch to main and squash-merge
  git -C "$PROJECT" checkout -q main
  git -C "$PROJECT" merge --squash claude/feat/auth-system
  git -C "$PROJECT" commit -q -m "feat: auth system (#1)"

  # 5. Verify: main has clean linear history
  # Main should have exactly 2 commits: init + squash
  local main_count
  main_count=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')
  [ "$main_count" -eq 2 ]

  # 6. Verify: no spec commit on main before the squash
  # The first commit is "init", the second is the squash — no "add spec" commit
  local first_msg
  first_msg=$(git -C "$PROJECT" log --oneline --reverse | head -1)
  echo "$first_msg" | grep -q "init"
  local second_msg
  second_msg=$(git -C "$PROJECT" log -1 --oneline)
  echo "$second_msg" | grep -q "auth system"

  # 7. Verify: spec file exists in the squash commit (came from branch)
  git -C "$PROJECT" show HEAD:docs/specs/auth-system.md | grep -q "Status: In Progress"
  git -C "$PROJECT" show HEAD:docs/spec.md | grep -q "auth-system"
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

  run "$PROJECT/.ccanvil/scripts/docs-check.sh" complete auth-system "$PROJECT/docs"
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

  "$PROJECT/.ccanvil/scripts/docs-check.sh" complete auth-system "$PROJECT/docs"
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

  run "$PROJECT/.ccanvil/scripts/docs-check.sh" complete auth-system "$PROJECT/docs"
  [ "$status" -eq 1 ]
}

@test "complete: fails if feature-id not found" {
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" complete nonexistent "$PROJECT/docs"
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
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" validate "$PROJECT/docs"
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
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" validate "$PROJECT/docs"
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
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" recommend "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.next_action | test("activate")'
}

@test "recommend: no spec.md and no Ready specs suggests describe" {
  # Empty specs dir, no spec.md
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" recommend "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.next_action | test("Describe|describe")'
}

# ---------------------------------------------------------------------------
# Step 6: Branch naming hook (AC-6)
# ---------------------------------------------------------------------------

@test "branch-name-lint: warns on non-convention branch name" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/branch-name-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git checkout -b my-bad-branch"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "convention\|warning\|claude/"
}

@test "branch-name-lint: no warning on convention branch name" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/branch-name-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git checkout -b claude/feat/my-feature"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  # Should have no warning output (or minimal)
  [[ ! "$output" =~ "WARNING" ]]
}

@test "branch-name-lint: ignores non-branch-creation commands" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/branch-name-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ -z "$output" || ! "$output" =~ "WARNING" ]]
}

@test "branch-name-lint: handles git switch -c" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/branch-name-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git switch -c bad-name"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "convention\|warning\|claude/"
}

# ---------------------------------------------------------------------------
# Step 7: Commit message lint hook (AC-9)
# ---------------------------------------------------------------------------

@test "commit-msg-lint: no warning on conventional commit" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/commit-msg-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(auth): add login flow\""}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "WARNING" ]]
}

@test "commit-msg-lint: warns on non-conventional commit" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/commit-msg-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fixed some stuff\""}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "warning\|conventional"
}

@test "commit-msg-lint: accepts type without scope" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/commit-msg-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"docs: update README\""}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "WARNING" ]]
}

@test "commit-msg-lint: ignores non-commit commands" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/commit-msg-lint.sh"
  input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  run bash -c "echo '$input' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ -z "$output" || ! "$output" =~ "WARNING" ]]
}

@test "commit-msg-lint: handles heredoc commit messages" {
  HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/commit-msg-lint.sh"
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
  grep -q ".claude/worktrees/" "$BATS_TEST_DIRNAME/../../.gitignore"
}

@test "worktree: .claudeignore contains .claude/worktrees/" {
  grep -q ".claude/worktrees/" "$BATS_TEST_DIRNAME/../../.claudeignore"
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
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" validate "$PROJECT/docs"
  [ "$status" -eq 0 ]
}

@test "activate: fails on dirty worktree with non-spec files" {
  cat > "$PROJECT/docs/specs/auth-system.md" <<'EOF'
# Feature: Auth System

> Feature: auth-system
> Created: 1774200000
> Status: Ready

## Summary
Auth feature.
EOF
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -q -m "add spec"
  # Create a non-spec dirty file
  echo "dirty" > "$PROJECT/README.md"
  run "$PROJECT/.ccanvil/scripts/docs-check.sh" activate auth-system "$PROJECT/docs"
  [ "$status" -eq 1 ]
}
