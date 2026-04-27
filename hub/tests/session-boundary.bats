#!/usr/bin/env bats
# BTS-206 — drift-guards for the session-boundary SessionStart hook
# and the docs-check.sh session-info substrate primitive.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"
HOOK="$REPO_ROOT/.claude/hooks/session-boundary.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && ALLOW_DESTRUCTIVE=1 rm -rf "$TMPDIR_BATS"
}

# =========================================================================
# AC-3: session-info primitive — empty/fresh-node envelope
# =========================================================================

@test "AC-3: session-info on fresh node returns counter=0 and null fields" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil"
  run bash "$SCRIPT" session-info --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.counter == 0'
  echo "$output" | jq -e '.epoch == null'
  echo "$output" | jq -e '.iso == null'
  echo "$output" | jq -e '.tz == null'
}

@test "AC-3: session-info reads counter + boundary state files" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  echo "47" > "$fx/.ccanvil/state/session-counter"
  cat > "$fx/.ccanvil/state/session-boundary" <<'EOF'
{"epoch":1777254400,"iso":"2026-04-26T18:44:36-07:00","tz":"America/Los_Angeles"}
EOF
  run bash "$SCRIPT" session-info --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.counter == 47'
  echo "$output" | jq -e '.epoch == 1777254400'
  echo "$output" | jq -e '.iso == "2026-04-26T18:44:36-07:00"'
  echo "$output" | jq -e '.tz == "America/Los_Angeles"'
}

@test "session-info: corrupted counter file returns counter=0 + warns" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  echo "not-a-number" > "$fx/.ccanvil/state/session-counter"
  run --separate-stderr bash "$SCRIPT" session-info --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.counter == 0'
  [[ "$stderr" == *"non-integer"* ]]
}

@test "session-info: malformed boundary JSON returns null fields" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  echo "not json at all" > "$fx/.ccanvil/state/session-boundary"
  run bash "$SCRIPT" session-info --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.epoch == null'
  echo "$output" | jq -e '.iso == null'
  echo "$output" | jq -e '.tz == null'
}
