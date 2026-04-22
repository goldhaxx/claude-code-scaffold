#!/usr/bin/env bats
# Tests for the idea-upgrade feature.
# Covers:
#   - docs-check.sh title-from-body (AC-9..AC-12)
#   - docs-check.sh idea-upgrade (AC-1..AC-8)
#   - archive-only semantic on Linear-configured nodes (AC-13..AC-16)
#   - documentation + dispatch (AC-17..AC-18)

DOCS_CHECK="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.ccanvil"
}

teardown() {
  rm -rf "$PROJECT"
}

# =========================================================================
# AC-9, AC-12: title-from-body short-text fast path + empty body edge case
# =========================================================================

@test "AC-9: title-from-body returns single-line body <=80 chars verbatim" {
  run bash "$DOCS_CHECK" title-from-body "hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
}

@test "AC-9: title-from-body returns exactly-80-char single-line body verbatim" {
  body=$(printf 'x%.0s' {1..80})
  run bash "$DOCS_CHECK" title-from-body "$body"
  [ "$status" -eq 0 ]
  [ "$output" = "$body" ]
  [ "${#output}" -eq 80 ]
}

@test "AC-12: title-from-body returns empty string for empty body, exit 0" {
  run bash "$DOCS_CHECK" title-from-body ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-9: title-from-body accepts body on stdin" {
  run bash -c "echo 'piped body' | '$DOCS_CHECK' title-from-body"
  [ "$status" -eq 0 ]
  [ "$output" = "piped body" ]
}

# =========================================================================
# AC-10: title-from-body stochastic path + deterministic fallback
# =========================================================================

# Helper: create a fake `claude` CLI that echoes a fixed stdout.
# Prepends the fake-bin dir to PATH so `command -v claude` finds it first.
_mock_claude() {
  local reply="$1"
  local bindir="$PROJECT/fake-bin"
  mkdir -p "$bindir"
  cat > "$bindir/claude" <<EOF
#!/usr/bin/env bash
printf '%s' "$reply"
EOF
  chmod +x "$bindir/claude"
  export PATH="$bindir:$PATH"
}

# Helper: force no-claude environment by pointing PATH at an empty bin dir.
_no_claude() {
  local bindir="$PROJECT/empty-bin"
  mkdir -p "$bindir"
  # Keep system utilities (bash, jq, etc.) available — only drop claude.
  export PATH="$bindir:/usr/bin:/bin:/usr/sbin:/sbin"
}

@test "AC-10: long body falls back to first 80 chars when claude CLI absent" {
  _no_claude
  body=$(printf 'x%.0s' {1..200})  # 200 chars, single line
  run bash "$DOCS_CHECK" title-from-body "$body"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 80 ]
  [ "$output" = "$(printf 'x%.0s' {1..80})" ]
}

@test "AC-10: multi-line body falls back to first 80 chars of first line when claude CLI absent" {
  _no_claude
  body=$'first line content\nsecond line\nthird'
  run bash "$DOCS_CHECK" title-from-body "$body"
  [ "$status" -eq 0 ]
  [ "$output" = "first line content" ]
}

@test "AC-10: long body uses claude CLI when available, output bounded to 80 chars" {
  _mock_claude "Synthesized concise title from long body"
  body=$(printf 'long idea body text that exceeds eighty characters by a comfortable margin for testing purposes')
  run bash "$DOCS_CHECK" title-from-body "$body"
  [ "$status" -eq 0 ]
  [ "$output" = "Synthesized concise title from long body" ]
  [ "${#output}" -le 80 ]
}

@test "AC-10: claude CLI output longer than 80 chars is truncated to 80 chars" {
  long_reply=$(printf 'Y%.0s' {1..200})
  _mock_claude "$long_reply"
  body=$'first\nsecond\nthird line that makes this multi-line so it hits the stochastic path'
  run bash "$DOCS_CHECK" title-from-body "$body"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 80 ]
}
