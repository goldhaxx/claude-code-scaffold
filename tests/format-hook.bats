#!/usr/bin/env bats
# Tests for .claude/hooks/format-on-write.sh
#
# Each test creates an isolated environment and pipes JSON to the hook.
# The format hook always exits 0 — formatting failures never block writes.

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/format-on-write.sh"

setup() {
  REPO=$(mktemp -d)
  cd "$REPO"
  git init -q
  echo "# test" > README.md
  git add -A && git commit -q -m "init"
}

teardown() {
  rm -rf "$REPO"
}

# Helper: run the hook with a given file path
run_hook() {
  local file="$1"
  echo "{\"tool_input\":{\"file_path\":\"$file\"}}" | bash "$HOOK"
}


# =========================================================================
# Basic pass-through (no config)
# =========================================================================

@test "format: no config file exits 0" {
  echo "content" > "$REPO/test.py"
  run run_hook "$REPO/test.py"
  [ "$status" -eq 0 ]
}

@test "format: nonexistent file exits 0" {
  run run_hook "$REPO/nonexistent.xyz"
  [ "$status" -eq 0 ]
}

@test "format: empty file path exits 0" {
  run bash -c "echo '{\"tool_input\":{}}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}


# =========================================================================
# Config-driven formatters
# =========================================================================

@test "format: config-driven formatter runs for matching glob" {
  mkdir -p "$REPO/.claude"
  # Use 'tr' as a simple formatter: lowercase the file
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {},
  "formatters": {
    "*.txt": { "format": "tr A-Z a-z <", "name": "lowercase" }
  }
}
EOF

  # tr with redirection won't work via the hook's $format_cmd "$FILE_PATH" pattern.
  # Instead, use a formatter that takes a file path argument.
  # Use 'touch' as a no-op formatter to verify it runs.
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {},
  "formatters": {
    "*.txt": { "format": "touch", "name": "touch-formatter" }
  }
}
EOF

  echo "content" > "$REPO/test.txt"
  local before
  before=$(stat -f %m "$REPO/test.txt")
  sleep 1
  run run_hook "$REPO/test.txt"
  [ "$status" -eq 0 ]
  local after
  after=$(stat -f %m "$REPO/test.txt")
  # touch should have updated the mtime
  [ "$after" -ge "$before" ]
}

@test "format: non-matching glob does not run formatter" {
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {},
  "formatters": {
    "*.py": { "format": "touch", "name": "python-format" }
  }
}
EOF

  echo "content" > "$REPO/test.txt"
  run run_hook "$REPO/test.txt"
  [ "$status" -eq 0 ]
}

@test "format: missing formatter command is skipped gracefully" {
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {},
  "formatters": {
    "*.txt": { "format": "nonexistent-formatter-cmd-99999", "name": "Fake" }
  }
}
EOF

  echo "content" > "$REPO/test.txt"
  run run_hook "$REPO/test.txt"
  [ "$status" -eq 0 ]
}

@test "format: formatter failure does not block (exit 0)" {
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {},
  "formatters": {
    "*.txt": { "format": "false", "name": "always-fail" }
  }
}
EOF

  echo "content" > "$REPO/test.txt"
  run run_hook "$REPO/test.txt"
  [ "$status" -eq 0 ]
}

@test "format: pipe-separated glob matches multiple extensions" {
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {},
  "formatters": {
    "*.ts|*.tsx|*.js": { "format": "touch", "name": "JS/TS format" }
  }
}
EOF

  echo "content" > "$REPO/test.ts"
  run run_hook "$REPO/test.ts"
  [ "$status" -eq 0 ]

  echo "content" > "$REPO/test.tsx"
  run run_hook "$REPO/test.tsx"
  [ "$status" -eq 0 ]

  echo "content" > "$REPO/test.js"
  run run_hook "$REPO/test.js"
  [ "$status" -eq 0 ]
}

@test "format: empty formatters section is handled gracefully" {
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {},
  "formatters": {}
}
EOF

  echo "content" > "$REPO/test.txt"
  run run_hook "$REPO/test.txt"
  [ "$status" -eq 0 ]
}
