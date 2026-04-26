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

@test "AC-4: matched_hooks entries are per-occurrence (lines[0] == lines[1])" {
  # Review CONCERN 1 regression: each entry covers a single gate-context line,
  # not a hull spanning unrelated code in between.
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(chmod:*)"] } }
EOF
  cd "$BATS_TEST_DIRNAME/../.."
  run bash "$SCRIPT" entry-context "Bash(chmod:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.matched_hooks[]; .lines[0] == .lines[1])'
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
# AC-5: introduced_in via git log -S
# =========================================================================

@test "AC-5: introduced_in null when permission not in any settings file" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(other:*)"] } }
EOF
  run bash "$SCRIPT" entry-context "Bash(notpresent:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.introduced_in == null'
}

@test "AC-5: introduced_in returns commit + subject for tracked permission" {
  set -e
  # Use the actual repo's git history. Pick a permission known to exist in
  # .claude/settings.json so git log -S finds the introducing commit.
  cd "$BATS_TEST_DIRNAME/../.."
  # Pick the first Bash() permission from settings.json deterministically.
  local perm
  perm=$(jq -r '.permissions.allow[] | select(startswith("Bash("))' .claude/settings.json | head -1)
  [ -n "$perm" ]
  run bash "$SCRIPT" entry-context "$perm" --settings-dir .claude
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.introduced_in != null'
  echo "$output" | jq -e '.introduced_in | has("commit") and has("subject")'
  echo "$output" | jq -e '.introduced_in.commit | length > 0'
  echo "$output" | jq -e '.introduced_in.subject | length > 0'
}


# =========================================================================
# AC-7: absent permission graceful path
# =========================================================================

@test "AC-7: absent permission returns full envelope, exit 0" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(other:*)"] } }
EOF
  cd "$BATS_TEST_DIRNAME/../.."
  run bash "$SCRIPT" entry-context "Bash(neverhappens:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permission == "Bash(neverhappens:*)"'
  echo "$output" | jq -e '.source_files == []'
  echo "$output" | jq -e '.introduced_in == null'
  # matched_hooks may still scan the real hooks dir for the leading verb
  # (independent of settings presence) — assertion is just that the field
  # exists and is an array.
  echo "$output" | jq -e '.matched_hooks | type == "array"'
}


# =========================================================================
# AC-8: round-trip drift-guard against cmd_check
# =========================================================================

@test "AC-8: matched_pattern matches cmd_check output for same DANGER entry" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(chmod:*)"] } }
EOF
  # cmd_check classifies Bash(chmod:*) → DANGER with a matched_pattern.
  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --json
  [ "$status" -ne 0 ]   # 2 (DANGER) or 1 (UNREVIEWED) — never 0 here
  local check_pattern
  check_pattern=$(echo "$output" | jq -r '.entries[] | select(.permission == "Bash(chmod:*)") | .matched_pattern')
  [ -n "$check_pattern" ]
  [ "$check_pattern" != "null" ]

  run bash "$SCRIPT" entry-context "Bash(chmod:*)" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  local ec_pattern
  ec_pattern=$(echo "$output" | jq -r '.matched_pattern')
  [ "$ec_pattern" = "$check_pattern" ]
}


# =========================================================================
# AC-9: /permissions-review skill prose drift-guard
# =========================================================================

@test "AC-9: permissions-review skill references entry-context substrate" {
  local skill="$BATS_TEST_DIRNAME/../../.claude/commands/permissions-review.md"
  [ -f "$skill" ]
  grep -q 'entry-context' "$skill"
  grep -q 'matched_hooks' "$skill"
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
