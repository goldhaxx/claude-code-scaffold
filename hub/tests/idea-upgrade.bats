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

# =========================================================================
# AC-6: idea-upgrade --dry-run
# =========================================================================

@test "AC-6: --dry-run prints plan, makes no config/git changes" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider local --dry-run "$PROJECT"
  [ "$status" -eq 0 ]

  # Stdout contains the plan markers.
  [[ "$output" = *"DRY-RUN"* ]]
  [[ "$output" = *"ccanvil.local.json"* ]]
  [[ "$output" = *"chore(idea-upgrade)"* ]]

  # No config file created, no new commit.
  [ ! -f "$PROJECT/.claude/ccanvil.local.json" ]
  run git -C "$PROJECT" log --oneline
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "AC-6: --dry-run with --provider linear surfaces the linear plan" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team T --project P --dry-run "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" = *"DRY-RUN"* ]]
  [[ "$output" = *"linear"* ]]
  [[ "$output" = *"team=T"* ]]
  [[ "$output" = *"project=P"* ]]
  [ ! -f "$PROJECT/.claude/ccanvil.local.json" ]
}

# =========================================================================
# AC-3: --create-project intent emission
# =========================================================================

@test "AC-3: --create-project with --provider linear emits save_project intent" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" --create-project "$PROJECT"
  [ "$status" -eq 0 ]

  # Extract the JSON intent line from stdout.
  intent=$(echo "$output" | grep -E '^\{' | head -1)
  [ -n "$intent" ]

  # Validate shape: tool = save_project, params.team + params.name set.
  tool=$(echo "$intent" | jq -r '.tool')
  [ "$tool" = "mcp__claude_ai_Linear__save_project" ]

  team=$(echo "$intent" | jq -r '.params.team')
  [ "$team" = "Acme" ]

  name=$(echo "$intent" | jq -r '.params.name')
  [ "$name" = "Alpha" ]
}

@test "AC-3: --create-project without --provider linear exits non-zero" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider local --create-project "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" = *"--create-project requires --provider linear"* ]]
}

@test "AC-3: --create-project with --dry-run emits intent without committing" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team T --project P --create-project --dry-run "$PROJECT"
  [ "$status" -eq 0 ]
  intent=$(echo "$output" | grep -E '^\{' | head -1)
  [ -n "$intent" ]
  # No commit created.
  run git -C "$PROJECT" log --oneline
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

# =========================================================================
# AC-4, AC-5: idea-upgrade --from-legacy migration pipeline
# =========================================================================

# Helper: write a fixture docs/ideas.md with 3 entries (mix of short + long).
_fixture_legacy_ideas() {
  mkdir -p "$PROJECT/docs"
  cat > "$PROJECT/docs/ideas.md" <<'MD'
# Ideas

- [ ] a1b2 1700000000: short idea text <!-- status:new -->
- [ ] c3d4 1700000100: another short one <!-- status:new -->
- [ ] e5f6 1700000200: a considerably longer idea body that exceeds eighty characters because it contains a lot of deliberately verbose description <!-- status:promoted -->
MD
  git -C "$PROJECT" add docs/ideas.md
  git -C "$PROJECT" commit -q -m "add legacy ideas.md"
}

@test "AC-4: --from-legacy migrates entries with generated titles, removes source, one commit" {
  _init_git
  _fixture_legacy_ideas
  _no_claude  # force deterministic titles (fast path for short, fallback for long)

  baseline_count=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')

  run bash "$DOCS_CHECK" idea-upgrade --provider local --from-legacy "$PROJECT"
  [ "$status" -eq 0 ]

  # docs/ideas.md removed
  [ ! -f "$PROJECT/docs/ideas.md" ]

  # .ccanvil/ideas.log has 3 JSONL entries (plus optional archive header — 0 for local)
  [ -f "$PROJECT/.ccanvil/ideas.log" ]
  entry_count=$(grep -c '^{' "$PROJECT/.ccanvil/ideas.log" || true)
  [ "$entry_count" -eq 3 ]

  # Each entry has a non-empty title (generated via title-from-body).
  while IFS= read -r line; do
    title=$(echo "$line" | jq -r '.title')
    [ -n "$title" ]
    [ "${#title}" -le 80 ]
  done < <(grep '^{' "$PROJECT/.ccanvil/ideas.log")

  # Exactly one new commit on top of baseline ("add legacy ideas.md" + upgrade).
  new_count=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')
  [ "$new_count" -eq $((baseline_count + 1)) ]

  # Commit message mentions from-legacy path.
  run git -C "$PROJECT" log -1 --format=%s
  [[ "$output" = *"chore(idea-upgrade)"* ]]
  [[ "$output" = *"migrate"* ]]
}

