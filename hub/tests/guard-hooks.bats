#!/usr/bin/env bats
# Tests for guard hooks: guard-force-push.sh and guard-destructive.sh
#
# Each test pipes JSON to the hook and checks exit code + output.

FORCE_PUSH_HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/guard-force-push.sh"
DESTRUCTIVE_HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/guard-destructive.sh"

# =========================================================================
# guard-force-push.sh
# =========================================================================

@test "guard-force-push: blocks git push --force" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push --force"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "force push"
}

@test "guard-force-push: blocks git push -f" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push -f"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "guard-force-push: blocks git push --force-with-lease" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "guard-force-push: blocks git push origin main --force" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "guard-force-push: allows normal git push" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-force-push: allows git push -u origin branch" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push -u origin claude/feat/test"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-force-push: bypass with ALLOW_FORCE=1" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_FORCE=1 git push --force"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-force-push: shows bypass syntax in error" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push --force"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "ALLOW_FORCE=1"
}

@test "guard-force-push: allows non-push commands" {
  input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-force-push: handles empty command" {
  input='{"tool_name":"Bash","tool_input":{}}'
  run bash -c "echo '$input' | '$FORCE_PUSH_HOOK'"
  [ "$status" -eq 0 ]
}

# =========================================================================
# guard-destructive.sh
# =========================================================================

@test "guard-destructive: blocks git reset --hard" {
  input='{"tool_name":"Bash","tool_input":{"command":"git reset --hard origin/main"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "git reset --hard"
}

@test "guard-destructive: blocks git branch -D" {
  input='{"tool_name":"Bash","tool_input":{"command":"git branch -D old-branch"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "git branch -D"
}

@test "guard-destructive: blocks git push origin --delete" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push origin --delete claude/feat/old"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "guard-destructive: blocks git clean -f" {
  input='{"tool_name":"Bash","tool_input":{"command":"git clean -fd"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "git clean"
}

@test "guard-destructive: allows git reset (soft)" {
  input='{"tool_name":"Bash","tool_input":{"command":"git reset HEAD~1"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: allows git branch -d (lowercase)" {
  input='{"tool_name":"Bash","tool_input":{"command":"git branch -d merged-branch"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: allows normal git push" {
  input='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: bypass with ALLOW_DESTRUCTIVE=1" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_DESTRUCTIVE=1 git reset --hard origin/main"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: shows bypass syntax in error" {
  input='{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "ALLOW_DESTRUCTIVE=1"
}

@test "guard-destructive: names the blocked command in error" {
  input='{"tool_name":"Bash","tool_input":{"command":"git branch -D feature"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "git branch -D"
}

@test "guard-destructive: allows non-destructive commands" {
  input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: handles empty command" {
  input='{"tool_name":"Bash","tool_input":{}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}
