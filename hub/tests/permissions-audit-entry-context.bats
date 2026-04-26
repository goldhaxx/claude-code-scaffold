#!/usr/bin/env bats
# BTS-161: permissions-audit.sh entry-context substrate
#
# Each test creates an isolated fixture dir with settings + log files.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/permissions-audit.sh"

setup() {
  FIXTURE=$(mktemp -d)
  echo '{"entries":{}}' > "$FIXTURE/permissions-log.json"
}

teardown() {
  rm -rf "$FIXTURE"
}


# =========================================================================
# AC-1: JSON envelope shape — five top-level keys, permission echoed verbatim
# =========================================================================

@test "AC-1: entry-context emits JSON object with five top-level keys" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(ls:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(ls:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permission == "Bash(ls:*)"'
  echo "$output" | jq -e 'has("source_files")'
  echo "$output" | jq -e 'has("matched_pattern")'
  echo "$output" | jq -e 'has("matched_hooks")'
  echo "$output" | jq -e 'has("introduced_in")'
}

@test "AC-1: entry-context echoes permission with parens and asterisks intact" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(git status:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(git status:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permission == "Bash(git status:*)"'
}


# =========================================================================
# AC-2: source_files derivation
# =========================================================================

@test "AC-2: source_files for permission only in settings.json" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(ls:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(ls:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg p "$FIXTURE/settings.json" '.source_files == [$p]'
}

@test "AC-2: source_files for permission only in settings.local.json" {
  set -e
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{ "permissions": { "allow": ["Bash(ls:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(ls:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg p "$FIXTURE/settings.local.json" '.source_files == [$p]'
}

@test "AC-2: source_files for permission in both files (sorted)" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(ls:*)"] } }
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{ "permissions": { "allow": ["Bash(ls:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(ls:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg a "$FIXTURE/settings.json" --arg b "$FIXTURE/settings.local.json" \
    '.source_files == [$a, $b]'
}

@test "AC-2: source_files empty when permission absent from both files" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(other:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(missing:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.source_files == []'
}


# =========================================================================
# AC-3: matched_pattern via check_danger
# =========================================================================

@test "AC-3: matched_pattern populated for DANGER-classified Bash(chmod:*)" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(chmod:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(chmod:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matched_pattern != null'
  echo "$output" | jq -e '.matched_pattern | length > 0'
}

@test "AC-3: matched_pattern null for non-DANGER Bash(ls:*)" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(ls:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(ls:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matched_pattern == null'
}

@test "AC-3: matched_pattern null for non-Bash permission shape" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Read(//Users/foo)"] } }
EOF
  run bash "$SCRIPT" entry-context "Read(//Users/foo)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matched_pattern == null'
}


# =========================================================================
# AC-4 / AC-10: matched_hooks heuristic scan
# =========================================================================

@test "AC-4: matched_hooks for Bash(chmod:*) finds guard-destructive.sh" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(chmod:*)"] } }
EOF
  # The hooks dir lives at .claude/hooks/ in the repo; entry-context scans it
  # relative to the workspace, not the fixture. Verify guard-destructive.sh is
  # picked up by the leading-verb scan for chmod.
  cd "$BATS_TEST_DIRNAME/../.."
  run bash "$SCRIPT" entry-context "Bash(chmod:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matched_hooks | length > 0'
  echo "$output" | jq -e '[.matched_hooks[].path] | any(. | endswith("guard-destructive.sh"))'
}

@test "AC-4: matched_hooks entry has path and lines fields" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(chmod:*)"] } }
EOF
  cd "$BATS_TEST_DIRNAME/../.."
  run bash "$SCRIPT" entry-context "Bash(chmod:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matched_hooks[0] | has("path") and has("lines")'
  echo "$output" | jq -e '.matched_hooks[0].lines | length == 2'
  echo "$output" | jq -e '.matched_hooks[0].lines[0] | type == "number"'
  echo "$output" | jq -e '.matched_hooks[0].lines[1] | type == "number"'
}

@test "AC-4: matched_hooks empty for Bash(echo:*) — no leading-verb match" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(echo:*)"] } }
EOF
  cd "$BATS_TEST_DIRNAME/../.."
  run bash "$SCRIPT" entry-context "Bash(echo:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matched_hooks == []'
}

@test "AC-10: matched_hooks empty when .claude/hooks/ is missing" {
  set -e
  # Run from a workspace that has no .claude/hooks/ dir — fixture itself.
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(chmod:*)"] } }
EOF
  cd "$FIXTURE"
  run bash "$SCRIPT" entry-context "Bash(chmod:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.matched_hooks == []'
}


# =========================================================================
# AC-6: positional arg required → exit 2 with specific error on stderr
# =========================================================================

@test "AC-6: entry-context with no positional arg exits 2 and explains why" {
  run bash "$SCRIPT" entry-context --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  # Stderr (or output) must mention the missing permission arg specifically —
  # generic 'Usage:' fallback is not enough; the error must be specific to
  # entry-context's missing-arg branch.
  combined="${stderr}${output}"
  [[ "$combined" == *"entry-context requires a permission"* ]]
}
