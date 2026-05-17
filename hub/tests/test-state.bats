#!/usr/bin/env bats
#
# BTS-508 — test-state verb in docs-check.sh.
# Covers AC-6 (envelope shape + intersection logic), AC-9 (fail-safe on
# missing/malformed state file), and AC-7 (state writers in bats-report.sh +
# module-manifest.sh validate).

bats_require_minimum_version 1.5.0

load _helpers/bats-report-stub

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"
REPORT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"
MANIFEST="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/module-manifest.sh"

setup() {
  stub_bats_report_prewarm
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

# ----------------------------------------------------------------------------
# AC-7: state writers in bats-report.sh + module-manifest.sh validate
# ----------------------------------------------------------------------------

@test "AC-7: bats-report.sh writes last_full_suite_* on exit-0 with BATS_REPORT_FULL_SUITE=1" {
  set -e
  cat > "$BATS_TEST_TMPDIR/pass.bats" <<'BATS'
@test "t" { [ 1 -eq 1 ]; }
BATS
  echo content > file.txt
  _commit init
  sha=$(git rev-parse HEAD)

  mkdir -p .ccanvil/state
  BATS_REPORT_STATE_DIR=".ccanvil/state" \
    BATS_REPORT_FULL_SUITE=1 \
    bash "$REPORT" --no-telemetry "$BATS_TEST_TMPDIR/pass.bats" >/dev/null 2>&1

  [ -f .ccanvil/state/test-state.json ]
  jq -e --arg sha "$sha" '.last_full_suite_commit == $sha' < .ccanvil/state/test-state.json
  jq -e '.last_full_suite_at | type == "number"' < .ccanvil/state/test-state.json
}

@test "AC-7: bats-report.sh skips state-write when BATS_REPORT_FULL_SUITE unset (BTS-507 helper-stub coexistence)" {
  set -e
  cat > "$BATS_TEST_TMPDIR/pass.bats" <<'BATS'
@test "t" { [ 1 -eq 1 ]; }
BATS
  echo content > file.txt
  _commit init

  mkdir -p .ccanvil/state
  # Explicitly unset BATS_REPORT_FULL_SUITE — when /pr → test-suite-run is
  # the outer process, the env var leaks down into the bats workers running
  # this @test. We're exercising the bare bats-report.sh path where the
  # gate var is NOT set, which is the BTS-507 helper-stub / TDD-inner-loop
  # invocation shape.
  env -u BATS_REPORT_FULL_SUITE \
    BATS_REPORT_STATE_DIR=".ccanvil/state" \
    bash "$REPORT" --no-telemetry "$BATS_TEST_TMPDIR/pass.bats" >/dev/null 2>&1

  # Unconditional assertion: either no state file at all, OR a state file
  # without last_full_suite_commit populated. The earlier guarded form
  # passed vacuously when the file was absent and asserted nothing in the
  # success path.
  if [[ -f .ccanvil/state/test-state.json ]]; then
    jq -e '(.last_full_suite_commit // "") == ""' < .ccanvil/state/test-state.json
  else
    true  # absence is also a valid success
  fi
}

@test "AC-7: module-manifest.sh validate writes last_manifest_validate_* on exit-0" {
  set -e
  echo content > file.txt
  _commit init
  sha=$(git rev-parse HEAD)

  mkdir -p .ccanvil .ccanvil/state
  : > .ccanvil/manifest-allowlist.txt

  BATS_REPORT_STATE_DIR=".ccanvil/state" bash "$MANIFEST" validate --json >/dev/null 2>&1

  [ -f .ccanvil/state/test-state.json ]
  jq -e --arg sha "$sha" '.last_manifest_validate_commit == $sha' < .ccanvil/state/test-state.json
  jq -e '.last_manifest_validate_at | type == "number"' < .ccanvil/state/test-state.json
}

@test "AC-7: writers preserve each other's fields (atomic-by-replace)" {
  set -e
  cat > "$BATS_TEST_TMPDIR/pass.bats" <<'BATS'
@test "t" { [ 1 -eq 1 ]; }
BATS
  echo content > file.txt
  _commit init
  sha=$(git rev-parse HEAD)

  mkdir -p .ccanvil .ccanvil/state
  : > .ccanvil/manifest-allowlist.txt

  BATS_REPORT_STATE_DIR=".ccanvil/state" bash "$MANIFEST" validate --json >/dev/null 2>&1
  BATS_REPORT_STATE_DIR=".ccanvil/state" BATS_REPORT_FULL_SUITE=1 \
    bash "$REPORT" --no-telemetry "$BATS_TEST_TMPDIR/pass.bats" >/dev/null 2>&1

  # Both pairs of fields must be present after both writes.
  jq -e --arg sha "$sha" '.last_manifest_validate_commit == $sha' < .ccanvil/state/test-state.json
  jq -e --arg sha "$sha" '.last_full_suite_commit == $sha' < .ccanvil/state/test-state.json
}
