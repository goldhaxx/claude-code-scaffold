#!/usr/bin/env bats
# BTS-181 — derive-pr-title substrate primitive.
#
# Factor PR-title derivation duplicated between cmd_activate and
# cmd_assert_pr_title into one cmd_derive_pr_title that emits
# `feat(<feature-id>): <truncated-summary>` to stdout.
#
# Truncation: first period strips suffix; remaining suffix capped at 80 chars.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/docs"
}

teardown() {
  rm -rf "$PROJECT"
}

# Write a spec at $1 with feature_id $2 and Summary first line $3.
_write_spec() {
  local path="$1"
  local feature_id="$2"
  local summary="$3"
  cat > "$path" <<EOF
# Feature: Test

> Feature: $feature_id
> Work: linear:BTS-X
> Created: 1700000000
> Status: Draft

## Summary

$summary

## Acceptance Criteria

- [ ] AC-1
EOF
}

# =========================================================================
# AC-1: happy path — emits feat(<id>): <first-line>
# =========================================================================

@test "AC-1: emits feat(<feature-id>): <first-line> from Summary" {
  set -e
  _write_spec "$PROJECT/docs/spec.md" "bts-x-test" "Short feature line."
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "feat(bts-x-test): Short feature line" ]
}

# =========================================================================
# AC-2: ≤80 chars, no period → verbatim
# =========================================================================

@test "AC-2: ≤80 chars without period emits verbatim" {
  set -e
  _write_spec "$PROJECT/docs/spec.md" "bts-x" "Short bare line"
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "feat(bts-x): Short bare line" ]
}

# =========================================================================
# AC-3: period-strip
# =========================================================================

@test "AC-3: first period strips remaining text" {
  set -e
  _write_spec "$PROJECT/docs/spec.md" "bts-x" "Add foo. Bar baz."
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "feat(bts-x): Add foo" ]
}

# =========================================================================
# AC-4: 80-char truncation when no period in first 80
# =========================================================================

@test "AC-4: long line without period or word-boundary in lookback truncates at 80 chars" {
  set -e
  # 120 chars of solid letters — no period, no spaces, no hyphens, so
  # BTS-182's word-boundary walk falls through and the hard 80-char cut applies.
  local line=""
  local i
  for (( i=0; i<120; i++ )); do line="${line}a"; done
  _write_spec "$PROJECT/docs/spec.md" "bts-x" "$line"
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  local expected_suffix="${line:0:80}"
  [ "$output" = "feat(bts-x): $expected_suffix" ]
  [[ ! "$output" =~ [[:space:]]$ ]]
}

# =========================================================================
# AC-5: empty Summary → activate-feature fallback
# =========================================================================

@test "AC-5: empty Summary section emits activate-feature fallback" {
  set -e
  cat > "$PROJECT/docs/spec.md" <<EOF
# Feature: Test

> Feature: bts-x-empty
> Work: linear:BTS-X
> Created: 1700000000
> Status: Draft

## Summary

## Acceptance Criteria

- [ ] AC-1
EOF
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "feat(bts-x-empty): activate feature" ]
}

# =========================================================================
# AC-6: missing/bad input → non-zero exit, no stdout
# =========================================================================

@test "AC-6: missing argument → non-zero exit, error on stderr, no stdout" {
  run --separate-stderr bash "$SCRIPT" derive-pr-title
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"missing"* || "$stderr" == *"derive-pr-title"* ]]
}

@test "AC-6: non-existent file → non-zero exit" {
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/does-not-exist.md"
  [ "$status" -ne 0 ]
}

# =========================================================================
# BTS-182 — word-boundary truncation
# =========================================================================

@test "BTS-182 AC-2: space at position 75 truncates suffix at the space" {
  set -e
  # 75 'a's + ' ' + 30 'b's = 106 chars, no period.
  local line=""
  local i
  for (( i=0; i<75; i++ )); do line="${line}a"; done
  line="${line} "
  for (( i=0; i<30; i++ )); do line="${line}b"; done
  _write_spec "$PROJECT/docs/spec.md" "bts-x" "$line"
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  # Suffix after `feat(bts-x): ` should be exactly 75 'a's (boundary char dropped).
  local prefix="feat(bts-x): "
  local suffix="${output#"$prefix"}"
  [ "${#suffix}" -eq 75 ]
  [[ ! "$suffix" =~ [[:space:]]$ ]]
}

