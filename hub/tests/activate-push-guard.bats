#!/usr/bin/env bats
# Tests for the pre-activate push-guard (AC-17/18/19 of ideas-to-linear).
#
# The guard halts `docs-check.sh activate` when local main is ahead of
# origin/main, to prevent the unpushed-commits-on-main pattern that causes
# divergence at squash-merge time. Bypass: `--force-local-ahead`.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

load helpers/seed-repo

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  seed_repo_with_origin --docs-specs
}

teardown() {
  rm -rf "$REPO" "$BARE"
}

# =========================================================================
# AC-17: guard halts when local main has unpushed commits
# =========================================================================

@test "AC-17: activate halts when local main is ahead of origin/main" {
  cd "$REPO"
  # Create a local-only commit → local main is 1 ahead of origin/main
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only work"

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  # Guard message should mention unpushed / ahead / origin/main
  echo "$output" | grep -qiE "unpushed|ahead of origin|push main"
}

@test "AC-17: guard surfaces the unpushed commit's short hash" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only work"
  local short_hash
  short_hash=$(git rev-parse --short HEAD)

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "$short_hash"
}

@test "AC-17: guard passes when local main matches origin/main" {
  cd "$REPO"
  # No local-only commits; local main == origin/main. Guard should pass,
  # failure should be the later 'spec not found' error, not the guard.
  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
  ! echo "$output" | grep -qiE "unpushed|ahead of origin"
}

# =========================================================================
# AC-18: --force-local-ahead bypasses the guard
# =========================================================================

@test "AC-18: --force-local-ahead bypasses the guard" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only"

  run bash "$SCRIPT" activate some-spec --force-local-ahead "$REPO/docs"
  # Guard passed → failure is now 'spec not found', not the guard message.
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
  ! echo "$output" | grep -qiE "unpushed|ahead of origin"
}

@test "AC-18: halt message names the --force-sync escape hatch" {
  # BTS-122 redirected the canonical hint to --force-sync; --force-local-ahead
  # remains a silent alias (see BTS-122 AC-2 tests below).
  # BTS-145: default activate now auto-pushes on AHEAD, so we use
  # --no-auto-push to reach the original halt path and assert the hint.
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only"

  run bash "$SCRIPT" activate some-spec --no-auto-push "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "force-sync"
}

# =========================================================================
# AC-19: no origin/main → guard is a no-op
# =========================================================================

@test "AC-19: guard is a no-op when origin/main does not exist" {
  # Fresh local repo with no remote at all.
  local LOCAL
  LOCAL=$(mktemp -d)
  git -C "$LOCAL" init -q -b main
  git -C "$LOCAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  mkdir -p "$LOCAL/docs/specs"

  cd "$LOCAL"
  run bash "$SCRIPT" activate some-spec "$LOCAL/docs"
  # Guard must NOT halt. Failure should be 'spec not found', no guard msg.
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
  ! echo "$output" | grep -qiE "unpushed|ahead of origin"

  rm -rf "$LOCAL"
}

@test "AC-19: guard is a no-op when remote exists but origin/main ref is absent" {
  # Remote exists but hasn't been pushed to yet — origin/main ref is missing.
  local EMPTY_BARE
  EMPTY_BARE=$(mktemp -d)
  git -C "$EMPTY_BARE" init --bare -q

  local LOCAL
  LOCAL=$(mktemp -d)
  git -C "$LOCAL" init -q -b main
  git -C "$LOCAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  git -C "$LOCAL" remote add origin "$EMPTY_BARE"
  mkdir -p "$LOCAL/docs/specs"

  cd "$LOCAL"
  run bash "$SCRIPT" activate some-spec "$LOCAL/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
  ! echo "$output" | grep -qiE "unpushed|ahead of origin"

  rm -rf "$LOCAL" "$EMPTY_BARE"
}

# =========================================================================
# BTS-122 AC-2: local-BEHIND detection at activate time
# =========================================================================

@test "BTS-122 AC-2: activate halts when local main is BEHIND origin/main" {
  cd "$REPO"
  # Push a new commit to the bare remote via a side clone — origin/main now
  # points past local main. Fetch from side-clone to populate bare, not from
  # $REPO (which would update $REPO's cached origin/main too).
  local SIDE
  SIDE=$(mktemp -d)
  git clone -q "$BARE" "$SIDE"
  git -C "$SIDE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "remote-ahead"
  git -C "$SIDE" push -q origin main
  rm -rf "$SIDE"

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  # After fetch, the guard detects behind — message mentions BEHIND + pull remediation.
  echo "$output" | grep -qi "behind"
  echo "$output" | grep -q "git pull --ff-only"
}

@test "BTS-122 AC-2: --force-sync bypasses the behind guard" {
  cd "$REPO"
  local SIDE
  SIDE=$(mktemp -d)
  git clone -q "$BARE" "$SIDE"
  git -C "$SIDE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "remote-ahead"
  git -C "$SIDE" push -q origin main
  rm -rf "$SIDE"

  run bash "$SCRIPT" activate some-spec --force-sync "$REPO/docs"
  # Guard bypassed → failure is now 'spec not found'.
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
  ! echo "$output" | grep -qi "behind"
}

@test "BTS-122 AC-2: --force-sync also bypasses the ahead guard (union semantics)" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only"

  run bash "$SCRIPT" activate some-spec --force-sync "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
  ! echo "$output" | grep -qiE "unpushed|ahead of origin"
}

