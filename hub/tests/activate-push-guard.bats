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
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only"

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
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
