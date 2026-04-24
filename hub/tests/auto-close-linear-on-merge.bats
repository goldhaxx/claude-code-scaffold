#!/usr/bin/env bats
# Tests for auto-close Linear on PR merge — BTS-119.
# cmd_extract_work helper + cmd_land AUTO-CLOSE intent emission + /idea sync
# support for the ticket.transition op shape.

DOCS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.ccanvil" "$PROJECT/.claude" "$PROJECT/docs/specs"
}

teardown() {
  rm -rf "$PROJECT"
}

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

_spec_linear() {
  # $1 = id (e.g. BTS-119), $2 = feature_id slug
  local id="$1"
  local slug="$2"
  cat > "$PROJECT/docs/specs/$slug.md" <<MD
# Feature: Fixture

> Feature: $slug
> Work: linear:$id
> Created: 1777004190
> Status: Complete

## Summary
Fixture.
MD
}

_spec_local() {
  local uid="$1"
  local slug="$2"
  cat > "$PROJECT/docs/specs/$slug.md" <<MD
# Feature: Fixture

> Feature: $slug
> Work: local:$uid
> Created: 1777004190
> Status: Complete

## Summary
Fixture.
MD
}

_spec_no_work() {
  local slug="$1"
  cat > "$PROJECT/docs/specs/$slug.md" <<MD
# Feature: Fixture (legacy)

> Feature: $slug
> Created: 1777004190
> Status: Complete

## Summary
Fixture without Work: metadata.
MD
}

_spec_other_provider() {
  local id="$1"
  local slug="$2"
  cat > "$PROJECT/docs/specs/$slug.md" <<MD
# Feature: Fixture

> Feature: $slug
> Work: github:$id
> Created: 1777004190
> Status: Complete

## Summary
Fixture with non-linear, non-local provider.
MD
}

# ===========================================================================
# Step 1 — cmd_extract_work happy path (AC-2 foundation)
# ===========================================================================

@test "BTS-119 AC-2 (foundation): cmd_extract_work returns linear provider + id JSON" {
  # AC-2 requires the land flow invoke operations.sh resolve ticket.transition.
  # This test exercises the data-extraction precondition only — the resolver
  # call itself lives in land.md (skill prose) and is covered by the AC-1
  # dogfood smoke test against the BTS-119 branch on merge.
  _spec_linear "BTS-119" "bts-119-foo"
  run bash "$DOCS" extract-work "$PROJECT/docs/specs/bts-119-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear" and .id == "BTS-119"'
}

@test "BTS-119 AC-5: cmd_extract_work returns empty for spec without Work:" {
  _spec_no_work "legacy-spec"
  run bash "$DOCS" extract-work "$PROJECT/docs/specs/legacy-spec.md"
  [ "$status" -eq 0 ]
  # Empty stdout is the contract — callers treat it as "no work ref, skip".
  [ -z "$output" ]
}

@test "BTS-119 AC-6: cmd_extract_work returns local provider + uid for local:" {
  _spec_local "idea-29" "foo-local"
  run bash "$DOCS" extract-work "$PROJECT/docs/specs/foo-local.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local" and .id == "idea-29"'
}

@test "BTS-119 AC-7: cmd_extract_work returns any provider + id for future providers" {
  _spec_other_provider "42" "future-spec"
  run bash "$DOCS" extract-work "$PROJECT/docs/specs/future-spec.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "github" and .id == "42"'
}

@test "BTS-119 AC-5 (edge): malformed Work: without colon → empty stdout, exit 0" {
  cat > "$PROJECT/docs/specs/malformed.md" <<'MD'
# Feature: Bad

> Feature: malformed
> Work: just-no-colon-here
> Created: 1777004190
> Status: Complete

## Summary
Fixture.
MD
  run bash "$DOCS" extract-work "$PROJECT/docs/specs/malformed.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-119 AC-5 (edge): spec file missing → ERROR + exit 1" {
  run bash "$DOCS" extract-work "$PROJECT/docs/specs/does-not-exist.md"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "spec file not found" ]]
}