@test "BTS-182 AC-3: hyphen at position 76 truncates and drops the hyphen" {
  set -e
  # 75 'a's + '-' + 30 'b's = 106 chars, no period, no spaces.
  local line=""
  local i
  for (( i=0; i<75; i++ )); do line="${line}a"; done
  line="${line}-"
  for (( i=0; i<30; i++ )); do line="${line}b"; done
  _write_spec "$PROJECT/docs/spec.md" "bts-x" "$line"
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  local prefix="feat(bts-x): "
  local suffix="${output#"$prefix"}"
  [ "${#suffix}" -eq 75 ]
  # Last char must NOT be a hyphen.
  [ "${suffix: -1}" != "-" ]
}

@test "BTS-182 AC-4: no boundary in lookback → falls back to hard 80-char cut" {
  set -e
  # 100 'a's, no spaces, no hyphens, no period.
  local line=""
  local i
  for (( i=0; i<100; i++ )); do line="${line}a"; done
  _write_spec "$PROJECT/docs/spec.md" "bts-x" "$line"
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  local prefix="feat(bts-x): "
  local suffix="${output#"$prefix"}"
  [ "${#suffix}" -eq 80 ]
}

@test "BTS-182 AC-5: period-strip happens BEFORE word-boundary logic" {
  set -e
  # `Add foo. ` + 100 'a's — period-strip drops everything after `Add foo`.
  local line="Add foo. "
  local i
  for (( i=0; i<100; i++ )); do line="${line}a"; done
  _write_spec "$PROJECT/docs/spec.md" "bts-x" "$line"
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "feat(bts-x): Add foo" ]
}

@test "BTS-182 AC-6: lookback window is parameterized as 'local lookback=8'" {
  set -e
  local start end
  start=$(grep -n '^cmd_derive_pr_title()' "$SCRIPT" | head -1 | cut -d: -f1)
  [ -n "$start" ]
  end=$(awk -v s="$start" 'NR > s && /^cmd_[a-z_]+\(\)/ { print NR; exit }' "$SCRIPT")
  [ -n "$end" ]
  sed -n "${start},${end}p" "$SCRIPT" | grep -qE '^\s*local\s+lookback=8\s*$'
}

@test "BTS-182 AC-7: trailing whitespace is trimmed after boundary cut" {
  set -e
  # 73 'a's + ' ' + 30 'b's — boundary at position 73, suffix should be 73 'a's, no trailing space.
  local line=""
  local i
  for (( i=0; i<73; i++ )); do line="${line}a"; done
  line="${line} "
  for (( i=0; i<30; i++ )); do line="${line}b"; done
  _write_spec "$PROJECT/docs/spec.md" "bts-x" "$line"
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ [[:space:]]$ ]]
}

@test "BTS-182 AC-8: empty Summary fallback unchanged (regression guard)" {
  set -e
  cat > "$PROJECT/docs/spec.md" <<EOF
# Feature: Test

> Feature: bts-x-empty
> Work: linear:BTS-X
> Created: 1700000000
> Status: Draft

## Summary

## Acceptance Criteria

- [ ] AC-1
EOF
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "feat(bts-x-empty): activate feature" ]
}

# =========================================================================
# AC-9: drift-guard — both call sites delegate to the primitive
# =========================================================================

@test "AC-9: cmd_activate no longer inlines the Summary sed extraction" {
  set -e
  # Find the line range of cmd_activate() and grep within it.
  local start end
  start=$(grep -n '^cmd_activate()' "$SCRIPT" | head -1 | cut -d: -f1)
  [ -n "$start" ]
  # End = next top-level `^cmd_` definition.
  end=$(awk -v s="$start" 'NR > s && /^cmd_[a-z_]+\(\)/ { print NR; exit }' "$SCRIPT")
  [ -n "$end" ]
  ! sed -n "${start},${end}p" "$SCRIPT" | grep -q "sed -n '/^## Summary"
}

@test "AC-9: cmd_assert_pr_title no longer inlines the Summary sed extraction" {
  set -e
  local start end
  start=$(grep -n '^cmd_assert_pr_title()' "$SCRIPT" | head -1 | cut -d: -f1)
  [ -n "$start" ]
  end=$(awk -v s="$start" 'NR > s && /^cmd_[a-z_]+\(\)/ { print NR; exit }' "$SCRIPT")
  [ -n "$end" ]
  ! sed -n "${start},${end}p" "$SCRIPT" | grep -q "sed -n '/^## Summary"
}

# =========================================================================
# BTS-236 AC-2: prefer `> Subject:` over Summary extraction
# =========================================================================

