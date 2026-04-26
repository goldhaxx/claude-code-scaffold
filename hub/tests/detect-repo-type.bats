#!/usr/bin/env bats
# BTS-72: docs-check.sh detect-repo-type — repo-type classifier returning
# {type: github|other-remote|local, has_remote, remote_url}.
#
# Each test scopes its own tmpdir + git init to test fresh repo state.

bats_require_minimum_version 1.5.0

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  REPO=$(mktemp -d)
  NOTREPO=""
  cd "$REPO"
  git init -q -b main
  git -c user.email=x@x -c user.name=x commit -q --allow-empty -m initial
}

teardown() {
  cd /
  rm -rf "$REPO"
  if [[ -n "$NOTREPO" ]]; then
    rm -rf "$NOTREPO"
  fi
}

# =========================================================================
# AC-1: github remote
# =========================================================================

@test "AC-1: github.com origin → type=github" {
  set -e
  git remote add origin git@github.com:foo/bar.git
  run bash "$DC" detect-repo-type
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "github"'
  echo "$output" | jq -e '.has_remote == true'
  echo "$output" | jq -e '.remote_url == "git@github.com:foo/bar.git"'
}

@test "AC-1 https: https github URL → type=github" {
  set -e
  git remote add origin https://github.com/foo/bar.git
  run bash "$DC" detect-repo-type
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "github"'
}

# =========================================================================
# AC-2: non-github remote
# =========================================================================

@test "AC-2: gitlab.com origin → type=other-remote" {
  set -e
  git remote add origin git@gitlab.com:foo/bar.git
  run bash "$DC" detect-repo-type
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "other-remote"'
  echo "$output" | jq -e '.has_remote == true'
}

@test "AC-2: bitbucket origin → type=other-remote" {
  set -e
  git remote add origin git@bitbucket.org:foo/bar.git
  run bash "$DC" detect-repo-type
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "other-remote"'
}

# =========================================================================
# AC-3: no remote
# =========================================================================

@test "AC-3: no origin configured → type=local" {
  set -e
  run bash "$DC" detect-repo-type
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "local"'
  echo "$output" | jq -e '.has_remote == false'
  echo "$output" | jq -e '.remote_url == ""'
}

# =========================================================================
# AC-4: not in a repo
# =========================================================================

@test "AC-4: outside git repo → exit 2" {
  NOTREPO=$(mktemp -d)
  cd "$NOTREPO"
  run bash "$DC" detect-repo-type
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in a git repository"* ]]
  # Cleanup is handled by teardown() now (NIT-2 fix).
}

# =========================================================================
# Reviewer CONCERN-1: poisoned-path regression — github.com in the repo
# path of a non-github host must NOT classify as github.
# =========================================================================

@test "CONCERN-1: gitlab.com:user/github.com-mirror.git → other-remote (host-precise match)" {
  set -e
  git remote add origin git@gitlab.com:user/github.com-mirror.git
  run bash "$DC" detect-repo-type
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "other-remote"'
}

@test "CONCERN-1: https://gitlab.com/user/github.com-clone.git → other-remote" {
  set -e
  git remote add origin https://gitlab.com/user/github.com-clone.git
  run bash "$DC" detect-repo-type
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.type == "other-remote"'
}

# =========================================================================
# AC-8: dispatch registration
# =========================================================================

@test "AC-8: docs-check.sh dispatch registers detect-repo-type" {
  grep -q "detect-repo-type)" "$DC"
}

# =========================================================================
# Edge cases
# =========================================================================

@test "edge: github with port specifier still classifies as github" {
  set -e
  # Some self-hosted github enterprise URLs include port; classifier is
  # substring-based on "github.com" so github enterprise on a non-github.com
  # domain (github.acme.corp) would NOT match — that's expected behavior.
  git remote add origin git@github.com:foo/bar.git
  run bash "$DC" detect-repo-type
  echo "$output" | jq -e '.type == "github"'
}

@test "edge: github enterprise (non-github.com domain) → other-remote" {
  set -e
  git remote add origin https://github.acme.corp/foo/bar.git
  run bash "$DC" detect-repo-type
  echo "$output" | jq -e '.type == "other-remote"'
}
