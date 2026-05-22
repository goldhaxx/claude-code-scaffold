#!/usr/bin/env bats
# BTS-460 — drift-guard + behavior tests for cmd_test_suite_run.
#
# The test-suite-run dispatcher reads `.test-provider` (or `.stacks[0]`
# fallback, default `bats`) from `.claude/ccanvil.json` and exec's the
# corresponding runner. Today only `bats` is implemented; other providers
# exit 2 with an explicit not-yet-implemented stderr.
#
# bats-report-stub: exempt — `bats-report.sh` appears here only inside
# the per-test STUB script path and a `pr.md` content assertion; this file
# does not invoke the real bats-report.sh.

bats_require_minimum_version 1.5.0

# BTS-497 telemetry hooks.
source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"
setup_file()    { telemetry_setup_file; }
teardown_file() { telemetry_teardown_file; }
teardown()      { telemetry_teardown; }

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT_DIR="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJECT_DIR/.claude" "$PROJECT_DIR/.ccanvil"

  # BATS_REPORT_OVERRIDE stub: echo argv and exit 0. Lets bats-path tests
  # run without actually invoking the real bats suite.
  STUB="$BATS_TEST_TMPDIR/stub-bats-report.sh"
  cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
echo "STUB-ARGS: $*"
exit 0
STUB_EOF
  chmod +x "$STUB"
  export BATS_REPORT_OVERRIDE="$STUB"
  telemetry_setup
}

# ---------------------------------------------------------------------------
# Provider dispatch error paths — pytest missing-config + vitest unimplemented
# ---------------------------------------------------------------------------
@test "AC-4: pytest provider with no test-command exits 2 naming the missing key" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "pytest"}
JSON
  run --separate-stderr bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"test-command"* ]]
}

@test "test-suite-run: vitest provider exits 2 with not-yet-implemented stderr" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "vitest"}
JSON
  run --separate-stderr bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"vitest"* && "$stderr" == *"not yet implemented"* ]]
}

# ---------------------------------------------------------------------------
# BTS-558 — pytest dispatcher arm behavior
#
# Tests stub the node's `test-command` with a script that records its argv
# and exits with a controlled code. The config IS the injection seam — no
# BATS_REPORT_OVERRIDE-style env var needed for pytest.
# ---------------------------------------------------------------------------

# Write a pytest stub at $1 that echoes "PYTEST-ARGS: [<argv>]" and exits $2.
_write_pytest_stub() {
  local path="$1" code="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
echo "PYTEST-ARGS: [\$*]"
exit $code
EOF
  chmod +x "$path"
}

# BTS-127 strict-mode: bats 1.13 only fails a test on `[ ]`, `grep`, and
# regular-command non-zero exits — a mid-test `[[ ]]` is silently skipped.
# Substring assertions below use `grep` so they are enforced regardless of
# position in the test body.

@test "pytest AC-1: runs test-command, exits 0 on success, appends test-path" {
  PYSTUB="$BATS_TEST_TMPDIR/stub-pytest.sh"
  _write_pytest_stub "$PYSTUB" 0
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<JSON
{"test-provider": "pytest", "test-command": "$PYSTUB", "test-path": "src/"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'PYTEST-ARGS: [src/]'
}

@test "pytest AC-1: no test-path key runs test-command with no path arg" {
  PYSTUB="$BATS_TEST_TMPDIR/stub-pytest.sh"
  _write_pytest_stub "$PYSTUB" 0
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<JSON
{"test-provider": "pytest", "test-command": "$PYSTUB"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'PYTEST-ARGS: []'
}

@test "pytest AC-2: a failing pytest test makes the dispatcher exit non-zero" {
  PYSTUB="$BATS_TEST_TMPDIR/stub-pytest.sh"
  _write_pytest_stub "$PYSTUB" 1
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<JSON
{"test-provider": "pytest", "test-command": "$PYSTUB"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
}

@test "pytest AC-5: no tests collected (exit 5) normalizes to exit 1 with a clear message" {
  PYSTUB="$BATS_TEST_TMPDIR/stub-pytest.sh"
  _write_pytest_stub "$PYSTUB" 5
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<JSON
{"test-provider": "pytest", "test-command": "$PYSTUB"}
JSON
  run --separate-stderr bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -qF 'no tests collected'
}

@test "pytest AC-3: --parallel translates to -n auto (literal --parallel not forwarded)" {
  PYSTUB="$BATS_TEST_TMPDIR/stub-pytest.sh"
  _write_pytest_stub "$PYSTUB" 0
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<JSON
{"test-provider": "pytest", "test-command": "$PYSTUB"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --parallel
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF -- '--parallel'
  echo "$output" | grep -qF -- '-n auto'
}

@test "pytest AC-8: bats-only flags are dropped, never forwarded to pytest" {
  PYSTUB="$BATS_TEST_TMPDIR/stub-pytest.sh"
  _write_pytest_stub "$PYSTUB" 0
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<JSON
{"test-provider": "pytest", "test-command": "$PYSTUB"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" \
    --json --timings --progress --no-telemetry --slow-top 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'PYTEST-ARGS: []'
}

@test "pytest: positional/post-double-dash args reach pytest verbatim" {
  PYSTUB="$BATS_TEST_TMPDIR/stub-pytest.sh"
  _write_pytest_stub "$PYSTUB" 0
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<JSON
{"test-provider": "pytest", "test-command": "$PYSTUB"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --parallel -- -k foo
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF -- '-n auto'
  echo "$output" | grep -qF -- '-k foo'
}

# ---------------------------------------------------------------------------
# AC-1: config resolution paths
# ---------------------------------------------------------------------------
@test "test-suite-run: missing config defaults to bats provider" {
  # No .claude/ccanvil.json at all → default to bats. With --parallel flag
  # the bats dispatch path runs (stub returns 0).
  rm -f "$PROJECT_DIR/.claude/ccanvil.json"
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --parallel
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB-ARGS: --parallel"* ]]
}

@test "test-suite-run: stacks[0]='bats' resolves to bats provider (no test-provider key)" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"stacks": ["bats"]}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --parallel
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB-ARGS: --parallel"* ]]
}

@test "test-suite-run: bats provider with NO forward args exits 2 with Usage (no-args trap)" {
  # BTS-212 + recursion guard: invoking without any forwarding flag or
  # target must NOT silently run the full bats suite.
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "bats"}
JSON
  run --separate-stderr bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == Usage:* ]]
}

@test "test-suite-run: explicit test-provider beats stacks[0]" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "pytest", "stacks": ["bats"]}
JSON
  run --separate-stderr bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"pytest"* ]]
}

