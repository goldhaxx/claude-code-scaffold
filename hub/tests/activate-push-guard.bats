#!/usr/bin/env bats
# Tests for the pre-activate push-guard (AC-17/18/19 of ideas-to-linear).
#
# The guard halts `docs-check.sh activate` when local main is ahead of
# origin/main, to prevent the unpushed-commits-on-main pattern that causes
# divergence at squash-merge time. Bypass: `--force-local-ahead`.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  REPO=$(mktemp -d)
  BARE=$(mktemp -d)

  # Local repo with one commit + an origin
  git -C "$REPO" init -q -b main
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  git -C "$BARE" init --bare -q -b main
  git -C "$REPO" remote add origin "$BARE"
  git -C "$REPO" push -q -u origin main

  mkdir -p "$REPO/docs/specs"
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

@test "AC-18: halt message names the --force-local-ahead escape hatch" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-only"

  run bash "$SCRIPT" activate some-spec "$REPO/docs"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "force-local-ahead"
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