_write_spec_with_subject() {
  local path="$1"
  local feature_id="$2"
  local subject="$3"
  local summary="$4"
  cat > "$path" <<EOF
# Feature: Test

> Feature: $feature_id
> Work: linear:BTS-X
> Created: 1700000000
> Subject: $subject
> Status: Draft

## Summary

$summary

## Acceptance Criteria

- [ ] AC-1
EOF
}

@test "BTS-236 AC-2: cmd_derive_pr_title prefers > Subject: over Summary first-line" {
  set -e
  _write_spec_with_subject "$PROJECT/docs/spec.md" "bts-236-test" \
    "clean imperative line under 72 chars" \
    "This is a verbose multi-clause sentence in the Summary that would otherwise be truncated at 80 chars."
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "feat(bts-236-test): clean imperative line under 72 chars" ]
}

@test "BTS-236 AC-2: spec without > Subject: falls back to Summary first-line (regression)" {
  set -e
  _write_spec "$PROJECT/docs/spec.md" "bts-236-fallback" "Short legacy line."
  run bash "$SCRIPT" derive-pr-title "$PROJECT/docs/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "feat(bts-236-fallback): Short legacy line" ]
}

# =========================================================================
# BTS-236 AC-1, AC-5, AC-6: cmd_stamp_spec inserts > Subject:
# =========================================================================

@test "BTS-236 AC-1: cmd_stamp_spec inserts > Subject: derived from H1" {
  set -e
  mkdir -p "$PROJECT/docs/specs"
  cat > "$PROJECT/docs/specs/foo.md" <<'EOF'
# Feature: stasis-carry-forward gsub regex-escape fix

> Feature: foo
> Work: linear:BTS-X
> Created: PLACEHOLDER
> Status: Draft

## Summary

Body.
EOF
  run bash "$SCRIPT" stamp-spec --project-dir "$PROJECT" foo
  [ "$status" -eq 0 ]
  grep -q '^> Subject: stasis-carry-forward gsub regex-escape fix$' "$PROJECT/docs/specs/foo.md"
}

@test "BTS-236 AC-5: cmd_stamp_spec re-run is idempotent (no duplicate > Subject:)" {
  set -e
  mkdir -p "$PROJECT/docs/specs"
  cat > "$PROJECT/docs/specs/foo.md" <<'EOF'
# Feature: a clean H1 line

> Feature: foo
> Work: linear:BTS-X
> Created: PLACEHOLDER
> Status: Draft

## Summary

Body.
EOF
  bash "$SCRIPT" stamp-spec --project-dir "$PROJECT" foo >/dev/null
  bash "$SCRIPT" stamp-spec --project-dir "$PROJECT" foo >/dev/null
  count=$(grep -c '^> Subject:' "$PROJECT/docs/specs/foo.md")
  [ "$count" -eq 1 ]
}

@test "BTS-236 AC-6: cmd_stamp_spec on spec without H1 'Feature:' prefix skips Subject (graceful)" {
  set -e
  mkdir -p "$PROJECT/docs/specs"
  cat > "$PROJECT/docs/specs/bar.md" <<'EOF'
# Some Other Title

> Feature: bar
> Work: linear:BTS-X
> Created: PLACEHOLDER
> Status: Draft

## Summary

Body.
EOF
  run bash "$SCRIPT" stamp-spec --project-dir "$PROJECT" bar
  [ "$status" -eq 0 ]
  ! grep -q '^> Subject:' "$PROJECT/docs/specs/bar.md"
}

@test "BTS-236 AC-3: H1 longer than 72 chars is truncated with word-boundary walkback" {
  set -e
  mkdir -p "$PROJECT/docs/specs"
  cat > "$PROJECT/docs/specs/longh1.md" <<'EOF'
# Feature: this is a very long imperative title that exceeds seventy two characters in length easily

> Feature: longh1
> Work: linear:BTS-X
> Created: PLACEHOLDER
> Status: Draft

## Summary

Body.
EOF
  run bash "$SCRIPT" stamp-spec --project-dir "$PROJECT" longh1
  [ "$status" -eq 0 ]
  subject=$(grep '^> Subject:' "$PROJECT/docs/specs/longh1.md" | sed 's/^> Subject: //')
  # Subject must be <= 72 chars and end on a word boundary
  [ "${#subject}" -le 72 ]
  [[ ! "$subject" =~ [[:space:]]$ ]]
}

@test "BTS-236 drift: BTS-236 referenced inline in docs-check.sh" {
  grep -q "BTS-236" "$SCRIPT"
}
