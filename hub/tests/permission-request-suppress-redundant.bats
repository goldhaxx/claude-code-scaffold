#!/usr/bin/env bats
# BTS-150: PermissionRequest hook — suppress redundant exact-form
# persistence to settings.local.json when a broader allow pattern in
# settings.json already covers the requested Bash command.
#
# Each test creates an isolated project root containing
# .claude/settings.json with a fixture allow list, points
# CLAUDE_PROJECT_DIR at it, pipes a synthetic PermissionRequest payload
# through the hook, and asserts on the emitted output.

bats_require_minimum_version 1.5.0

HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/permission-request-suppress-redundant.sh"

setup() {
  FIXTURE=$(mktemp -d)
  mkdir -p "$FIXTURE/.claude"
}

teardown() {
  rm -rf "$FIXTURE"
}

# Helper: build the hook input JSON given a command string.
_make_input() {
  local cmd="$1"
  jq -n --arg cmd "$cmd" '{
    session_id: "test-session",
    cwd: "/tmp",
    permission_mode: "default",
    hook_event_name: "PermissionRequest",
    tool_name: "Bash",
    tool_input: {command: $cmd}
  }'
}

# Helper: write a settings.json with a given allow array.
_write_settings() {
  local allow_json="$1"
  jq -n --argjson allow "$allow_json" '{permissions: {allow: $allow}}' > "$FIXTURE/.claude/settings.json"
}

# =========================================================================
# Token-prefix matching — Bash(<binary>:*) covers Bash(<binary> <args>)
# =========================================================================

@test "token-prefix: Bash(bash:*) covers 'bash some args' → session-scope intercept" {
  set -e
  _write_settings '["Bash(bash:*)"]'
  output=$(_make_input "bash .ccanvil/scripts/foo.sh check" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PermissionRequest"'
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
  echo "$output" | jq -e '.hookSpecificOutput.decision.updatedPermissions[0].destination == "session"'
  echo "$output" | jq -e '.hookSpecificOutput.decision.updatedPermissions[0].rules[0].toolName == "Bash"'
  echo "$output" | jq -e '.hookSpecificOutput.decision.updatedPermissions[0].rules[0].ruleContent == "bash .ccanvil/scripts/foo.sh check"'
}

@test "token-prefix: Bash(jq:*) covers 'jq -r .foo file.json'" {
  set -e
  _write_settings '["Bash(jq:*)"]'
  output=$(_make_input "jq -r .foo file.json" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "token-prefix: Bash(bash:*) does NOT cover 'basher foo' (word-boundary)" {
  _write_settings '["Bash(bash:*)"]'
  output=$(_make_input "basher foo" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

@test "token-prefix: Bash(bash:*) does NOT cover 'bash-language-server foo' (hyphen word-boundary)" {
  _write_settings '["Bash(bash:*)"]'
  output=$(_make_input "bash-language-server foo" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

@test "token-prefix: bare-token 'bash' (no args) matches Bash(bash:*)" {
  set -e
  _write_settings '["Bash(bash:*)"]'
  output=$(_make_input "bash" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "token-prefix: multi-token prefix Bash(bash -n:*) covers 'bash -n script.sh'" {
  set -e
  _write_settings '["Bash(bash -n:*)"]'
  output=$(_make_input "bash -n script.sh" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "token-prefix: multi-token prefix Bash(bash -n:*) does NOT cover bare 'bash'" {
  _write_settings '["Bash(bash -n:*)"]'
  output=$(_make_input "bash script.sh" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

@test "token-prefix: env-prefix Bash(ALLOW_MAIN=1 git:*) covers 'ALLOW_MAIN=1 git push'" {
  set -e
  _write_settings '["Bash(ALLOW_MAIN=1 git:*)"]'
  output=$(_make_input "ALLOW_MAIN=1 git push" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

# =========================================================================
# Path-prefix matching — Bash(<dir>/:*) covers Bash(<dir>/<anything>)
# =========================================================================

@test "path-prefix: Bash(.ccanvil/scripts/:*) covers '.ccanvil/scripts/foo.sh check'" {
  set -e
  _write_settings '["Bash(.ccanvil/scripts/:*)"]'
  output=$(_make_input ".ccanvil/scripts/foo.sh check" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "path-prefix: Bash(./.ccanvil/scripts/:*) covers './.ccanvil/scripts/foo.sh'" {
  set -e
  _write_settings '["Bash(./.ccanvil/scripts/:*)"]'
  output=$(_make_input "./.ccanvil/scripts/foo.sh" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

# =========================================================================
# Exact-form matching — Bash(<exact>) requires command == exact
# =========================================================================

@test "exact: Bash(done) matches command 'done' exactly" {
  set -e
  _write_settings '["Bash(done)"]'
  output=$(_make_input "done" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "exact: Bash(done) does NOT match 'done && something'" {
  _write_settings '["Bash(done)"]'
  output=$(_make_input "done && something" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

# =========================================================================
# No-match / passthrough — uncovered command returns empty stdout
# =========================================================================

@test "no-match: command not covered by any allow pattern → passthrough (empty stdout)" {
  _write_settings '["Bash(jq:*)", "Bash(grep:*)"]'
  output=$(_make_input "rm -rf /" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

@test "no-match: empty allow list → passthrough" {
  _write_settings '[]'
  output=$(_make_input "bash foo" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

# =========================================================================
# Tool-scope — non-Bash tools are passthrough
# =========================================================================

@test "non-Bash tool (Edit) → passthrough" {
  _write_settings '["Bash(bash:*)"]'
  input=$(jq -n '{tool_name: "Edit", tool_input: {file_path: "/tmp/x"}, hook_event_name: "PermissionRequest"}')
  output=$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

@test "Bash with empty command → passthrough" {
  _write_settings '["Bash(bash:*)"]'
  input=$(jq -n '{tool_name: "Bash", tool_input: {command: ""}, hook_event_name: "PermissionRequest"}')
  output=$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

# =========================================================================
# Edge cases — missing settings.json, malformed allow list
# =========================================================================

@test "missing settings.json → passthrough (no error)" {
  rm -f "$FIXTURE/.claude/settings.json"
  output=$(_make_input "bash foo" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

@test "settings.json with no permissions key → passthrough" {
  echo '{}' > "$FIXTURE/.claude/settings.json"
  output=$(_make_input "bash foo" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -z "$output" ]]
}

@test "non-Bash entries in allow list are ignored (e.g., WebSearch, Read())" {
  set -e
  _write_settings '["WebSearch", "Read(.//*)", "Bash(jq:*)"]'
  output=$(_make_input "jq -r ." | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  [[ -n "$output" ]]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

# =========================================================================
# First-match-wins — the loop breaks on the first matching pattern
# =========================================================================

@test "first-match-wins: emitted ruleContent is the original command (not the matched pattern)" {
  set -e
  _write_settings '["Bash(jq:*)", "Bash(bash:*)"]'
  output=$(_make_input "bash foo bar" | CLAUDE_PROJECT_DIR="$FIXTURE" bash "$HOOK")
  echo "$output" | jq -e '.hookSpecificOutput.decision.updatedPermissions[0].rules[0].ruleContent == "bash foo bar"'
}