@test "test-suite-run: unknown flag exits 2 with Usage:" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "bats"}
JSON
  run --separate-stderr bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --bogus-flag-xyz
  [ "$status" -eq 2 ]
  [[ "$stderr" == Usage:* ]]
}

# ---------------------------------------------------------------------------
# AC-2 + AC-7: bats provider dispatch + arg pass-through
# ---------------------------------------------------------------------------
@test "test-suite-run: bats provider forwards --parallel --progress to runner" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "bats"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --parallel --progress
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB-ARGS: --parallel --progress"* ]]
}

@test "test-suite-run: bats provider forwards --json to runner" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "bats"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB-ARGS: --json"* ]]
}

@test "test-suite-run: --slow-top with N forwards both tokens" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "bats"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --slow-top 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB-ARGS: --slow-top 5"* ]]
}

@test "test-suite-run: --slow-top with NO arg exits 2 with Usage:" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "bats"}
JSON
  run --separate-stderr bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" --slow-top
  [ "$status" -eq 2 ]
  [[ "$stderr" == Usage:* ]]
}

@test "test-suite-run: positional args pass through to runner" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "bats"}
JSON
  run bash "$DC" test-suite-run --project-dir "$PROJECT_DIR" -- hub/tests/foo.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB-ARGS: hub/tests/foo.bats"* ]]
}

# ---------------------------------------------------------------------------
# Regression: existing hub config (stacks: ["bats"]) → bats dispatch
# ---------------------------------------------------------------------------
@test "test-suite-run: --project-dir defaults to . when omitted" {
  # When --project-dir is omitted, cwd is used. Run from PROJECT_DIR with a
  # forward arg so the bats dispatch path is exercised (not the no-args trap).
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"stacks": ["bats"]}
JSON
  (
    cd "$PROJECT_DIR"
    bash "$DC" test-suite-run --parallel
  )
  status=$?
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-4: doc-drift — /pr skill calls dispatcher, not hardcoded bats-report.sh
# ---------------------------------------------------------------------------
PR_MD="$BATS_TEST_DIRNAME/../../.claude/commands/pr.md"

@test "AC-4: pr.md calls test-suite-run dispatcher" {
  grep -qF 'docs-check.sh test-suite-run' "$PR_MD"
}

@test "AC-4: pr.md no longer hardcodes bats-report.sh --parallel --progress" {
  ! grep -qF 'bats-report.sh --parallel --progress' "$PR_MD"
}

@test "AC-4: pr.md preserves BTS-118 single-invocation explanatory text" {
  grep -qF 'single-invocation discipline' "$PR_MD"
}

@test "AC-4: pr.md preserves BTS-383 streaming-progress explanatory text" {
  grep -qF '30s-idle heartbeat' "$PR_MD"
}

# ---------------------------------------------------------------------------
# AC-5: doc-drift — configuration.md documents the pattern + inventory
# ---------------------------------------------------------------------------
CFG_MD="$BATS_TEST_DIRNAME/../../.ccanvil/guide/configuration.md"

@test "AC-5: configuration.md has 'Hub describes behavior' section heading" {
  grep -qF 'Hub describes behavior, node describes implementation' "$CFG_MD"
}

@test "AC-5: configuration.md cites test-provider key" {
  grep -qF 'test-provider' "$CFG_MD"
}

@test "AC-5: configuration.md cites test-suite-run verb" {
  grep -qF 'test-suite-run' "$CFG_MD"
}

@test "AC-5: configuration.md lists tdd.md as captured leak-site follow-up" {
  grep -qF '.claude/rules/tdd.md' "$CFG_MD"
}
