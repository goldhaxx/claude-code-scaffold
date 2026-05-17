#!/usr/bin/env bats
#
# BTS-508 — test-state verb in docs-check.sh.
# Covers AC-6 (envelope shape + intersection logic) and AC-9 (fail-safe on
# missing/malformed state file). Step 4 extends with state-writer integration.

bats_require_minimum_version 1.5.0

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  git init -q
  git config user.email "a@b.example"
  git config user.name "test"
}

_commit() {
  local msg="$1"
  git add -A
  git -c commit.gpgsign=false commit -q -m "$msg"
}

@test "AC-9: empty envelope when state file does not exist" {
  mkdir -p .ccanvil/state
  run bash "$DC" test-state --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {}'
}

@test "AC-9: empty envelope when state file is malformed JSON" {
  mkdir -p .ccanvil/state
  echo 'not json {' > .ccanvil/state/test-state.json
  run bash "$DC" test-state --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {}'
}

@test "AC-6: full 7-field envelope when state file populated" {
  echo content > file.txt
  _commit init
  sha=$(git rev-parse HEAD)
  mkdir -p .ccanvil/state
  jq -n --arg sha "$sha" '{
    last_full_suite_commit: $sha,
    last_full_suite_at: 1000,
    last_manifest_validate_commit: $sha,
    last_manifest_validate_at: 2000
  }' > .ccanvil/state/test-state.json

  run bash "$DC" test-state --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg sha "$sha" '.last_full_suite_commit == $sha'
  echo "$output" | jq -e '.last_full_suite_at == 1000'
  echo "$output" | jq -e --arg sha "$sha" '.last_manifest_validate_commit == $sha'
  echo "$output" | jq -e '.last_manifest_validate_at == 2000'
  echo "$output" | jq -e '.files_changed_since_last_full_suite == 0'
  echo "$output" | jq -e '.files_changed_since_last_manifest_validate == 0'
  echo "$output" | jq -e '.manifest_tracked_files_changed_since_last_validate == 0'
}

@test "AC-6: manifest_tracked_files intersects diff with allowlist globs" {
  mkdir -p .ccanvil/scripts hub/tests
  echo orig > .ccanvil/scripts/foo.sh
  echo orig > hub/tests/bar.bats
  echo orig > README.md
  _commit init
  base=$(git rev-parse HEAD)

  # Change one allowlisted (.ccanvil/scripts/foo.sh) + one non-allowlisted (README.md)
  echo changed > .ccanvil/scripts/foo.sh
  echo changed > README.md
  _commit change

  mkdir -p .ccanvil/state
  jq -n --arg sha "$base" '{
    last_manifest_validate_commit: $sha,
    last_manifest_validate_at: 100
  }' > .ccanvil/state/test-state.json
  printf '%s\n' '.ccanvil/scripts/*.sh' > .ccanvil/manifest-allowlist.txt

  run bash "$DC" test-state --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.files_changed_since_last_manifest_validate == 2'
  echo "$output" | jq -e '.manifest_tracked_files_changed_since_last_validate == 1'
}
