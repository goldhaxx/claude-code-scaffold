#!/usr/bin/env bats
# Tests for guard hooks: guard-force-push.sh, guard-destructive.sh, guard-workspace.sh
#
# Each test pipes JSON to the hook and checks exit code + output.

FORCE_PUSH_HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/guard-force-push.sh"
DESTRUCTIVE_HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/guard-destructive.sh"
WORKSPACE_HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/guard-workspace.sh"

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

@test "BTS-156 AC-2: blocks rm -r -f (split short flags)" {
  # Split flags are equivalent to -rf at the OS level; an agent might emit
  # this form as a natural variation. Without independent flag detection,
  # the cluster regex would miss this. Surfaced by code review.
  input='{"tool_name":"Bash","tool_input":{"command":"rm -r -f /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-3: blocks rm -r --force (mixed short+long)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -r --force /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-156 AC-3: blocks rm --recursive -f (mixed long+short)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm --recursive -f /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
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
# guard-workspace.sh — workspace fence (BTS-146)
# =========================================================================

@test "BTS-146 AC-1: blocks rm with absolute path outside workspace" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm /etc/foo"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "/etc/foo"
  echo "$output" | grep -q "ALLOW_OUTSIDE_WORKSPACE=1"
}

@test "BTS-146 AC-2: blocks cp when source is outside workspace" {
  input='{"tool_name":"Bash","tool_input":{"command":"cp ~/Downloads/x ~/projects/ccanvil/y"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "Downloads"
}

@test "BTS-146 AC-3: allows cp when both paths are inside workspace" {
  input='{"tool_name":"Bash","tool_input":{"command":"cp ~/projects/ccanvil/a ~/projects/ccanvil/b"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146 AC-4: blocks chmod on system bin path" {
  input='{"tool_name":"Bash","tool_input":{"command":"chmod 755 /usr/local/bin/foo"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "/usr/local/bin/foo"
}

@test "BTS-146 AC-5: blocks chown on macOS Library path" {
  input='{"tool_name":"Bash","tool_input":{"command":"chown user ~/Library/foo"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "Library"
}

@test "BTS-146 AC-6: blocks bash executing script outside workspace" {
  input='{"tool_name":"Bash","tool_input":{"command":"bash ~/Documents/script.sh"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "Documents"
}

@test "BTS-146 AC-7: blocks bash -c with quoted inline rm targeting system path" {
  input='{"tool_name":"Bash","tool_input":{"command":"bash -c \"rm /etc/foo\""}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "/etc/foo"
}

@test "BTS-146 AC-8: allows rm in /tmp" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm /tmp/foo"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146 AC-9: allows rm in /private/var/folders (macOS mktemp -d)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm /private/var/folders/xx/yy/T/test"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146 AC-10: allows rm with relative path" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm relative/path.txt"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146 AC-11: allows bash on relative script path" {
  input='{"tool_name":"Bash","tool_input":{"command":"bash .ccanvil/scripts/foo.sh"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146 AC-12: allows cat on system path (verb not in gated list)" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat /etc/passwd"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146 AC-13: ALLOW_OUTSIDE_WORKSPACE=1 bypass works" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_OUTSIDE_WORKSPACE=1 rm /etc/foo"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146: handles empty command" {
  input='{"tool_name":"Bash","tool_input":{}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146: allows rm in workspace via absolute path" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm /Users/zacharywright/projects/ccanvil/file"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-146: allows redirect to /dev/null" {
  input='{"tool_name":"Bash","tool_input":{"command":"cp file /dev/null"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

# guard-workspace.sh — bare-slash false-positive (BTS-147)

@test "BTS-147 AC-1: allows bare slash token (jq math/format string)" {
  input='{"tool_name":"Bash","tool_input":{"command":"bash script.sh | jq -r .a / .b"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-147 AC-3: real out-of-workspace path wins over bare slash" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm / /etc/foo"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "/etc/foo"
}

@test "BTS-147 AC-5: ALLOW_OUTSIDE_WORKSPACE=1 still bypasses on bare-slash commands" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_OUTSIDE_WORKSPACE=1 bash script | jq .a / .b"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-147 AC-6: single-char absolute path /a still hits the whitelist check" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm /a"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "/a"
}
