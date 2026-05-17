#!/usr/bin/env bats
#
# BTS-508 AC-8 — /review's manifest-validate skip-check.
# Exercises cmd_check_skip_validate decision envelope across three states:
# fail-safe on empty state, SKIP on SHA match + zero allowlisted changes,
# bypass when changes detected.

bats_require_minimum_version 1.5.0

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  git init -q
  git config user.email "a@b.example"
  git config user.name "test"
}

_commit() {
  git add -A
  git -c commit.gpgsign=false commit -q -m "$1"
}

@test "AC-8 / AC-9: empty state → no skip (fail-safe)" {
  echo content > file.txt
  _commit init

  run bash "$DC" check-skip-validate --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.skip == false'
  echo "$output" | jq -e '.reason == "no-prior-validate"'
}

@test "AC-8: SHA matches HEAD + zero manifest-tracked changes → SKIP" {
  mkdir -p .ccanvil/scripts
  echo orig > .ccanvil/scripts/foo.sh
  _commit init
  sha=$(git rev-parse HEAD)

  mkdir -p .ccanvil/state
  jq -n --arg sha "$sha" '{
    last_manifest_validate_commit: $sha,
    last_manifest_validate_at: 1000
  }' > .ccanvil/state/test-state.json
  printf '%s\n' '.ccanvil/scripts/*.sh' > .ccanvil/manifest-allowlist.txt

  run bash "$DC" check-skip-validate --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.skip == true'
  echo "$output" | jq -e --arg sha "$sha" '.sha == $sha'
}

@test "AC-8: SHA advanced + only non-allowlisted files changed → SKIP (Path-B core case)" {
  mkdir -p .ccanvil/scripts docs
  echo orig > .ccanvil/scripts/foo.sh
  echo orig > docs/readme.md
  _commit init
  base=$(git rev-parse HEAD)

  # Doc-only commit: HEAD advances, but no allowlisted file changes.
  echo changed > docs/readme.md
  _commit doc-only-change

  mkdir -p .ccanvil/state
  jq -n --arg sha "$base" '{
    last_manifest_validate_commit: $sha,
    last_manifest_validate_at: 1000
  }' > .ccanvil/state/test-state.json
  printf '%s\n' '.ccanvil/scripts/*.sh' > .ccanvil/manifest-allowlist.txt

  run bash "$DC" check-skip-validate --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.skip == true'
  echo "$output" | jq -e --arg sha "$base" '.sha == $sha'
}

@test "AC-8: SHA advanced + allowlisted file changed → no skip (files-changed)" {
  mkdir -p .ccanvil/scripts
  echo orig > .ccanvil/scripts/foo.sh
  _commit init
  base=$(git rev-parse HEAD)

  echo changed > .ccanvil/scripts/foo.sh
  _commit change

  mkdir -p .ccanvil/state
  jq -n --arg sha "$base" '{
    last_manifest_validate_commit: $sha,
    last_manifest_validate_at: 1000
  }' > .ccanvil/state/test-state.json
  printf '%s\n' '.ccanvil/scripts/*.sh' > .ccanvil/manifest-allowlist.txt

  run bash "$DC" check-skip-validate --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.skip == false'
  echo "$output" | jq -e '.reason | startswith("files-changed:")'
}

@test "AC-8: colon-suffix allowlist entries match bare file paths (BLOCKING-1 regression guard)" {
  # The allowlist often contains function-level entries of the form
  # `<path>:<function>`. Bare file paths from git diff must still match these.
  mkdir -p .ccanvil/scripts
  echo orig > .ccanvil/scripts/docs-check.sh
  _commit init
  base=$(git rev-parse HEAD)

  echo changed > .ccanvil/scripts/docs-check.sh
  _commit change

  mkdir -p .ccanvil/state
  jq -n --arg sha "$base" '{
    last_manifest_validate_commit: $sha,
    last_manifest_validate_at: 1000
  }' > .ccanvil/state/test-state.json
  # ONLY function-level entries — no bare file-level rescue entry.
  printf '%s\n' \
    '.ccanvil/scripts/docs-check.sh:cmd_test_state' \
    '.ccanvil/scripts/docs-check.sh:cmd_check_skip_validate' \
    > .ccanvil/manifest-allowlist.txt

  run bash "$DC" check-skip-validate --project-dir .
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.skip == false'
  echo "$output" | jq -e '.reason | startswith("files-changed:")'
}
