#!/usr/bin/env bats
# Tests for ccanvil-sync.sh relocate <old-path>.
# Spec: docs/specs/relocate-subcommand.md (BTS-74, Feature 3 of 3)
#
# Tests override $HOME to an isolated tmpdir so the production
# ~/.claude/projects/ path resolves into the test fixture.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  FAKE_HOME=$(mktemp -d)
  export HOME="$FAKE_HOME"

  NEW_PATH=$(mktemp -d)
  OLD_PATH="/Users/zach/projects/foo"

  # Compute encoded dir names
  OLD_ENCODED="-Users-zach-projects-foo"
  # NEW_ENCODED must match what the command computes for NEW_PATH ($(pwd))
  NEW_ENCODED=$(echo "$NEW_PATH" | sed 's|/|-|g')

  PROJECTS_DIR="$FAKE_HOME/.claude/projects"
  OLD_DIR="$PROJECTS_DIR/$OLD_ENCODED"
  NEW_DIR="$PROJECTS_DIR/$NEW_ENCODED"
  mkdir -p "$OLD_DIR"

  # Seed a .jsonl session file: 2 entries, only one has matching cwd
  cat > "$OLD_DIR/session-1.jsonl" <<JSONL
{"type":"user","cwd":"$OLD_PATH","message":"hello"}
{"type":"user","cwd":"/other/path","message":"contains $OLD_PATH as incidental string"}
JSONL

  # A second .jsonl with no matches at all
  cat > "$OLD_DIR/session-2.jsonl" <<JSONL
{"type":"user","cwd":"/somewhere/else","message":"no match here"}
JSONL
}

teardown() {
  rm -rf "$FAKE_HOME" "$NEW_PATH"
}

# Helper: run relocate from $NEW_PATH
run_relocate() {
  (cd "$NEW_PATH" && bash "$SCRIPT" relocate "$@")
}

# =========================================================================
# AC-1: dir rename + cwd rewrite happens on normal invocation
# =========================================================================
@test "AC-1: relocate renames history dir and rewrites cwd" {
  run_relocate "$OLD_PATH"

  # Old dir is gone, new dir exists
  [ ! -d "$OLD_DIR" ]
  [ -d "$NEW_DIR" ]

  # cwd rewritten in session-1
  local line1
  line1=$(sed -n '1p' "$NEW_DIR/session-1.jsonl")
  [[ "$line1" == *"\"cwd\":\"$NEW_PATH\""* ]]
  [[ "$line1" != *"\"cwd\":\"$OLD_PATH\""* ]]
}

# =========================================================================
# AC-2: path encoding is correct
# =========================================================================
@test "AC-2: encoded dir name uses dash-for-slash transformation" {
  run_relocate "$OLD_PATH"
  [ -d "$PROJECTS_DIR/$NEW_ENCODED" ]
  # Regression spot-check on well-known shape
  [[ "$NEW_ENCODED" == -* ]]
  [[ "$NEW_ENCODED" != *"/"* ]]
}

# =========================================================================
# AC-3: non-matching content is NOT rewritten (incidental substring preserved)
# =========================================================================
@test "AC-3: incidental substring in message content is not rewritten" {
  run_relocate "$OLD_PATH"

  # session-1 line 2: has OLD_PATH in message but NOT in cwd field
  local line2
  line2=$(sed -n '2p' "$NEW_DIR/session-1.jsonl")
  [[ "$line2" == *"\"cwd\":\"/other/path\""* ]]
  [[ "$line2" == *"$OLD_PATH"* ]]  # the message still contains old path (incidentally)

  # session-2 has no matching cwd — content must be untouched
  local session2_line
  session2_line=$(sed -n '1p' "$NEW_DIR/session-2.jsonl")
  [ "$session2_line" = '{"type":"user","cwd":"/somewhere/else","message":"no match here"}' ]
  # And no OLD_PATH string anywhere in the file
  ! grep -q "$OLD_PATH" "$NEW_DIR/session-2.jsonl"
}

# =========================================================================
# AC-4: idempotency — second run is a no-op exit 0
# =========================================================================
@test "AC-4: re-running relocate after success is a no-op exit 0" {
  run_relocate "$OLD_PATH"

  # Now old dir is gone. Re-run.
  run bash -c "cd '$NEW_PATH' && bash '$SCRIPT' relocate '$OLD_PATH'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already relocated"* ]] || [[ "$output" == *"No history dir"* ]]
}

# =========================================================================
# AC-5: collision safety — both dirs exist → abort with no changes
# =========================================================================
@test "AC-5: collision (both old and new dirs exist) aborts non-zero" {
  mkdir -p "$NEW_DIR"
  echo "existing" > "$NEW_DIR/marker.txt"

  run bash -c "cd '$NEW_PATH' && bash '$SCRIPT' relocate '$OLD_PATH'"
  [ "$status" -ne 0 ]

  # No changes: both dirs still exist
  [ -d "$OLD_DIR" ]
  [ -d "$NEW_DIR" ]
  [ -f "$NEW_DIR/marker.txt" ]

  # Original cwd field still unchanged
  local line1
  line1=$(sed -n '1p' "$OLD_DIR/session-1.jsonl")
  [[ "$line1" == *"\"cwd\":\"$OLD_PATH\""* ]]
}

# =========================================================================
# AC-6: non-absolute old path → usage error
# =========================================================================
@test "AC-6: non-absolute path exits non-zero" {
  run bash -c "cd '$NEW_PATH' && bash '$SCRIPT' relocate 'relative/path'"
  [ "$status" -ne 0 ]

  # Old dir untouched
  [ -d "$OLD_DIR" ]
}

# =========================================================================
# AC-7: cwd rewrite uses JSON-field anchor, not blind substring
# =========================================================================
@test "AC-7: only JSON cwd field is rewritten, not message strings" {
  # Add a line where the old path appears outside the cwd field
  cat >> "$OLD_DIR/session-1.jsonl" <<JSONL
{"type":"user","cwd":"/other/path","message":"user said $OLD_PATH"}
JSONL

  run_relocate "$OLD_PATH"

  # Line 3's message must still contain OLD_PATH literally
  local line3
  line3=$(sed -n '3p' "$NEW_DIR/session-1.jsonl")
  [[ "$line3" == *"user said $OLD_PATH"* ]]
  [[ "$line3" == *"\"cwd\":\"/other/path\""* ]]
}
