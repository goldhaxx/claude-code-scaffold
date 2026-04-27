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

# =========================================================================
# AC-1: SessionStart hook bumps counter (first-run init)
# =========================================================================

@test "AC-1: hook initializes counter to 1 on fresh node" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil"
  CLAUDE_PROJECT_DIR="$fx" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -f "$fx/.ccanvil/state/session-counter" ]
  [ "$(cat "$fx/.ccanvil/state/session-counter")" = "1" ]
}

# =========================================================================
# AC-6: counter is monotonic across two SessionStart invocations
# =========================================================================

@test "AC-6: counter is monotonic across two SessionStart invocations" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil"
  CLAUDE_PROJECT_DIR="$fx" bash "$HOOK"
  [ "$(cat "$fx/.ccanvil/state/session-counter")" = "1" ]
  CLAUDE_PROJECT_DIR="$fx" bash "$HOOK"
  [ "$(cat "$fx/.ccanvil/state/session-counter")" = "2" ]
}

# =========================================================================
# AC-2: SessionStart hook stamps ISO boundary
# =========================================================================

@test "AC-2: hook writes session-boundary JSON with epoch, iso, tz" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil"
  CLAUDE_PROJECT_DIR="$fx" run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -f "$fx/.ccanvil/state/session-boundary" ]
  jq -e '.epoch | type == "number"' < "$fx/.ccanvil/state/session-boundary"
  jq -e '.iso | type == "string"' < "$fx/.ccanvil/state/session-boundary"
  jq -e '.tz | type == "string" and length > 0' < "$fx/.ccanvil/state/session-boundary"
  iso=$(jq -r '.iso' < "$fx/.ccanvil/state/session-boundary")
  [[ "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$ ]]
}

# =========================================================================
# AC-7: TZ env override respected
# =========================================================================

@test "AC-7: TZ=UTC produces iso ending in +00:00" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil"
  TZ=UTC CLAUDE_PROJECT_DIR="$fx" run bash "$HOOK"
  [ "$status" -eq 0 ]
  iso=$(jq -r '.iso' < "$fx/.ccanvil/state/session-boundary")
  [[ "$iso" == *"+00:00" ]]
  tz=$(jq -r '.tz' < "$fx/.ccanvil/state/session-boundary")
  [ "$tz" = "UTC" ]
}

@test "AC-7: TZ env always wins over /etc/localtime + timedatectl" {
  # Even on a host where /etc/localtime is a non-IANA copy (Docker), the TZ
  # env override should produce the requested zone in the boundary tz field.
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil"
  TZ="America/New_York" CLAUDE_PROJECT_DIR="$fx" run bash "$HOOK"
  [ "$status" -eq 0 ]
  tz=$(jq -r '.tz' < "$fx/.ccanvil/state/session-boundary")
  [ "$tz" = "America/New_York" ]
}

# =========================================================================
# AC-8: counter file corruption resets to 1 + warns
# =========================================================================

@test "AC-8: hook resets corrupted counter to 1 + warns" {
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  echo "garbage" > "$fx/.ccanvil/state/session-counter"
  CLAUDE_PROJECT_DIR="$fx" run --separate-stderr bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(cat "$fx/.ccanvil/state/session-counter")" = "1" ]
  [[ "$stderr" == *"non-integer"* ]]
}

# =========================================================================
# AC-9: hook non-blocking when state dir is unwritable
# =========================================================================

@test "AC-9: hook exits 0 even when state dir is unwritable" {
  if [[ "$EUID" -eq 0 ]]; then
    skip "running as root — chmod 555 is bypassed"
  fi
  set -e
  fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil/state"
  chmod 555 "$fx/.ccanvil/state"
  CLAUDE_PROJECT_DIR="$fx" run bash "$HOOK"
  # Restore so teardown can clean up.
  chmod 755 "$fx/.ccanvil/state"
  [ "$status" -eq 0 ]
}

# =========================================================================
# Hook registration — settings.json wires SessionStart
# =========================================================================

@test "settings.json registers SessionStart hook" {
  set -e
  jq -e '.hooks.SessionStart | type == "array" and length > 0' "$REPO_ROOT/.claude/settings.json"
  grep -qF 'session-boundary.sh' "$REPO_ROOT/.claude/settings.json"
}

# =========================================================================
# AC-4: stasis template carries Session + Boundary metadata
# =========================================================================

@test "AC-4: stasis template includes > Session: line" {
  grep -qE '^> Session:' "$REPO_ROOT/.ccanvil/templates/stasis.md"
}

@test "AC-4: stasis template includes > Boundary: line" {
  grep -qE '^> Boundary:' "$REPO_ROOT/.ccanvil/templates/stasis.md"
}

@test "AC-4: stasis skill calls docs-check.sh session-info" {
  grep -qF 'docs-check.sh session-info' "$REPO_ROOT/.claude/skills/stasis/SKILL.md"
}

# =========================================================================
# AC-5: recall skill surfaces session + boundary
# =========================================================================

@test "AC-5: recall skill calls docs-check.sh session-info" {
  grep -qF 'docs-check.sh session-info' "$REPO_ROOT/.claude/skills/recall/SKILL.md"
}

@test "AC-5: recall skill briefing prose mentions Session N" {
  # The briefing renders a one-liner like "Session N — boundary ISO" guarded
  # on counter > 0 to avoid zero-noise on fresh nodes.
  grep -qE 'Session N|Session \\?\\?N' "$REPO_ROOT/.claude/skills/recall/SKILL.md"
}
