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

@test "BTS-155 AC-10: workspace fence blocks find /etc traversal" {
  set -e   # BTS-127
  input='{"tool_name":"Bash","tool_input":{"command":"find /etc -name \"*.conf\""}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "/etc"
}

@test "BTS-155 AC-11: workspace fence allows find /tmp/scratch" {
  # Whitelist prefix is "/tmp/" (with trailing slash); bare "/tmp" doesn't
  # match the case-glob pattern. Operators traversing inside /tmp use a
  # subpath. (Same convention as the BTS-146 AC-8 test for rm in /tmp.)
  input='{"tool_name":"Bash","tool_input":{"command":"find /tmp/scratch -name \"*.log\""}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

# =========================================================================
# guard-workspace.sh — sort -o output flag (BTS-157)
# =========================================================================

@test "BTS-157 AC-1: blocks sort -o ~/.zshrc" {
  set -e   # BTS-127
  input='{"tool_name":"Bash","tool_input":{"command":"sort -o ~/.zshrc input"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
  echo "$output" | grep -q "~/.zshrc"
}

@test "BTS-157 AC-2: blocks sort -o /etc/foo" {
  input='{"tool_name":"Bash","tool_input":{"command":"sort -o /etc/foo input"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-157 AC-3: allows sort -o ./local-output (relative path)" {
  input='{"tool_name":"Bash","tool_input":{"command":"sort -o ./local-output input"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-157 AC-4: allows sort -o ~/projects/ccanvil/foo (inside workspace)" {
  input='{"tool_name":"Bash","tool_input":{"command":"sort -o ~/projects/ccanvil/foo input"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-157 AC-5: allows sort -o /tmp/foo (whitelisted)" {
  input='{"tool_name":"Bash","tool_input":{"command":"sort -o /tmp/foo input"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-157 AC-6: bypass via ALLOW_OUTSIDE_WORKSPACE=1" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_OUTSIDE_WORKSPACE=1 sort -o ~/.zshrc input"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-157 AC-7: allows plain sort input (no -o)" {
  input='{"tool_name":"Bash","tool_input":{"command":"sort input"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-157 AC-8: blocks sort input > ~/.zshrc (redirect target via token scan)" {
  # Bonus coverage: once sort is a gated verb, the tilde token in the
  # redirect target trips the fence too — even though the hook doesn't
  # parse > as a redirect operator. Path B-adjacent free win.
  input='{"tool_name":"Bash","tool_input":{"command":"sort input > ~/.zshrc"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-157 AC-9: allows xsort -o ~/.zshrc (sort substring in another verb)" {
  input='{"tool_name":"Bash","tool_input":{"command":"xsort -o ~/.zshrc x"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

# AC-10 ("existing gates intact") is validated by the full bats-report.sh
# --parallel run, not a named per-AC test. Counted as covered when the
# pre-BTS-157 test count rises by exactly the number of new BTS-157 tests
# with no failures elsewhere.

# =========================================================================
# guard-workspace.sh — cat read fence (BTS-153)
# =========================================================================

@test "BTS-153 AC-1: blocks cat ~/.ssh/id_rsa" {
  set -e   # BTS-127
  input='{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "BTS-153 AC-2: blocks cat /etc/passwd" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat /etc/passwd"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-153 AC-3: blocks cat ~/.zshrc" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat ~/.zshrc"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-153 AC-4: allows cat ~/projects/ccanvil/CLAUDE.md (inside workspace)" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat ~/projects/ccanvil/CLAUDE.md"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-153 AC-5: allows cat ./relative/path" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat ./relative/path"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-153 AC-6: allows cat /tmp/foo" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat /tmp/foo"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-153 AC-7: allows cat /dev/null" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat /dev/null"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-153 AC-8: bypass via ALLOW_OUTSIDE_WORKSPACE=1" {
  input='{"tool_name":"Bash","tool_input":{"command":"ALLOW_OUTSIDE_WORKSPACE=1 cat ~/.ssh/id_rsa"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-153 AC-9: allows xcat /etc/foo (cat substring in another verb)" {
  input='{"tool_name":"Bash","tool_input":{"command":"xcat /etc/foo"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-153 AC-10: blocks cat /etc/foo in pipeline" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat /etc/foo | grep x"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-153 AC-11: allows cat with no path arg (heredoc-style)" {
  # `cat << EOF` has no path tokens; the fence has nothing to gate.
  input='{"tool_name":"Bash","tool_input":{"command":"cat << EOF"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

# =========================================================================
# BTS-151: git commit early-exit (false-positive fix for both hooks)
# =========================================================================

@test "BTS-151 AC-1: guard-destructive allows git commit with literal rm -rf in body" {
  # The BTS-156 regex matches rm + recursive + force anywhere in the
  # command string. Without an early-exit, a commit message that talks
  # about the rm-rf gate trips the destructive hook.
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(bts-156): add rm -rf shape gate\""}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-2: guard-workspace allows git commit with verb + path-shaped string in body" {
  # The workspace verb regex matches `bash`/`cat`/etc anywhere in the
  # command, then the path scan picks up `/stasis` from the message body.
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix bash hook for /stasis path\""}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-3: both hooks allow git commit -am with /tmp/foo in body" {
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -am \"msg with /tmp/foo\""}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-4: guard-workspace allows git commit -F /tmp/msg.txt" {
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -F /tmp/msg.txt"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-5: cat /etc/passwd still blocks (unchanged contract)" {
  input='{"tool_name":"Bash","tool_input":{"command":"cat /etc/passwd"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-151 AC-6: rm -rf still blocks (unchanged contract)" {
  input='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 2 ]
}

@test "BTS-151 AC-7: git status (no commit, no path scan) exits 0" {
  input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-8: git commit (no flags, opens editor) exits 0 from both hooks" {
  input='{"tool_name":"Bash","tool_input":{"command":"git commit"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-9 (known gap): git commit chained with rm -rf bypasses destructive check" {
  # Documented trade-off — chaining destructive ops after commit is rare.
  # If this test ever needs to flip to exit 2, the early-exit pattern
  # should be tightened to forbid chain operators in the command.
  input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\" && rm -rf /tmp/foo"}}'
  run bash -c "echo '$input' | '$DESTRUCTIVE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-10: env-prefix before git commit allowed" {
  input='{"tool_name":"Bash","tool_input":{"command":"LANG=en_US git commit -m \"msg with /tmp\""}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-10b: quoted env-prefix value with spaces still skipped" {
  # GIT_AUTHOR_NAME and GIT_COMMITTER_DATE are common automation prefixes
  # whose values contain spaces. The early-exit regex must accept the
  # quoted form.
  input='{"tool_name":"Bash","tool_input":{"command":"GIT_AUTHOR_NAME=\"Foo Bar\" git commit -m \"msg with /stasis\""}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151 AC-10c: single-quoted env-prefix value also skipped" {
  input='{"tool_name":"Bash","tool_input":{"command":"GIT_COMMITTER_DATE='\''2024-01-01 12:00:00'\'' git commit -m \"msg with /stasis\""}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
}

@test "BTS-151: git commit-tree (different verb, same prefix) is NOT auto-skipped" {
  # `commit-tree` is a plumbing command; the early-exit must word-anchor
  # on `commit` to avoid masking it. This test confirms the boundary.
  # Today commit-tree wouldn't trigger any path scan anyway (git isn't a
  # gated verb), so exit 0. The test value is in pinning the regex
  # boundary if future verbs make the contrast load-bearing.
  input='{"tool_name":"Bash","tool_input":{"command":"git commit-tree HEAD^{tree}"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 0 ]
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

@test "BTS-146 AC-12 (superseded by BTS-153): cat /etc/passwd now blocks" {
  # Original AC-12 asserted exit 0 (cat outside workspace was unblocked).
  # BTS-153 flipped the contract; this test now asserts the new behavior in
  # the same file location so a future regression on either side surfaces
  # immediately rather than silently dropping coverage.
  input='{"tool_name":"Bash","tool_input":{"command":"cat /etc/passwd"}}'
  run bash -c "echo '$input' | '$WORKSPACE_HOOK'"
  [ "$status" -eq 2 ]
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
