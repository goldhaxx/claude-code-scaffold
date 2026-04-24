#!/usr/bin/env bats
# BTS-117 — docs-check.sh remote-presence: structured probe of origin remote.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
}

@test "BTS-117 AC-1: repo with origin → has_origin=true, url present, exit 0" {
  set -e
  local repo
  repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" remote add origin https://example.com/foo.git

  run bash "$SCRIPT" remote-presence "$repo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_origin == true'
  echo "$output" | jq -e '.url == "https://example.com/foo.git"'
  echo "$output" | jq -e '.git_repo == true'
  rm -rf "$repo"
}

@test "BTS-117 AC-2: repo without origin → has_origin=false, url=null, exit 0" {
  set -e
  local repo
  repo=$(mktemp -d)
  git -C "$repo" init -q

  run bash "$SCRIPT" remote-presence "$repo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_origin == false'
  echo "$output" | jq -e '.url == null'
  echo "$output" | jq -e '.git_repo == true'
  rm -rf "$repo"
}

@test "BTS-117 AC-3: outside any git repo → has_origin=false, git_repo=false, exit 0" {
  set -e
  local nonrepo
  nonrepo=$(mktemp -d)
  # No git init.

  run bash "$SCRIPT" remote-presence "$nonrepo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_origin == false'
  echo "$output" | jq -e '.url == null'
  echo "$output" | jq -e '.git_repo == false'
  rm -rf "$nonrepo"
}

@test "BTS-117 AC-4: default repo-dir is . (no positional arg)" {
  set -e
  # Run inside this repo (which has origin).
  run bash "$SCRIPT" remote-presence
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_origin == true'
  echo "$output" | jq -e '.git_repo == true'
}

@test "BTS-117 AC-5: JSON shape stable — always has has_origin, url, git_repo keys" {
  set -e
  local repo
  repo=$(mktemp -d)
  git -C "$repo" init -q

  run bash "$SCRIPT" remote-presence "$repo"
  echo "$output" | jq -e 'has("has_origin") and has("url") and has("git_repo")'
  rm -rf "$repo"
}

@test "BTS-117 AC-6: multiple remotes — only origin reported" {
  set -e
  local repo
  repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" remote add origin https://example.com/origin.git
  git -C "$repo" remote add upstream https://example.com/upstream.git
  git -C "$repo" remote add fork https://example.com/fork.git

  run bash "$SCRIPT" remote-presence "$repo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_origin == true'
  echo "$output" | jq -e '.url == "https://example.com/origin.git"'
  rm -rf "$repo"
}

@test "BTS-117 AC-7: exit code is always 0 — caller branches on has_origin, not status" {
  set -e
  # No-origin repo
  local repo
  repo=$(mktemp -d)
  git -C "$repo" init -q
  run bash "$SCRIPT" remote-presence "$repo"
  [ "$status" -eq 0 ]

  # Non-repo
  local nonrepo
  nonrepo=$(mktemp -d)
  run bash "$SCRIPT" remote-presence "$nonrepo"
  [ "$status" -eq 0 ]

  rm -rf "$repo" "$nonrepo"
}
