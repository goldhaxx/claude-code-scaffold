#!/usr/bin/env bats
# BTS-460 — drift-guard + behavior tests for cmd_test_suite_run.
#
# The test-suite-run dispatcher reads `.test-provider` (or `.stacks[0]`
# fallback, default `bats`) from `.claude/ccanvil.json` and exec's the
# corresponding runner. Today only `bats` is implemented; other providers
# exit 2 with an explicit not-yet-implemented stderr.

bats_require_minimum_version 1.5.0

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
}

# ---------------------------------------------------------------------------
# AC-3: unimplemented-provider error path
# ---------------------------------------------------------------------------
@test "test-suite-run: pytest provider exits 2 with not-yet-implemented stderr" {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'JSON'
{"test-provider": "pytest"}
JSON
  run --separate-stderr bash "$DC" test-suite-run --project-dir "$PROJECT_DIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"test-provider 'pytest' dispatcher not yet implemented"* ]]
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
