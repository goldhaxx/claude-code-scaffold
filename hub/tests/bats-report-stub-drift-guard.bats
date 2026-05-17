#!/usr/bin/env bats
#
# BTS-507 — drift-guard: any hub/tests/*.bats file that invokes
# `bash bats-report.sh ...` in a subshell MUST also source the helper
# `load _helpers/bats-report-stub` OR carry the literal exempt marker
# `# bats-report-stub: exempt` on a comment line. This file is itself
# exempt — it doesn't invoke bats-report.sh, it tests OTHER files'
# compliance with the rule.
#
# COVERAGE GAP: the literal-substring detection catches direct invocation
# and variable-assignment indirection (`SCRIPT=".../bats-report.sh"`). It
# does NOT catch dispatcher-forwarded paths where `bats-report.sh` never
# appears as a literal in the calling file — e.g., a test that invokes
# `docs-check.sh test-suite-run` which internally exec's bats-report.sh.
# Those cases require manual classification: the file author must KNOW the
# transitive dependency and add `load _helpers/bats-report-stub` directly.
# The drift-guard does not structurally enforce them. An abstract call-graph
# check would close the gap but is out of scope here (BTS-507 chose Path 1:
# grep-based detection with exempt markers, per the source ticket).
#
# bats-report-stub: exempt

bats_require_minimum_version 1.5.0

# Scan <dir>/*.bats (one level, non-recursive). For each file with a
# non-comment line containing the literal substring `bats-report.sh` (catches
# direct invocation, variable-assignment indirection, and dispatcher-forwarded
# invocation), emit a violation line `VIOLATION: <path>` unless the file ALSO
# contains a non-comment line with `load _helpers/bats-report-stub` OR carries
# the literal exempt marker `# bats-report-stub: exempt` on a comment line.
# Returns 0 with empty stdout when no violations; returns 1 with violations
# on stdout otherwise.
_scan_dir() {
  local dir="$1"
  local violations=""
  local f
  shopt -s nullglob
  for f in "$dir"/*.bats; do
    if grep -qE '^[[:space:]]*[^[:space:]#].*bats-report\.sh' "$f" 2>/dev/null; then
      if grep -qF 'load _helpers/bats-report-stub' "$f" 2>/dev/null; then
        continue
      fi
      if grep -qF '# bats-report-stub: exempt' "$f" 2>/dev/null; then
        continue
      fi
      violations+="VIOLATION: $f"$'\n'
    fi
  done
  shopt -u nullglob
  if [[ -n "$violations" ]]; then
    printf '%s' "$violations"
    return 1
  fi
  return 0
}

_make_fixture() {
  local path="$1" body="$2"
  printf '%s\n' "$body" > "$path"
}

@test "AC-5: compliant — invocation + helper load → no violations" {
  fx="$BATS_TEST_TMPDIR/compliant.bats"
  _make_fixture "$fx" '#!/usr/bin/env bats
load _helpers/bats-report-stub
setup() { stub_bats_report_prewarm; }
@test "x" { run bash .ccanvil/scripts/bats-report.sh fast.bats; }'
  run _scan_dir "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-6: exempt-marker — invocation + exempt comment → no violations" {
  fx="$BATS_TEST_TMPDIR/exempt.bats"
  _make_fixture "$fx" '#!/usr/bin/env bats
# bats-report-stub: exempt
@test "y" { run bash .ccanvil/scripts/bats-report.sh slow.bats; }'
  run _scan_dir "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-5: non-compliant — invocation without load or exempt → violation names file path" {
  fx="$BATS_TEST_TMPDIR/non-compliant.bats"
  _make_fixture "$fx" '#!/usr/bin/env bats
@test "z" { run bash .ccanvil/scripts/bats-report.sh fail.bats; }'
  run _scan_dir "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF "VIOLATION: $fx"
}

@test "AC-4: glob is one-level (non-recursive) — nested fixture ignored" {
  mkdir -p "$BATS_TEST_TMPDIR/sub"
  _make_fixture "$BATS_TEST_TMPDIR/sub/nested.bats" '#!/usr/bin/env bats
@test "n" { run bash .ccanvil/scripts/bats-report.sh fixture.bats; }'
  run _scan_dir "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-4: production scan — all hub/tests/*.bats compliant" {
  run _scan_dir "$BATS_TEST_DIRNAME"
  if [ "$status" -ne 0 ]; then
    echo "Drift-guard violations:" >&2
    echo "$output" >&2
  fi
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
