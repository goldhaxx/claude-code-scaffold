#!/usr/bin/env bats
# BTS-504 — inject-telemetry-source.sh substrate tests.

bats_require_minimum_version 1.5.0

# BTS-497 telemetry hooks.
source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"
setup_file()    { telemetry_setup_file; }
teardown_file() { telemetry_teardown_file; }
setup()         { telemetry_setup; }
teardown()      { telemetry_teardown; }

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/inject-telemetry-source.sh"

# ---------------------------------------------------------------------------
# Step 1 — skeleton + manifest (AC-9)
# ---------------------------------------------------------------------------

@test "Step 1: inject-telemetry-source.sh exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "Step 1: --help prints supported invocation forms" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'classify'
  echo "$output" | grep -qE -- '--all'
  echo "$output" | grep -qE 'print-skip-list'
}

@test "Step 1: invalid subcommand exits 2 with usage on stderr" {
  run bash "$SCRIPT" not-a-real-subcommand
  [ "$status" -eq 2 ]
  echo "$output" | grep -qiE 'usage|unknown'
}

@test "AC-9: manifest entry present for the script (file-level @manifest)" {
  grep -qE "^\.ccanvil/scripts/inject-telemetry-source\.sh($|:)" .ccanvil/manifest-allowlist.txt \
    || { echo "manifest-allowlist.txt missing entry for inject-telemetry-source.sh" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Step 2 — classifier (AC-3): partition the 4-tuple boolean space.
# ---------------------------------------------------------------------------

FIX="$BATS_TEST_DIRNAME/fixtures/inject-telemetry"

@test "AC-3: classify cat-a fixture → A" {
  run bash "$SCRIPT" classify "$FIX/cat-a.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "A" ]
}

@test "AC-3: classify cat-b fixture → B" {
  run bash "$SCRIPT" classify "$FIX/cat-b.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "B" ]
}

@test "AC-3: classify cat-c fixture → C" {
  run bash "$SCRIPT" classify "$FIX/cat-c.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "C" ]
}

@test "AC-3: classify cat-e fixture → E" {
  run bash "$SCRIPT" classify "$FIX/cat-e.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "E" ]
}

@test "AC-3: classify cat-f fixture → F" {
  run bash "$SCRIPT" classify "$FIX/cat-f.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "F" ]
}

@test "AC-3: classify all-hooks fixture → UNCLASSIFIED" {
  run bash "$SCRIPT" classify "$FIX/all-hooks-unclassified.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "UNCLASSIFIED" ]
}

@test "AC-3: classify a skip-listed file → SKIP" {
  # telemetry-helper.bats is the documented skip-list entry (AC-5).
  run bash "$SCRIPT" classify "$BATS_TEST_DIRNAME/telemetry-helper.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "SKIP" ]
}

@test "AC-3: classify missing-file-arg → exit 2" {
  run bash "$SCRIPT" classify
  [ "$status" -eq 2 ]
  echo "$output" | grep -qiE 'usage'
}

@test "AC-3: classify non-existent file → exit 2 with file-not-found message" {
  run bash "$SCRIPT" classify "$BATS_TEST_TMPDIR/no-such.bats"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qiE 'not found|no such'
}

# ---------------------------------------------------------------------------
# Step 2 — print-skip-list (AC-5): single source of truth for the drift-guard.
# ---------------------------------------------------------------------------

@test "AC-5: print-skip-list emits at least telemetry-helper.bats" {
  run bash "$SCRIPT" print-skip-list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qFx 'telemetry-helper.bats'
}
