#!/usr/bin/env bats
# BTS-122 — lifecycle gate audit. Tests for:
# - cmd_sync_check helper (AC-1, 3, 9)
# - cmd_pr_guard subcommand (AC-5)
# - cmd_land offline-degradation WARN: (AC-7)
# Existing cmd_activate guard tests live in activate-push-guard.bats; this file
# covers the NEW helpers added by BTS-122.

DOCS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  REPO=$(mktemp -d)
  BARE=$(mktemp -d)

  git -C "$REPO" init -q -b main
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  git -C "$BARE" init --bare -q -b main
  git -C "$REPO" remote add origin "$BARE"
  git -C "$REPO" push -q -u origin main
}

teardown() {
  rm -rf "$REPO" "$BARE"
}

# ===========================================================================
# Phase 1 — cmd_sync_check (AC-1, 3, 9)
# ===========================================================================

@test "BTS-122 AC-1: sync-check exits 0 when local main matches origin/main" {
  cd "$REPO"
  run bash "$DOCS" sync-check "$REPO"
  [ "$status" -eq 0 ]
}

@test "BTS-122 AC-1: sync-check exits 1 when local is ahead, prints AHEAD: with hashes" {
  cd "$REPO"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local-ahead"
  local short_hash
  short_hash=$(git rev-parse --short HEAD)

  run bash "$DOCS" sync-check "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "AHEAD" ]]
  [[ "$output" =~ $short_hash ]]
}

@test "BTS-122 AC-1: sync-check fetches before comparing — detects NEW remote commit" {
  # The critical AC-1 assertion: fetch actually runs. We seed a commit on the
  # bare remote AFTER the local clone, then call sync-check. A cached-ref-only
  # comparison would miss it; a fetch-based comparison catches it.
  local BARE_CLONE
  BARE_CLONE=$(mktemp -d)
  git clone --bare -q "$BARE" "$BARE_CLONE"
  git -C "$BARE_CLONE" -c user.email=t@t -c user.name=t commit --allow-empty -m "remote-ahead" -q 2>/dev/null || {
    # Bare repos don't allow direct commits — use a working repo to push.
    local WORK
    WORK=$(mktemp -d)
    git clone -q "$BARE" "$WORK"
    git -C "$WORK" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "remote-ahead"
    git -C "$WORK" push -q origin main
    rm -rf "$WORK"
  }
  rm -rf "$BARE_CLONE"

  # Local REPO hasn't fetched yet — cached origin/main still points at the
  # original init commit. sync-check must fetch + detect the new upstream.
  cd "$REPO"
  run bash "$DOCS" sync-check "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "BEHIND" ]]
  [[ "$output" =~ "git pull --ff-only" ]]
}

@test "BTS-122 AC-3: sync-check emits WARN: when origin unreachable, exits 0" {
  cd "$REPO"
  # Break origin URL so fetch fails.
  git -C "$REPO" remote set-url origin "/nonexistent/path/does-not-exist.git"

  run bash "$DOCS" sync-check "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "WARN" ]]
  [[ "$output" =~ "offline" ]]
}

@test "BTS-122 AC-9: sync-check is no-op (exit 0) when no origin remote at all" {
  local LOCAL
  LOCAL=$(mktemp -d)
  git -C "$LOCAL" init -q -b main
  git -C "$LOCAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"

  cd "$LOCAL"
  run bash "$DOCS" sync-check "$LOCAL"
  [ "$status" -eq 0 ]
  # No spurious WARN: when there's no remote to sync with.
  [[ ! "$output" =~ "WARN" ]]

  rm -rf "$LOCAL"
}

@test "BTS-122 AC-9: sync-check is no-op when origin exists but origin/main ref absent" {
  local EMPTY_BARE LOCAL
  EMPTY_BARE=$(mktemp -d)
  git -C "$EMPTY_BARE" init --bare -q
  LOCAL=$(mktemp -d)
  git -C "$LOCAL" init -q -b main
  git -C "$LOCAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  git -C "$LOCAL" remote add origin "$EMPTY_BARE"

  cd "$LOCAL"
  run bash "$DOCS" sync-check "$LOCAL"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "AHEAD" ]]
  [[ ! "$output" =~ "BEHIND" ]]

  rm -rf "$LOCAL" "$EMPTY_BARE"
}

# ===========================================================================
# Phase 4 — cmd_pr_guard (AC-5)
# ===========================================================================

@test "BTS-122 AC-5: pr-guard exits 0 when feature branch is ahead of base" {
  cd "$REPO"
  git -C "$REPO" checkout -q -b claude/feat/example
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature work"

  run bash "$DOCS" pr-guard
  [ "$status" -eq 0 ]
}

@test "BTS-122 AC-5: pr-guard halts when feature branch is behind its base" {
  cd "$REPO"
  git -C "$REPO" checkout -q -b claude/feat/example
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature work"

  # Move origin/main forward by pushing from a side clone.
  local SIDE
  SIDE=$(mktemp -d)
  git clone -q "$BARE" "$SIDE"
  git -C "$SIDE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "base-moved"
  git -C "$SIDE" push -q origin main
  rm -rf "$SIDE"

  run bash "$DOCS" pr-guard
  [ "$status" -eq 1 ]
  [[ "$output" =~ "behind" ]]
  [[ "$output" =~ "rebase origin/main" ]] || [[ "$output" =~ "merge origin/main" ]]
}

@test "BTS-122 AC-5: pr-guard is a no-op when no origin remote exists" {
  local LOCAL
  LOCAL=$(mktemp -d)
  git -C "$LOCAL" init -q -b main
  git -C "$LOCAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  git -C "$LOCAL" checkout -q -b claude/feat/example
  git -C "$LOCAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "work"

  cd "$LOCAL"
  run bash "$DOCS" pr-guard
  [ "$status" -eq 0 ]

  rm -rf "$LOCAL"
}

# ===========================================================================
# Phase 3 — cmd_land offline-degradation (AC-7)
# ===========================================================================

@test "BTS-122 AC-7: cmd_land emits WARN: and exits 0 when fetch fails" {
  cd "$REPO"
  # Create and switch to a feature branch so cmd_land doesn't take the
  # "already on main" early return path.
  git -C "$REPO" checkout -q -b claude/feat/dummy
  # Break origin URL so fetch fails.
  git -C "$REPO" remote set-url origin "/nonexistent/path/does-not-exist.git"

  # Capture the pre-land HEAD on main to assert no reset happened.
  local pre_main_sha
  pre_main_sha=$(git -C "$REPO" rev-parse main)

  run bash "$DOCS" land --force
  [ "$status" -eq 0 ]
  [[ "$output" =~ "WARN" ]]

  # Assert main wasn't reset to a stale/unknown ref.
  local post_main_sha
  post_main_sha=$(git -C "$REPO" rev-parse main)
  [ "$pre_main_sha" = "$post_main_sha" ]
}

