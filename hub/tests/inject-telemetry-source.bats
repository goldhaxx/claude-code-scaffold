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

@test "AC-3: classify cat-g fixture → G" {
  run bash "$SCRIPT" classify "$FIX/cat-g.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "G" ]
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

# ---------------------------------------------------------------------------
# Step 3 — Cat A wiring (AC-1 partial).
# Reference: hub/tests/canonical-fixtures.bats:12-17.
# ---------------------------------------------------------------------------

_setup_cat_a_copy() {
  # Copy the Cat A fixture into a writable tmp file (the fixture itself must
  # stay pristine for re-use across tests).
  cp "$FIX/cat-a.bats" "$BATS_TEST_TMPDIR/cat-a.bats"
  echo "$BATS_TEST_TMPDIR/cat-a.bats"
}

@test "AC-1 (Cat A): wiring injects source line + 4 wrappers in order" {
  target=$(_setup_cat_a_copy)
  run bash "$SCRIPT" "$target"
  [ "$status" -eq 0 ]
  # Source line present.
  grep -qE '^source "\$BATS_TEST_DIRNAME/_helpers/telemetry\.bash"$' "$target"
  # All 4 lifecycle wrappers present.
  grep -qE '^setup_file\(\)[[:space:]]*\{.*telemetry_setup_file' "$target"
  grep -qE '^teardown_file\(\)[[:space:]]*\{.*telemetry_teardown_file' "$target"
  grep -qE '^setup\(\)[[:space:]]*\{.*telemetry_setup' "$target"
  grep -qE '^teardown\(\)[[:space:]]*\{.*telemetry_teardown' "$target"
}

@test "AC-1 (Cat A): source line appears AFTER bats_require_minimum_version" {
  target=$(_setup_cat_a_copy)
  bash "$SCRIPT" "$target"
  bats_line=$(grep -n '^bats_require_minimum_version' "$target" | head -1 | cut -d: -f1)
  source_line=$(grep -n '^source.*telemetry\.bash' "$target" | head -1 | cut -d: -f1)
  [ -n "$bats_line" ] && [ -n "$source_line" ]
  [ "$source_line" -gt "$bats_line" ]
}

@test "AC-1 (Cat A): existing @test block is preserved" {
  target=$(_setup_cat_a_copy)
  bash "$SCRIPT" "$target"
  grep -qF '@test "cat-a fixture: trivial test passes"' "$target"
}

@test "AC-1 (Cat A): post-wiring file still parses as valid bats" {
  target=$(_setup_cat_a_copy)
  bash "$SCRIPT" "$target"
  # Disabled mode keeps the helper a no-op so we don't need the OTel stack.
  CCANVIL_TELEMETRY_DISABLED=1 run bats "$target"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Step 4 — Cat B / C / E / F wiring (AC-1 full, including order sensitivity).
# ---------------------------------------------------------------------------

_setup_copy() {
  # $1 = category letter (a|b|c|e|f). Returns absolute path of tmp copy.
  cp "$FIX/cat-$1.bats" "$BATS_TEST_TMPDIR/cat-$1.bats"
  echo "$BATS_TEST_TMPDIR/cat-$1.bats"
}

# Cat B — setup() only → APPEND telemetry_setup; ADD setup_file/teardown_file/teardown.
@test "AC-1 (Cat B): telemetry_setup APPENDED to existing setup body" {
  target=$(_setup_copy b)
  run bash "$SCRIPT" "$target"
  [ "$status" -eq 0 ]
  # telemetry_setup must appear AFTER the existing EXAMPLE_VAR assignment
  # but BEFORE the closing brace of the setup() function.
  existing_line=$(grep -n 'EXAMPLE_VAR="hello"' "$target" | head -1 | cut -d: -f1)
  telemetry_line=$(grep -n '^[[:space:]]*telemetry_setup[[:space:]]*$' "$target" | head -1 | cut -d: -f1)
  [ -n "$existing_line" ] && [ -n "$telemetry_line" ]
  [ "$telemetry_line" -gt "$existing_line" ]
}

@test "AC-1 (Cat B): ADD setup_file, teardown_file, teardown wrappers" {
  target=$(_setup_copy b)
  bash "$SCRIPT" "$target"
  grep -qE '^setup_file\(\)[[:space:]]*\{.*telemetry_setup_file' "$target"
  grep -qE '^teardown_file\(\)[[:space:]]*\{.*telemetry_teardown_file' "$target"
  grep -qE '^teardown\(\)[[:space:]]*\{.*telemetry_teardown' "$target"
}

@test "AC-1 (Cat B): post-wiring file still parses as valid bats" {
  target=$(_setup_copy b)
  bash "$SCRIPT" "$target"
  CCANVIL_TELEMETRY_DISABLED=1 run bats "$target"
  [ "$status" -eq 0 ]
}

# Cat C — setup() + teardown() → APPEND telemetry_setup; PREPEND telemetry_teardown;
# ADD setup_file/teardown_file.
@test "AC-1 (Cat C): telemetry_teardown PREPENDED to existing teardown body" {
  target=$(_setup_copy c)
  run bash "$SCRIPT" "$target"
  [ "$status" -eq 0 ]
  # telemetry_teardown must appear AFTER the teardown() opening line but
  # BEFORE the existing `unset EXAMPLE_VAR` body.
  teardown_open=$(grep -n '^teardown()' "$target" | head -1 | cut -d: -f1)
  telemetry_line=$(grep -n '^[[:space:]]*telemetry_teardown[[:space:]]*$' "$target" | head -1 | cut -d: -f1)
  unset_line=$(grep -n 'unset EXAMPLE_VAR' "$target" | head -1 | cut -d: -f1)
  [ "$telemetry_line" -gt "$teardown_open" ]
  [ "$telemetry_line" -lt "$unset_line" ]
}

@test "AC-1 (Cat C): telemetry_setup APPENDED to existing setup body" {
  target=$(_setup_copy c)
  bash "$SCRIPT" "$target"
  existing=$(grep -n 'EXAMPLE_VAR="hello"' "$target" | head -1 | cut -d: -f1)
  telemetry=$(grep -n '^[[:space:]]*telemetry_setup[[:space:]]*$' "$target" | head -1 | cut -d: -f1)
  [ "$telemetry" -gt "$existing" ]
}

@test "AC-1 (Cat C): post-wiring file still parses as valid bats" {
  target=$(_setup_copy c)
  bash "$SCRIPT" "$target"
  CCANVIL_TELEMETRY_DISABLED=1 run bats "$target"
  [ "$status" -eq 0 ]
}

# Cat E — setup_file() + setup(), no teardown — PREPEND telemetry_setup_file;
# APPEND telemetry_setup; ADD teardown/teardown_file.
@test "AC-1 (Cat E): telemetry_setup_file PREPENDED to existing setup_file body" {
  target=$(_setup_copy e)
  run bash "$SCRIPT" "$target"
  [ "$status" -eq 0 ]
  setup_file_open=$(grep -n '^setup_file()' "$target" | head -1 | cut -d: -f1)
  telemetry_line=$(grep -n '^[[:space:]]*telemetry_setup_file[[:space:]]*$' "$target" | head -1 | cut -d: -f1)
  existing=$(grep -n 'EXAMPLE_FILE_VAR' "$target" | head -1 | cut -d: -f1)
  [ "$telemetry_line" -gt "$setup_file_open" ]
  [ "$telemetry_line" -lt "$existing" ]
}

@test "AC-1 (Cat E): ADD teardown + teardown_file wrappers" {
  target=$(_setup_copy e)
  bash "$SCRIPT" "$target"
  grep -qE '^teardown\(\)[[:space:]]*\{.*telemetry_teardown' "$target"
  grep -qE '^teardown_file\(\)[[:space:]]*\{.*telemetry_teardown_file' "$target"
}

@test "AC-1 (Cat E): post-wiring file still parses as valid bats" {
  target=$(_setup_copy e)
  bash "$SCRIPT" "$target"
  CCANVIL_TELEMETRY_DISABLED=1 run bats "$target"
  [ "$status" -eq 0 ]
}

# Cat F — setup_file() + teardown_file() only → PREPEND telemetry_setup_file;
# APPEND telemetry_teardown_file; ADD setup/teardown.
@test "AC-1 (Cat F): telemetry_setup_file PREPENDED, telemetry_teardown_file APPENDED" {
  target=$(_setup_copy f)
  run bash "$SCRIPT" "$target"
  [ "$status" -eq 0 ]
  # Prepend on setup_file.
  sf_open=$(grep -n '^setup_file()' "$target" | head -1 | cut -d: -f1)
  pre_t=$(grep -n '^[[:space:]]*telemetry_setup_file[[:space:]]*$' "$target" | head -1 | cut -d: -f1)
  [ "$pre_t" -gt "$sf_open" ]
  # Append on teardown_file.
  tf_open=$(grep -n '^teardown_file()' "$target" | head -1 | cut -d: -f1)
  tf_close_after=$(awk -v start="$tf_open" 'NR > start && /^}/ { print NR; exit }' "$target")
  append_t=$(grep -n '^[[:space:]]*telemetry_teardown_file[[:space:]]*$' "$target" | head -1 | cut -d: -f1)
  [ "$append_t" -gt "$tf_open" ]
  [ "$append_t" -lt "$tf_close_after" ]
}

@test "AC-1 (Cat F): ADD setup + teardown wrappers" {
  target=$(_setup_copy f)
  bash "$SCRIPT" "$target"
  grep -qE '^setup\(\)[[:space:]]*\{.*telemetry_setup' "$target"
  grep -qE '^teardown\(\)[[:space:]]*\{.*telemetry_teardown' "$target"
}

@test "AC-1 (Cat F): post-wiring file still parses as valid bats" {
  target=$(_setup_copy f)
  bash "$SCRIPT" "$target"
  CCANVIL_TELEMETRY_DISABLED=1 run bats "$target"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Step 9 — Heredoc-protected function bodies (regression guard).
# The state-machine MUST NOT treat a heredoc-internal bare `}` as the
# function close. Anchored on the BTS-504 Step 9 rollout regression.
# ---------------------------------------------------------------------------

@test "AC-1 (heredoc): bare-} inside heredoc body NOT misread as function close" {
  cp "$FIX/cat-c-heredoc.bats" "$BATS_TEST_TMPDIR/cat-c-heredoc.bats"
  target="$BATS_TEST_TMPDIR/cat-c-heredoc.bats"
  run bash "$SCRIPT" "$target"
  [ "$status" -eq 0 ]
  # telemetry_setup must appear AFTER EXAMPLE_VAR="hello" (the real setup
  # body's tail), not after the heredoc-internal `}`. Equivalently:
  # telemetry_setup must appear AFTER `EOF` (which ends the heredoc) AND
  # AFTER EXAMPLE_VAR (which follows EOF in the existing body).
  eof_line=$(grep -n '^EOF$' "$target" | head -1 | cut -d: -f1)
  example=$(grep -n 'EXAMPLE_VAR="hello"' "$target" | head -1 | cut -d: -f1)
  telemetry=$(grep -n '^[[:space:]]*telemetry_setup[[:space:]]*$' "$target" | head -1 | cut -d: -f1)
  [ -n "$eof_line" ] && [ -n "$example" ] && [ -n "$telemetry" ]
  [ "$telemetry" -gt "$eof_line" ]
  [ "$telemetry" -gt "$example" ]
  CCANVIL_TELEMETRY_DISABLED=1 run bats "$target"
  [ "$status" -eq 0 ]
}

# Cat G — teardown() only → PREPEND telemetry_teardown; ADD setup_file/teardown_file/setup.
@test "AC-1 (Cat G): telemetry_teardown PREPENDED to existing teardown body" {
  target=$(_setup_copy g)
  run bash "$SCRIPT" "$target"
  [ "$status" -eq 0 ]
  teardown_open=$(grep -n '^teardown()' "$target" | head -1 | cut -d: -f1)
  telemetry_line=$(grep -n '^[[:space:]]*telemetry_teardown[[:space:]]*$' "$target" | head -1 | cut -d: -f1)
  unset_line=$(grep -n 'unset EXAMPLE_VAR' "$target" | head -1 | cut -d: -f1)
  [ "$telemetry_line" -gt "$teardown_open" ]
  [ "$telemetry_line" -lt "$unset_line" ]
}

@test "AC-1 (Cat G): ADD setup_file + teardown_file + setup wrappers" {
  target=$(_setup_copy g)
  bash "$SCRIPT" "$target"
  grep -qE '^setup_file\(\)[[:space:]]*\{.*telemetry_setup_file' "$target"
  grep -qE '^teardown_file\(\)[[:space:]]*\{.*telemetry_teardown_file' "$target"
  grep -qE '^setup\(\)[[:space:]]*\{.*telemetry_setup' "$target"
}

@test "AC-1 (Cat G): post-wiring file still parses as valid bats" {
  target=$(_setup_copy g)
  bash "$SCRIPT" "$target"
  CCANVIL_TELEMETRY_DISABLED=1 run bats "$target"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Step 5 — Idempotency (AC-2): re-running on a wired file is byte-identical.
# ---------------------------------------------------------------------------

@test "AC-2 (Cat A): re-running injector on already-wired file is byte-identical no-op" {
  target=$(_setup_copy a)
  bash "$SCRIPT" "$target"        # first wire
  pre_sha=$(shasum -a 256 "$target" | awk '{print $1}')
  run bash "$SCRIPT" "$target"    # second invocation
  [ "$status" -eq 0 ]
  post_sha=$(shasum -a 256 "$target" | awk '{print $1}')
  [ "$pre_sha" = "$post_sha" ]
}

@test "AC-2 (Cat C): idempotency holds on multi-directive wiring" {
  target=$(_setup_copy c)
  bash "$SCRIPT" "$target"
  pre_sha=$(shasum -a 256 "$target" | awk '{print $1}')
  bash "$SCRIPT" "$target"
  post_sha=$(shasum -a 256 "$target" | awk '{print $1}')
  [ "$pre_sha" = "$post_sha" ]
}

@test "AC-2 (Cat G): idempotency on PREPEND-to-teardown path" {
  target=$(_setup_copy g)
  bash "$SCRIPT" "$target"
  pre_sha=$(shasum -a 256 "$target" | awk '{print $1}')
  bash "$SCRIPT" "$target"
  post_sha=$(shasum -a 256 "$target" | awk '{print $1}')
  [ "$pre_sha" = "$post_sha" ]
}

# ---------------------------------------------------------------------------
# Step 6 — UNCLASSIFIED error path (AC-7).
# ---------------------------------------------------------------------------

@test "AC-7: UNCLASSIFIED file → exit 3 + stderr UNCLASSIFIED + file unchanged" {
  target="$BATS_TEST_TMPDIR/all-hooks.bats"
  cp "$FIX/all-hooks-unclassified.bats" "$target"
  pre_sha=$(shasum -a 256 "$target" | awk '{print $1}')
  run bash "$SCRIPT" "$target"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qE '^UNCLASSIFIED:'
  post_sha=$(shasum -a 256 "$target" | awk '{print $1}')
  [ "$pre_sha" = "$post_sha" ]
}

# ---------------------------------------------------------------------------
# Step 7 — Bulk --all + JSON report (AC-4, AC-5).
# ---------------------------------------------------------------------------

_setup_bulk_root() {
  # Build a tmp root with one fixture per category + skip-listed + unclassified.
  local root="$BATS_TEST_TMPDIR/bulk"
  mkdir -p "$root"
  cp "$FIX/cat-a.bats" "$root/cat-a.bats"
  cp "$FIX/cat-b.bats" "$root/cat-b.bats"
  cp "$FIX/cat-c.bats" "$root/cat-c.bats"
  cp "$FIX/cat-e.bats" "$root/cat-e.bats"
  cp "$FIX/cat-f.bats" "$root/cat-f.bats"
  cp "$FIX/cat-g.bats" "$root/cat-g.bats"
  cp "$FIX/cat-a.bats" "$root/telemetry-helper.bats"  # skip-listed
  echo "$root"
}

@test "AC-4: --all clean root → wires every cat fixture, exits 0, reports counts" {
  root=$(_setup_bulk_root)
  run bash "$SCRIPT" --all --root "$root"
  [ "$status" -eq 0 ]
  # JSON report — parse and check each count.
  wired=$(echo "$output" | jq -r '.wired')
  already=$(echo "$output" | jq -r '.already_wired')
  skipped=$(echo "$output" | jq -r '.skipped')
  unclassified=$(echo "$output" | jq -r '.unclassified')
  [ "$wired" -eq 6 ]
  [ "$already" -eq 0 ]
  [ "$skipped" -eq 1 ]
  [ "$unclassified" -eq 0 ]
  # Skip-listed file MUST remain unwired.
  ! grep -qE '^source.*telemetry\.bash' "$root/telemetry-helper.bats"
  # All 6 cat files MUST now contain the sourceline.
  for f in cat-a cat-b cat-c cat-e cat-f cat-g; do
    grep -qE '^source.*telemetry\.bash' "$root/$f.bats" \
      || { echo "$f.bats missing sourceline" >&2; return 1; }
  done
}

@test "AC-4: --all is idempotent (re-running counts every file as already_wired)" {
  root=$(_setup_bulk_root)
  bash "$SCRIPT" --all --root "$root" >/dev/null
  run bash "$SCRIPT" --all --root "$root"
  [ "$status" -eq 0 ]
  wired=$(echo "$output" | jq -r '.wired')
  already=$(echo "$output" | jq -r '.already_wired')
  [ "$wired" -eq 0 ]
  [ "$already" -eq 6 ]
}

@test "AC-4: --all with UNCLASSIFIED file → exits non-zero AND wires other files (accumulate-then-exit)" {
  root=$(_setup_bulk_root)
  cp "$FIX/all-hooks-unclassified.bats" "$root/all-hooks.bats"
  run bash "$SCRIPT" --all --root "$root"
  [ "$status" -eq 3 ]
  unclassified=$(echo "$output" | jq -r '.unclassified')
  wired=$(echo "$output" | jq -r '.wired')
  [ "$unclassified" -ge 1 ]
  [ "$wired" -eq 6 ]
  # The other (Cat) files were still wired despite the one UNCLASSIFIED.
  grep -qE '^source.*telemetry\.bash' "$root/cat-a.bats"
  # The UNCLASSIFIED file was left untouched.
  ! grep -qE '^source.*telemetry\.bash' "$root/all-hooks.bats"
}

@test "AC-4: --all reports unclassified file paths in the JSON envelope" {
  root=$(_setup_bulk_root)
  cp "$FIX/all-hooks-unclassified.bats" "$root/all-hooks.bats"
  run bash "$SCRIPT" --all --root "$root"
  unclassified_files=$(echo "$output" | jq -r '.unclassified_files[]')
  echo "$unclassified_files" | grep -qE 'all-hooks\.bats'
}
