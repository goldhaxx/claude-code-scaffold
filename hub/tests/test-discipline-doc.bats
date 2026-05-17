#!/usr/bin/env bats
#
# BTS-508 — structural drift-guard for docs/research/test-discipline-research.md.
# Verifies the audit catalog covers every canonical invocation site of the
# long-running test substrates (bats-report.sh, module-manifest.sh validate,
# docs-check.sh test-suite-run) so future skill changes can't silently leave
# the research doc out of sync.
#
# Step 1 covers AC-1 (audit catalog). Steps 2/6 extend with redundancy /
# framework / rule assertions.
#
# bats-report-stub: exempt — this file only mentions bats-report.sh as a
# string token inside drift-guard assertions; it does not invoke the
# substrate, so the BTS-507 pre-warm stub is not required.

bats_require_minimum_version 1.5.0

DOC="$BATS_TEST_DIRNAME/../../docs/research/test-discipline-research.md"

@test "AC-1: research doc exists" {
  [ -f "$DOC" ]
}

@test "AC-1: doc has required top-level sections" {
  set -e
  grep -qE '^## Audit' "$DOC"
  grep -qE '^## Redundancy' "$DOC"
  grep -qE '^## Framework' "$DOC"
  grep -qE '^## Decision Tree' "$DOC"
}

@test "AC-1: audit catalog covers every canonical invocation site" {
  # Canonical invocation sites — each must appear as a row identifier in
  # the audit table. These are the production sites the framework gates
  # against (test fixtures, helper docs, and drift-guards excluded).
  set -e
  local sites=(
    ".claude/skills/stasis/SKILL.md"
    ".claude/skills/recall/SKILL.md"
    ".claude/commands/review.md"
    ".claude/commands/pr.md"
    ".claude/agents/code-reviewer.md"
  )
  local missing=""
  for site in "${sites[@]}"; do
    grep -qF "$site" "$DOC" || missing+="$site "
  done
  if [[ -n "$missing" ]]; then
    echo "Audit catalog missing rows for: $missing" >&2
    return 1
  fi
}

@test "AC-1: audit catalog cites all three substrates" {
  set -e
  grep -qF 'bats-report.sh' "$DOC"
  grep -qF 'module-manifest.sh validate' "$DOC"
  grep -qF 'test-suite-run' "$DOC"
}

@test "AC-2: redundancy analysis names >=3 overlap patterns" {
  set -e
  local count
  count=$(awk '/^## Redundancy/{flag=1; next} /^## /{flag=0} flag && /^### Pattern [0-9]+:/' "$DOC" | wc -l | tr -d ' ')
  [ "$count" -ge 3 ]
}

@test "AC-2: each redundancy pattern names duplicate sites and a candidate state-key" {
  set -e
  awk '/^## Redundancy/{flag=1; next} /^## /{flag=0} flag' "$DOC" > "$BATS_TEST_TMPDIR/red.md"
  # Each pattern block must reference at least one site path AND a state-key token.
  grep -qF '.claude/' "$BATS_TEST_TMPDIR/red.md"
  grep -qE 'last_(full_suite|manifest_validate)_(commit|at)' "$BATS_TEST_TMPDIR/red.md"
}

@test "AC-3: framework section contains the gate table with all 6 phases" {
  set -e
  awk '/^## Framework/{flag=1; next} /^## /{flag=0} flag' "$DOC" > "$BATS_TEST_TMPDIR/fw.md"
  local phases=(TDD-cycle pre-review pre-commit pre-merge session-boundary post-merge)
  local p
  for p in "${phases[@]}"; do
    grep -qF "$p" "$BATS_TEST_TMPDIR/fw.md" || { echo "missing phase: $p" >&2; return 1; }
  done
}

@test "AC-3: framework gate table has state/intent/scope columns" {
  set -e
  awk '/^## Framework/{flag=1; next} /^## /{flag=0} flag' "$DOC" > "$BATS_TEST_TMPDIR/fw.md"
  # Look for a markdown table header row containing all three column names.
  grep -qE '\| *Phase *\|.*State.*\|.*Intent.*\|.*Scope' "$BATS_TEST_TMPDIR/fw.md"
}

@test "AC-3: decision tree section has one tree per gate (>=6 gate headers)" {
  set -e
  local count
  count=$(awk '/^## Decision Tree/{flag=1; next} /^## /{flag=0} flag && /^### /' "$DOC" | wc -l | tr -d ' ')
  [ "$count" -ge 6 ]
}
