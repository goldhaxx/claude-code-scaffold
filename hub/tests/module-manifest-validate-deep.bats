#!/usr/bin/env bats
# BTS-239 Step 5: cmd_validate (deep / bidirectional) — AC-3 cont., AC-4 (5 remaining drift classes)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
  FIXTURES="$REPO_ROOT/hub/tests/fixtures/manifest"
}

# Helper: stage a single fixture file as the only source under .ccanvil/scripts.
_stage_fixture() {
  local proj="$1" fixture="$2" basename="$3"
  mkdir -p "$proj/.ccanvil/scripts" "$proj/.ccanvil"
  cp "$FIXTURES/$fixture" "$proj/.ccanvil/scripts/$basename"
}

@test "validate deep: valid-deep manifest exits 0" {
  set -e
  proj="$BATS_TEST_TMPDIR/proj"
  _stage_fixture "$proj" "valid-deep.sh" "valid-deep.sh"
  echo ".ccanvil/scripts/valid-deep.sh:valid_deep_func" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.covered == 1'
}

@test "validate deep: caller-not-found exits 2" {
  proj="$BATS_TEST_TMPDIR/proj"
  _stage_fixture "$proj" "caller-not-found.sh" "caller-not-found.sh"
  echo ".ccanvil/scripts/caller-not-found.sh:caller_not_found_func" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "caller-not-found" ]]
  [[ "$output" =~ "nonexistent_caller_func_xyz" ]]
}

@test "validate deep: depends-on-not-found exits 2" {
  proj="$BATS_TEST_TMPDIR/proj"
  _stage_fixture "$proj" "depends-on-not-found.sh" "depends-on-not-found.sh"
  echo ".ccanvil/scripts/depends-on-not-found.sh:depends_on_not_found_func" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "depends-on-not-found" ]]
  [[ "$output" =~ "nonexistent_dependency_xyz" ]]
}

@test "validate deep: missing-failure-mode-marker exits 2" {
  proj="$BATS_TEST_TMPDIR/proj"
  _stage_fixture "$proj" "missing-fm-marker.sh" "missing-fm-marker.sh"
  echo ".ccanvil/scripts/missing-fm-marker.sh:missing_fm_marker_func" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing-failure-mode-marker" ]]
  [[ "$output" =~ "orphan-fm" ]]
}

@test "validate deep: missing-side-effect-marker exits 2" {
  proj="$BATS_TEST_TMPDIR/proj"
  _stage_fixture "$proj" "missing-se-marker.sh" "missing-se-marker.sh"
  echo ".ccanvil/scripts/missing-se-marker.sh:missing_se_marker_func" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing-side-effect-marker" ]]
  [[ "$output" =~ "orphan-se" ]]
}
