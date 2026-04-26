#!/usr/bin/env bats
# BTS-72: cmd_land branches on detect-repo-type. Local-only repos
# perform an in-place merge instead of fetching from a non-existent
# origin. AUTO-CLOSE marker still emits (work-ref tracking is
# provider-orthogonal to repo-type).

bats_require_minimum_version 1.5.0

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  REPO=$(mktemp -d)
  cd "$REPO"
  git init -q -b main
  git -c user.email=x@x -c user.name=x commit -q --allow-empty -m initial
  # Disable signing for the test repo (matches cmd_land's invocation
  # convention via -c commit.gpgsign=false).
  git config commit.gpgsign false
  git config user.email "x@x"
  git config user.name "x"
}

teardown() {
  cd /
  rm -rf "$REPO"
}

# =========================================================================
# AC-5: local-only, already-on-main path skips fetch (marker doesn't fire,
# documented gap — see spec note)
# =========================================================================

@test "AC-5: local-only, on main with merged feature branch → no fetch, no recovery" {
  set -e
  # Create + merge a feature branch locally
  git checkout -q -b claude/feat/bts-99-test-feature
  git commit -q --allow-empty -m "feat: stub commit"
  git checkout -q main
  git merge -q --no-ff --no-edit claude/feat/bts-99-test-feature
  git commit -q --amend -m "feat(bts-99): test feature (#42)"
  git branch -D claude/feat/bts-99-test-feature

  run bash "$DC" land
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No remote configured"
  # AUTO-CLOSE marker is NOT expected here: cmd_land_recover_branch
  # parses (#NN) suffix and queries gh, which has no PR on local-only.
  # Documented gap in spec AC-5.
}

# =========================================================================
# AC-6: local-only, on feature branch → merge in-place, marker fires
# Reviewer CONCERN-3: no --force, exercising the `[[ repo_type != local ]]`
# guard that skips the gh PR check on local-only.
# =========================================================================

@test "AC-6: local-only, on feature branch → merge in-place, end on main, marker fires" {
  set -e
  git checkout -q -b claude/feat/bts-100-local-feature
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -q -m "feat(bts-100): add feature"

  # Create a matching spec archive so cmd_auto_close_emit can read its
  # Work: line and fire the marker. Linear-routed work-ref → marker.
  mkdir -p docs/specs
  cat > docs/specs/bts-100-local-feature.md <<EOF
# Feature: stub

> Feature: bts-100-local-feature
> Work: linear:BTS-100
> Status: In Progress
EOF
  git add docs/specs
  git commit -q -m "docs: stub spec"

  # No --force: relies on the local-only gh-skip guard at the entry-time
  # PR-merged check.
  run bash "$DC" land
  [ "$status" -eq 0 ]
  # Switched to main, feature branch deleted, commit on main
  branch_after=$(git branch --show-current)
  [ "$branch_after" = "main" ]
  ! git branch | grep -q "bts-100-local-feature"
  git log --oneline | grep -q "bts-100"
  # No remote means no fetch
  ! echo "$output" | grep -q "Fetched origin"
  # AUTO-CLOSE marker fires for linear-routed work
  echo "$output" | grep -q "AUTO-CLOSE:"
  echo "$output" | grep -q "BTS-100"
}

@test "AC-6 conflict-recovery: failed merge aborts cleanly, leaves user on feature branch" {
  set -e
  # Create feature branch with a conflicting change
  echo "main version" > conflict.txt
  git add conflict.txt
  git commit -q -m "main: add conflict.txt"

  git checkout -q -b claude/feat/bts-101-conflicts
  echo "feature version" > conflict.txt
  git add conflict.txt
  git commit -q -m "feat(bts-101): conflicting edit"

  git checkout -q main
  echo "main: divergent" > conflict.txt
  git add conflict.txt
  git commit -q -m "main: divergent edit"

  git checkout -q claude/feat/bts-101-conflicts

  run bash "$DC" land
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Could not merge"
  # User should be back on the feature branch (or at least not on main
  # with a half-merged state)
  branch_after=$(git branch --show-current)
  [ "$branch_after" = "claude/feat/bts-101-conflicts" ]
  # Tree should be clean (no unfinished merge)
  [ ! -f .git/MERGE_HEAD ]
}

# =========================================================================
# Drift-guards
# =========================================================================

@test "drift-guard: cmd_land calls detect-repo-type" {
  grep -q "cmd_detect_repo_type\|detect-repo-type" "$DC"
}

@test "drift-guard: /pr command documents local-only branch" {
  PR_CMD="$BATS_TEST_DIRNAME/../../.claude/commands/pr.md"
  grep -q "local-only" "$PR_CMD"
}
