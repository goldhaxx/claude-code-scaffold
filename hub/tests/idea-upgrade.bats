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

# =========================================================================
# AC-11: title-from-body --title-map override
# =========================================================================

@test "AC-11: --title-map returns mapped title for matching body" {
  cat > "$PROJECT/map.json" <<'JSON'
{
  "some long body text that would otherwise hit the stochastic path": "Manual Title"
}
JSON
  body='some long body text that would otherwise hit the stochastic path'
  run bash "$DOCS_CHECK" title-from-body --title-map "$PROJECT/map.json" "$body"
  [ "$status" -eq 0 ]
  [ "$output" = "Manual Title" ]
}

@test "AC-11: --title-map falls through to fast path for unmapped body" {
  _no_claude
  cat > "$PROJECT/map.json" <<'JSON'
{"other body": "Other Title"}
JSON
  run bash "$DOCS_CHECK" title-from-body --title-map "$PROJECT/map.json" "short body"
  [ "$status" -eq 0 ]
  [ "$output" = "short body" ]
}

@test "AC-11: --title-map falls through to fallback for unmapped long body, no claude" {
  _no_claude
  cat > "$PROJECT/map.json" <<'JSON'
{"keyed body": "Keyed Title"}
JSON
  body=$(printf 'a%.0s' {1..150})
  run bash "$DOCS_CHECK" title-from-body --title-map "$PROJECT/map.json" "$body"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 80 ]
  [ "$output" = "$(printf 'a%.0s' {1..80})" ]
}

@test "AC-11: --title-map with missing file exits non-zero" {
  run bash "$DOCS_CHECK" title-from-body --title-map "$PROJECT/absent.json" "body"
  [ "$status" -ne 0 ]
  [[ "$output" = *"title-map"* ]]
}

# =========================================================================
# AC-1, AC-2: idea-upgrade command skeleton for both providers
# =========================================================================

# Helper: initialize $PROJECT as a minimal git repo.
_init_git() {
  git -C "$PROJECT" init -q -b main
  git -C "$PROJECT" config user.email "test@example.com"
  git -C "$PROJECT" config user.name "Test"
  git -C "$PROJECT" commit --allow-empty -q -m "init"
}

@test "AC-1: idea-upgrade --provider local writes config, .gitignore, commits" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider local "$PROJECT"
  [ "$status" -eq 0 ]

  # Config written with routing.idea = local
  run jq -r '.integrations.routing.idea' "$PROJECT/.claude/ccanvil.local.json"
  [ "$output" = "local" ]

  # .gitignore has the three expected entries
  grep -qxF ".ccanvil/ideas.log" "$PROJECT/.gitignore"
  grep -qxF ".ccanvil/ideas-pending.log" "$PROJECT/.gitignore"
  grep -qxF "docs/ideas.md" "$PROJECT/.gitignore"

  # Exactly one new commit with the expected message prefix
  run git -C "$PROJECT" log --oneline
  [ "$status" -eq 0 ]
  [[ "$output" = *"chore(idea-upgrade): configure local provider"* ]]
}

@test "AC-2: idea-upgrade --provider linear writes routing + provider config, commits" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]

  run jq -r '.integrations.routing.idea' "$PROJECT/.claude/ccanvil.local.json"
  [ "$output" = "linear" ]

  run jq -r '.integrations.providers.linear.team' "$PROJECT/.claude/ccanvil.local.json"
  [ "$output" = "Acme" ]

  run jq -r '.integrations.providers.linear.project' "$PROJECT/.claude/ccanvil.local.json"
  [ "$output" = "Alpha" ]

  run git -C "$PROJECT" log --oneline
  [[ "$output" = *"chore(idea-upgrade): configure linear provider"* ]]
}

# =========================================================================
# AC-8: idea-upgrade flag validation
# =========================================================================

@test "AC-8: --provider linear with no team or project exits non-zero" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" = *"ERROR: --provider linear requires --team and --project"* ]]
  # No commit was created — the baseline "init" commit is still the only one.
  run git -C "$PROJECT" log --oneline
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "AC-8: --provider linear with only --team exits non-zero" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" = *"ERROR: --provider linear requires --team and --project"* ]]
}

@test "AC-8: --provider linear with only --project exits non-zero" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --project "Alpha" "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" = *"ERROR: --provider linear requires --team and --project"* ]]
}

@test "AC-8: no --provider exits non-zero" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" = *"--provider is required"* ]]
}

@test "AC-8: unknown --provider exits non-zero" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider bogus "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" = *"unknown provider"* ]]
}