@test "BTS-122 AC-2: legacy --force-local-ahead alias still bypasses both guards" {
  cd "$REPO"
  # Seed both ahead AND behind so we're testing the union.
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only"
  local SIDE
  SIDE=$(mktemp -d)
  git clone -q "$BARE" "$SIDE"
  git -C "$SIDE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "remote-ahead"
  git -C "$SIDE" push -q origin main
  rm -rf "$SIDE"

  run bash "$SCRIPT" activate some-spec --force-local-ahead "$REPO/docs"
  # Guard bypassed; both states ignored.
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
}

# =========================================================================
# BTS-122 AC-4: existing-branch guard
# =========================================================================

@test "BTS-122 AC-4: activate halts when target branch already exists" {
  cd "$REPO"
  # Seed a spec so we get past the spec-lookup step.
  cat > "$REPO/docs/specs/foo-spec.md" <<'MD'
# Feature: Foo

> Feature: foo-spec
> Created: 1777004190
> Status: Draft

## Summary
Fixture.
MD
  # Pre-create the branch so activate's checkout collides.
  git -C "$REPO" branch claude/feat/foo-spec

  run bash "$SCRIPT" activate foo-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "claude/feat/foo-spec"
  echo "$output" | grep -qE "git branch -D|git checkout"
}

# =========================================================================
# BTS-122 AC-6: working-tree guard regression coverage (non-spec files blocked)
# =========================================================================

@test "BTS-122 AC-6: activate halts on uncommitted non-spec file" {
  cd "$REPO"
  cat > "$REPO/docs/specs/foo-spec.md" <<'MD'
# Feature: Foo

> Feature: foo-spec
> Created: 1777004190
> Status: Draft

## Summary
Fixture.
MD
  git -C "$REPO" add docs/specs/foo-spec.md
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "seed spec"
  git -C "$REPO" push -q origin main

  # Introduce an uncommitted non-spec file. README.md, not in docs/specs/.
  echo "scratch" > "$REPO/README.md"

  run bash "$SCRIPT" activate foo-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "uncommitted"
}

# =========================================================================
# BTS-145: cmd_activate auto-push-main
# =========================================================================

@test "BTS-145 AC-1: default activate auto-pushes when on main with unpushed commits" {
  cd "$REPO"
  # Local-only commit → AHEAD.
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only work"
  local local_sha
  local_sha=$(git rev-parse HEAD)

  # Run activate (no spec exists, so it'll error after auto-push).
  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  # Auto-push success → spec lookup fails → exit 1 with "not found".
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "AUTO-PUSH"
  echo "$output" | grep -q "not found"

  # Verify the auto-push actually landed: origin/main should now include the local commit.
  local origin_sha
  origin_sha=$(git -C "$BARE" rev-parse main)
  [ "$origin_sha" = "$local_sha" ]
}

@test "BTS-145 AC-2: --no-auto-push preserves AHEAD error path" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only work"
  local pre_origin_sha
  pre_origin_sha=$(git -C "$BARE" rev-parse main)

  run bash "$SCRIPT" activate some-spec --no-auto-push "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qiE "ahead of origin|unpushed"
  ! echo "$output" | grep -q "AUTO-PUSH"

  # Verify origin/main was NOT updated.
  local post_origin_sha
  post_origin_sha=$(git -C "$BARE" rev-parse main)
  [ "$pre_origin_sha" = "$post_origin_sha" ]
}

@test "BTS-145 AC-3: auto-push does NOT fire when current branch is not main" {
  cd "$REPO"
  # Make local main AHEAD.
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only work"
  # Switch to a feature branch (still ahead because main has unpushed commits).
  git -C "$REPO" checkout -q -b some-feature

  local pre_origin_sha
  pre_origin_sha=$(git -C "$BARE" rev-parse main)

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qiE "ahead of origin|unpushed"
  ! echo "$output" | grep -q "AUTO-PUSH"

  # origin/main unchanged.
  local post_origin_sha
  post_origin_sha=$(git -C "$BARE" rev-parse main)
  [ "$pre_origin_sha" = "$post_origin_sha" ]
}

@test "BTS-145 AC-4: auto-push failure does not silently claim success" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only work"
  # Break the remote: remove the bare repo dir mid-test.
  rm -rf "$BARE"

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  # When the remote is unreachable, sync-check's fetch fails first (degrades
  # to WARN) and activate proceeds without auto-push. Either path is OK as
  # long as we never claim AUTO-PUSH succeeded for a push that didn't happen.
  ! echo "$output" | grep -q "AUTO-PUSH: success"
}

@test "BTS-145 AC-5: --force-sync still bypasses the entire sync check" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only work"
  local pre_origin_sha
  pre_origin_sha=$(git -C "$BARE" rev-parse main)

  run bash "$SCRIPT" activate some-spec --force-sync "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
  ! echo "$output" | grep -q "AUTO-PUSH"

  # --force-sync should NOT auto-push; the user's contract is "leave my main alone."
  local post_origin_sha
  post_origin_sha=$(git -C "$BARE" rev-parse main)
  [ "$pre_origin_sha" = "$post_origin_sha" ]
}

@test "BTS-145 AC-6: BEHIND case unchanged — auto-push does NOT fire on behind" {
  cd "$REPO"
  # Push a remote commit so local main is BEHIND origin/main.
  local SIDE
  SIDE=$(mktemp -d)
  git clone -q "$BARE" "$SIDE"
  git -C "$SIDE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "remote-ahead"
  git -C "$SIDE" push -q origin main
  rm -rf "$SIDE"

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "behind"
  ! echo "$output" | grep -q "AUTO-PUSH"
}

@test "BTS-145 AC-7: stderr emits AUTO-PUSH marker lines on success" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only work"

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  echo "$output" | grep -q "AUTO-PUSH: local main is ahead"
  echo "$output" | grep -q "AUTO-PUSH: success"
}
