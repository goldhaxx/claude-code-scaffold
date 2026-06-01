#!/usr/bin/env bats

# BTS-497 telemetry hooks.
source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"
setup_file()    { telemetry_setup_file; }
teardown_file() { telemetry_teardown_file; }
setup()         { telemetry_setup; }
teardown()      { telemetry_teardown; }
# Tests for guard hooks: guard-force-push.sh, guard-destructive.sh
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

# =========================================================================
# guard-destructive.sh — chmod-destructive patterns (BTS-142)
# =========================================================================

@test "guard-destructive: blocks chmod 777" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod 777 /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "chmod"
  echo "$output" | grep -q "ALLOW_DESTRUCTIVE=1"
}

@test "guard-destructive: blocks chmod -R 777" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod -R 777 /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "guard-destructive: blocks chmod 666" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod 666 /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "guard-destructive: blocks chmod -R 666" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod -R 666 /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "guard-destructive: blocks chmod 000" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod 000 /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "guard-destructive: blocks chmod -R 000" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod -R 000 /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "guard-destructive: allows chmod +x" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod +x scripts/foo.sh"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: allows chmod 644" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod 644 file.txt"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: allows chmod 755" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod 755 scripts/foo.sh"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: allows chmod -R 755" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod -R 755 scripts/"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "guard-destructive: chmod 777 bypasses with ALLOW_DESTRUCTIVE=1" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_DESTRUCTIVE=1 chmod 777 /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

# =========================================================================
# guard-destructive.sh — rm recursive+force patterns (BTS-156)
# =========================================================================

@test "BTS-156 AC-1: blocks rm -rf" {
  set -e   # BTS-127: halt on any assertion failure
  input='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "ALLOW_DESTRUCTIVE=1"
}

@test "BTS-156 AC-2: blocks rm -fr" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -fr /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-2: blocks rm -rfv" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -rfv /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-2: blocks rm -fR" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -fR /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-2: blocks rm -Rfv" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -Rfv /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-3: blocks rm --recursive --force" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm --recursive --force /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-3: blocks rm --force --recursive (reverse order)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm --force --recursive /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 → BTS-202: split rm -r -f no longer caught (trade-off)" {
  # BTS-202: rm-rf detection scoped to combined cluster (-rf, -fr, etc.)
  # OR dual long-form (--recursive --force). Split short-form is the
  # accepted trade-off — eliminates the jq -r + rm -f false-positive
  # class. Operator can ALLOW_DESTRUCTIVE=1 for deliberate split form.
  input='{"tool_name":"Bash","tool_input":{"command":"rm -r -f /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 → BTS-202: rm -r --force no longer caught (mixed trade-off)" {
  # BTS-202 trade-off: mixed short+long not caught. Same rationale.
  input='{"tool_name":"Bash","tool_input":{"command":"rm -r --force /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 → BTS-202: rm --recursive -f no longer caught (mixed trade-off)" {
  # BTS-202 trade-off: mixed long+short not caught. Same rationale.
  input='{"tool_name":"Bash","tool_input":{"command":"rm --recursive -f /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156: blocks sudo rm -rf" {
  # sudo prefix is a space-separated word boundary; rm is still anchored.
  input='{"tool_name":"Bash","tool_input":{"command":"sudo rm -rf /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-4: rm -rf bypasses with ALLOW_DESTRUCTIVE=1" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_DESTRUCTIVE=1 rm -rf /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-5: allows rm -r (no -f)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -r dir/"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-5: allows rm -R (no -f)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -R dir/"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-6: allows rm -f (no recursive)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -f file.txt"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-6: allows rm --force (no recursive)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm --force file.txt"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-7: allows plain rm (no flags)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm file1 file2"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-8: allows rm -i -f (interactive+force, no recursive)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -i -f file.txt"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-8: allows rm -v -r (verbose+recursive, no force)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -v -r dir/"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-9: allows form -rf (rm-substring in another verb)" {
  # Not a real command, but tests that the rm regex anchors as a word.
  input='{"tool_name":"Bash","tool_input":{"command":"form -rf /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-9: allows arm -rf (rm-substring at end of word)" {
  input='{"tool_name":"Bash","tool_input":{"command":"arm -rf /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-156 AC-10: blocks rm -rf with relative path" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -rf ./foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-10: blocks rm -rf with workspace-relative path" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -rf ~/projects/x"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156: catches rm -rf reached via xargs (literal string in command)" {
  # The hook is a literal-string check, not a parser. Pipelines like
  # `find . | xargs rm -rf` are caught because `rm -rf` appears verbatim.
  # The real blind spot is rm composed at runtime where the literal string
  # never contains `rm -rf` — e.g. `bash -c "$(printf 'rm %s' '-rf')"`.
  # Out of scope per spec; documented in hook comment.
  input='{"tool_name":"Bash","tool_input":{"command":"find . -type d | xargs rm -rf"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

# =========================================================================
# guard-destructive.sh — find traverse-and-mutate patterns (BTS-155)
# =========================================================================

@test "BTS-155 AC-1: blocks find . -delete" {
  set -e   # BTS-127
  input='{"tool_name":"Bash","tool_input":{"command":"find . -delete"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "ALLOW_DESTRUCTIVE=1"
}

@test "BTS-155 AC-2: blocks find . -exec rm {} +" {
  input='{"tool_name":"Bash","tool_input":{"command":"find . -exec rm {} +"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-155 AC-3: blocks find . -exec rm {} \\;" {
  input='{"tool_name":"Bash","tool_input":{"command":"find . -exec rm {} \\;"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-155 AC-4: blocks find . -execdir chmod" {
  input='{"tool_name":"Bash","tool_input":{"command":"find . -execdir chmod 644 {} +"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-155 AC-5: blocks find . -okdir rm" {
  input='{"tool_name":"Bash","tool_input":{"command":"find . -okdir rm {} \\;"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-155 AC-6: bypass via ALLOW_DESTRUCTIVE=1" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_DESTRUCTIVE=1 find . -delete"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-155 AC-7a: allows find . -name (read-only)" {
  input='{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.log\""}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-155 AC-7b: allows find . -type f (read-only)" {
  input='{"tool_name":"Bash","tool_input":{"command":"find . -type f"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-155 AC-7c: allows find . -print (read-only)" {
  input='{"tool_name":"Bash","tool_input":{"command":"find . -print"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-155 AC-8: allows find with -name '-delete' as pattern (quoted)" {
  # The single-quoted '-delete' is a name pattern, not the action.
  # Bats' inline-JSON-via-echo pipe re-parses single quotes during
  # bash -c, stripping them — so we feed the input via a tmpfile to
  # preserve the literal quotes the way Claude Code passes tool_input.
  tmp=$(mktemp -t bts155-ac8)
  cat > "$tmp" <<'JSON'
{"tool_name":"Bash","tool_input":{"command":"find . -name '-delete' -print"}}
JSON
  run bash -c "cat '$tmp' | '$DESTRUCTIVE_HOOK'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}

@test "BTS-155 AC-9: allows xfind . -delete (find substring in another verb)" {
  input='{"tool_name":"Bash","tool_input":{"command":"xfind . -delete"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

