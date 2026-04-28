#!/usr/bin/env bats
# BTS-239 Step 4: cmd_validate (foundation) — AC-3 base, AC-4 (missing-key class)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
  FIXTURES="$REPO_ROOT/hub/tests/fixtures/manifest"
}

@test "validate: empty allowlist exits 0 with coverage 0/0" {
  set -e
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil"
  printf '# only-comment\n' > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.covered == 0'
  echo "$output" | jq -e '.coverage.total == 0'
  echo "$output" | jq -e '.status == "ok"'
}

@test "validate: missing allowlist file is treated as empty (exit 0)" {
  set -e
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.total == 0'
}

@test "validate: allowlist with valid entry exits 0" {
  set -e
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil/scripts" "$proj/.ccanvil"
  cp "$FIXTURES/two-blocks.sh" "$proj/.ccanvil/scripts/file-a.sh"
  echo ".ccanvil/scripts/file-a.sh:func_one" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.covered == 1'
  echo "$output" | jq -e '.coverage.total == 1'
  echo "$output" | jq -e '.status == "ok"'
}

@test "validate: missing required key (purpose) exits 2 with DRIFT stderr" {
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil/scripts" "$proj/.ccanvil"
  cat > "$proj/.ccanvil/scripts/no-purpose.sh" <<'FIXTURE'
#!/usr/bin/env bash
# @manifest
# input: stdin
# output: stdout
# side-effect: foo
# failure-mode: x | exit=1 | visible=stderr
# contract: idempotent
# anchor: BTS-239
no_purpose_func() {
  return 0
}
FIXTURE
  echo ".ccanvil/scripts/no-purpose.sh:no_purpose_func" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "DRIFT" ]]
  [[ "$output" =~ "missing-required-key" ]]
  [[ "$output" =~ "purpose" ]]
}

@test "validate: missing manifest entry exits 2 with manifest-not-found" {
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil/scripts" "$proj/.ccanvil"
  cp "$FIXTURES/two-blocks.sh" "$proj/.ccanvil/scripts/file-a.sh"
  echo ".ccanvil/scripts/file-a.sh:func_does_not_exist" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "manifest-not-found" ]]
}

@test "validate: file-not-found exits 2" {
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil"
  echo ".ccanvil/scripts/missing.sh:cmd_x" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "file-not-found" ]]
}

@test "validate: comments and blank lines in allowlist are ignored" {
  set -e
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil/scripts" "$proj/.ccanvil"
  cp "$FIXTURES/two-blocks.sh" "$proj/.ccanvil/scripts/file-a.sh"
  cat > "$proj/.ccanvil/manifest-allowlist.txt" <<'AL'
# Comment line

  # Indented comment

.ccanvil/scripts/file-a.sh:func_one

# Trailing comment
AL
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.total == 1'
}