# ===========================================================================
# Phase 2 — cmd_auto_close_emit (extracted helper testable without git)
# ===========================================================================
# The cmd_land safety net block is hard to test end-to-end because it does
# `git checkout main`, `git fetch`, `git reset --hard`, etc. We extract the
# "map branch → spec → emit intent" logic into a pure helper that takes
# branch name + docs dir as args. cmd_land calls it after the safety net.
# That way the intent-emission rules (AC-5/6/7/9) are directly testable.

@test "BTS-119 AC-2/AC-9: auto-close-emit prints AUTO-CLOSE marker for linear Work" {
  _spec_linear "BTS-119" "bts-119-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-close-emit claude/feat/bts-119-foo"
  [ "$status" -eq 0 ]
  # Marker line is structured JSON with role=done pre-applied — caller just
  # reads the id and dispatches.
  [[ "$output" =~ "AUTO-CLOSE: " ]]
  echo "$output" | grep "^AUTO-CLOSE: " | sed 's/^AUTO-CLOSE: //' | \
    jq -e '.provider == "linear" and .id == "BTS-119" and .role == "done"'
}

@test "BTS-119 AC-5: auto-close-emit is silent for spec without Work: (legacy)" {
  _spec_no_work "legacy-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-close-emit claude/feat/legacy-foo"
  [ "$status" -eq 0 ]
  # Silent — no marker, no skip log. Matches validator's grandfather rule.
  [ -z "$output" ]
}

@test "BTS-119 AC-6: auto-close-emit skips with explicit log for local provider" {
  _spec_local "idea-29" "foo-local"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-close-emit claude/feat/foo-local"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "AUTO-CLOSE: " ]]
  [[ "$output" =~ "local provider" ]]
  [[ "$output" =~ "skipping" ]]
}

@test "BTS-119 AC-7: auto-close-emit skips unknown provider with named log" {
  _spec_other_provider "42" "future-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-close-emit claude/feat/future-foo"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "AUTO-CLOSE: " ]]
  [[ "$output" =~ "provider 'github'" ]]
  [[ "$output" =~ "no adapter" ]]
}

@test "BTS-119 AC-9: auto-close-emit skips non-claude branch with log" {
  _spec_linear "BTS-119" "bts-119-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-close-emit hotfix/urgent"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "AUTO-CLOSE: " ]]
  [[ "$output" =~ "no feature-id detected" ]]
}

@test "BTS-119 (edge): auto-close-emit is silent when spec file is missing" {
  # Non-spec-driven branch — no archive ever existed. Silent success.
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-close-emit claude/feat/never-had-a-spec"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ===========================================================================
# Phase 4 — /idea sync tolerates the ticket.transition op shape (AC-4)
# ===========================================================================
# cmd_idea_sync is shape-agnostic (enumerates + acks by ts), so the new
# op:"ticket.transition" entry type doesn't need script changes — but we
# assert the round-trip explicitly so a future refactor that adds op-filtering
# must account for it.

@test "BTS-119 AC-4: idea-sync lists ticket.transition entries without error" {
  cat > "$PROJECT/.ccanvil/ideas-pending.log" <<'JSONL'
{"op":"ticket.transition","args":{"id":"BTS-119","role":"done"},"ts":1777004190}
JSONL
  run bash "$DOCS" idea-sync "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    .pending == 1
    and (.entries | length == 1)
    and .entries[0].op == "ticket.transition"
    and .entries[0].args.id == "BTS-119"
    and .entries[0].args.role == "done"
  '
}

@test "BTS-119 AC-4: idea-sync --ack removes a ticket.transition entry" {
  cat > "$PROJECT/.ccanvil/ideas-pending.log" <<'JSONL'
{"op":"ticket.transition","args":{"id":"BTS-119","role":"done"},"ts":1777004190}
{"op":"add","args":{"title":"keep me"},"ts":1777004200}
JSONL
  run bash "$DOCS" idea-sync --ack 1777004190 "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ACKED: 1777004190" ]]
  # The other entry survives. Re-read pending log and assert status + shape.
  run bash "$DOCS" idea-sync "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pending == 1 and .entries[0].op == "add"'
}
