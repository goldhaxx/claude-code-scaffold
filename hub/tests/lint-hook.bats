#!/usr/bin/env bats
# Tests for .claude/hooks/lint-on-write.sh
#
# Each test creates an isolated environment and pipes JSON to the hook.

HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/lint-on-write.sh"

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
# Built-in: Bash syntax validation
# =========================================================================

@test "lint: valid bash script passes" {
  cat > "$REPO/good.sh" <<'EOF'
#!/usr/bin/env bash
echo "hello"
EOF
  run run_hook "$REPO/good.sh"
  [ "$status" -eq 0 ]
}

@test "lint: broken bash script blocks with exit 2" {
  cat > "$REPO/bad.sh" <<'EOF'
#!/usr/bin/env bash
if [[ true; then echo bad
EOF
  run run_hook "$REPO/bad.sh"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "Bash syntax error"
}


# =========================================================================
# Built-in: JSON syntax validation
# =========================================================================

@test "lint: valid JSON passes" {
  echo '{"key": "value"}' > "$REPO/good.json"
  run run_hook "$REPO/good.json"
  [ "$status" -eq 0 ]
}

@test "lint: broken JSON blocks with exit 2" {
  echo '{bad json' > "$REPO/bad.json"
  run run_hook "$REPO/bad.json"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "Invalid JSON"
}


# =========================================================================
# Built-in: YAML syntax validation
# =========================================================================

@test "lint: valid YAML passes" {
  echo "key: value" > "$REPO/good.yaml"
  run run_hook "$REPO/good.yaml"
  [ "$status" -eq 0 ]
}

@test "lint: .yml extension also validated" {
  echo "key: value" > "$REPO/good.yml"
  run run_hook "$REPO/good.yml"
  [ "$status" -eq 0 ]
}


# =========================================================================
# Non-matched files pass through
# =========================================================================

@test "lint: markdown files pass through without checking" {
  echo "# Just markdown" > "$REPO/doc.md"
  run run_hook "$REPO/doc.md"
  [ "$status" -eq 0 ]
}

@test "lint: nonexistent file passes (exit 0)" {
  run run_hook "$REPO/nonexistent.xyz"
  [ "$status" -eq 0 ]
}

@test "lint: empty file path passes (exit 0)" {
  run bash -c "echo '{\"tool_input\":{}}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}


# =========================================================================
# Config-driven linters
# =========================================================================

@test "lint: config-driven linter runs for matching glob" {
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {
    "*.txt": { "check": "test -s", "name": "Non-empty check" }
  },
  "formatters": {}
}
EOF

  # Non-empty file should pass
  echo "content" > "$REPO/test.txt"
  run run_hook "$REPO/test.txt"
  [ "$status" -eq 0 ]

  # Empty file should fail (test -s returns 1 for empty)
  > "$REPO/empty.txt"
  run run_hook "$REPO/empty.txt"
  [ "$status" -eq 2 ]
}

@test "lint: config-driven linter skips when command not found" {
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/lint.json" <<'EOF'
{
  "linters": {
    "*.xyz": { "check": "nonexistent-linter-command-12345", "name": "Fake linter" }
  },
  "formatters": {}
}
EOF

  echo "content" > "$REPO/test.xyz"
  run run_hook "$REPO/test.xyz"
  [ "$status" -eq 0 ]  # Should pass — linter command not found, gracefully skipped
}

@test "lint: no config file is handled gracefully" {
  # No .claude/lint.json exists
  echo "content" > "$REPO/test.py"
  run run_hook "$REPO/test.py"
  [ "$status" -eq 0 ]
}
