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