@test "AC-5: --from-legacy without docs/ideas.md proceeds with config-only upgrade" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider local --from-legacy "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" = *"Nothing to migrate"* ]]

  # Config written as if --from-legacy was omitted.
  run jq -r '.integrations.routing.idea' "$PROJECT/.claude/ccanvil.local.json"
  [ "$output" = "local" ]
}

# =========================================================================
# AC-7: idempotency
# =========================================================================

@test "AC-7: second run on already-upgraded node exits 0 with 'Already upgraded' and no new commit" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider local "$PROJECT"
  [ "$status" -eq 0 ]

  baseline=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')

  run bash "$DOCS_CHECK" idea-upgrade --provider local "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" = *"Already upgraded"* ]]

  after=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')
  [ "$baseline" -eq "$after" ]
}

@test "AC-7: second run with linear provider is also a no-op when already-upgraded" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]

  baseline=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')

  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" = *"Already upgraded"* ]]

  after=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')
  [ "$baseline" -eq "$after" ]
}

@test "AC-7: changing provider from local to linear on second run is NOT idempotent (re-upgrade allowed)" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider local "$PROJECT"
  [ "$status" -eq 0 ]

  baseline=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')

  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Already upgraded"* ]]

  after=$(git -C "$PROJECT" log --oneline | wc -l | tr -d ' ')
  [ "$after" -eq $((baseline + 1)) ]

  # Routing is now linear.
  run jq -r '.integrations.routing.idea' "$PROJECT/.claude/ccanvil.local.json"
  [ "$output" = "linear" ]
}

# =========================================================================
# AC-13, AC-16: archive header on Linear upgrade
# =========================================================================

@test "AC-13: --provider linear prepends archive header to .ccanvil/ideas.log" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]

  [ -f "$PROJECT/.ccanvil/ideas.log" ]
  head1=$(head -1 "$PROJECT/.ccanvil/ideas.log")
  [[ "$head1" =~ ^\#\ ARCHIVE:\ read-only\ after\ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "AC-13: existing log entries are preserved below the prepended header" {
  _init_git
  # Simulate a project with pre-existing local log entries.
  mkdir -p "$PROJECT/.ccanvil"
  echo '{"uid":"a1b2","created":1700000000,"status":"new","title":"old","body":"old"}' > "$PROJECT/.ccanvil/ideas.log"

  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]

  head1=$(head -1 "$PROJECT/.ccanvil/ideas.log")
  [[ "$head1" =~ ^\#\ ARCHIVE: ]]
  # Original entry still present.
  grep -q '"uid":"a1b2"' "$PROJECT/.ccanvil/ideas.log"
}

@test "AC-16: archive header is not duplicated on idempotent re-run" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]

  # Re-run the upgrade — since config matches, this is the idempotent path.
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]

  archive_header_count=$(grep -c '^# ARCHIVE:' "$PROJECT/.ccanvil/ideas.log" || true)
  [ "$archive_header_count" -eq 1 ]
}

@test "AC-13: --provider local does NOT prepend the archive header" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider local "$PROJECT"
  [ "$status" -eq 0 ]

  # Log file may not exist yet, or if it exists it must not have the header.
  if [[ -f "$PROJECT/.ccanvil/ideas.log" ]]; then
    ! grep -q '^# ARCHIVE:' "$PROJECT/.ccanvil/ideas.log"
  fi
}

# =========================================================================
# AC-14: idea-add refuses direct writes on Linear-configured nodes
# =========================================================================

@test "AC-14: idea-add on Linear-configured node exits non-zero with routing error" {
  _init_git
  # Configure node as Linear-routed.
  run bash "$DOCS_CHECK" idea-upgrade --provider linear --team "Acme" --project "Alpha" "$PROJECT"
  [ "$status" -eq 0 ]

  run bash "$DOCS_CHECK" idea-add "attempted direct capture" "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" = *"Linear-configured"* ]]
  [[ "$output" = *"/idea"* ]]
}

@test "AC-14: idea-add on local-routed node still works (no regression)" {
  _init_git
  run bash "$DOCS_CHECK" idea-upgrade --provider local "$PROJECT"
  [ "$status" -eq 0 ]

  run bash "$DOCS_CHECK" idea-add "normal local capture" "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q "normal local capture" "$PROJECT/.ccanvil/ideas.log"
}

@test "AC-14: idea-add on unconfigured node works (default local)" {
  _init_git
  # No idea-upgrade run — no ccanvil.local.json at all.
  run bash "$DOCS_CHECK" idea-add "unconfigured capture" "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q "unconfigured capture" "$PROJECT/.ccanvil/ideas.log"
}
