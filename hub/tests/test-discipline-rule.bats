#!/usr/bin/env bats
#
# BTS-508 AC-4 / AC-5 — test-discipline.md atomized rule + references.
# Mirrors the BTS-387 atomized-rule pattern: tier-0 frontmatter, manifest
# block, bounded token budget, and operator-facing references from at least
# 4 consumer files.

bats_require_minimum_version 1.5.0

RULE="$BATS_TEST_DIRNAME/../../.claude/rules/test-discipline.md"

@test "AC-4: test-discipline.md exists" {
  [ -f "$RULE" ]
}

@test "AC-4: tier-0 universal frontmatter present" {
  set -e
  awk '/^---$/{c++; next} c==1' "$RULE" > "$BATS_TEST_TMPDIR/fm.yaml"
  grep -qE '^tier:[[:space:]]*0' "$BATS_TEST_TMPDIR/fm.yaml"
  grep -qE '^scope:[[:space:]]*(universal|hub)' "$BATS_TEST_TMPDIR/fm.yaml"
  grep -qE '^stack:[[:space:]]*any' "$BATS_TEST_TMPDIR/fm.yaml"
  grep -qE 'docs/research/test-discipline-research\.md' "$BATS_TEST_TMPDIR/fm.yaml"
}

@test "AC-4: manifest block present in frontmatter" {
  set -e
  awk '/^---$/{c++; next} c==1' "$RULE" > "$BATS_TEST_TMPDIR/fm.yaml"
  grep -qE '^manifest:' "$BATS_TEST_TMPDIR/fm.yaml"
  grep -qE '^[[:space:]]+id:[[:space:]]*test-discipline' "$BATS_TEST_TMPDIR/fm.yaml"
}

@test "AC-4: rule file size <= 900 tokens (rough token = words / 0.75)" {
  set -e
  local words tokens
  words=$(wc -w < "$RULE" | tr -d ' ')
  # Rough word→token conversion: 1 token ≈ 0.75 words. 900 tokens ≈ 675 words.
  tokens=$(( words * 4 / 3 ))
  if (( tokens > 900 )); then
    echo "rule body ~$tokens tokens (>900); trim required" >&2
    return 1
  fi
}

@test "AC-5: rule referenced from review.md" {
  grep -qF 'test-discipline.md' "$BATS_TEST_DIRNAME/../../.claude/commands/review.md"
}

@test "AC-5: rule referenced from pr.md" {
  grep -qF 'test-discipline.md' "$BATS_TEST_DIRNAME/../../.claude/commands/pr.md"
}

@test "AC-5: rule referenced from stasis SKILL.md" {
  grep -qF 'test-discipline.md' "$BATS_TEST_DIRNAME/../../.claude/skills/stasis/SKILL.md"
}

@test "AC-5: rule referenced from tdd.md" {
  grep -qF 'test-discipline.md' "$BATS_TEST_DIRNAME/../../.claude/rules/tdd.md"
}
