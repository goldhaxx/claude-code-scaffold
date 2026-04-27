#!/usr/bin/env bats
# BTS-202: guard-destructive.sh rm-rf detection scoped to combined flag
# clusters. Tightens the previous two-regex cross-line scan that fired on
# any unrelated `-r` + `-f` combination on the line (e.g., `jq -r ... ;
# rm -f /tmp/x`). Now requires r AND f in the SAME flag cluster, OR
# both --recursive AND --force long forms on the line.

bats_require_minimum_version 1.5.0

HOOK="$BATS_TEST_DIRNAME/../../.claude/hooks/guard-destructive.sh"

_run_hook() {
  local cmd="$1"
  local input
  input=$(jq -n --arg cmd "$cmd" '{tool_name: "Bash", tool_input: {command: $cmd}}')
  run bash -c "printf '%s' \"\$0\" | '$HOOK'" "$input"
}

# =========================================================================
# AC-1: jq -r + rm -f origin reproducer no longer blocks
# =========================================================================

@test "AC-1: jq -r .; rm -f /tmp/x does NOT block (origin reproducer)" {
  _run_hook 'echo foo | jq -r .; rm -f /tmp/notreal'
  [ "$status" -eq 0 ]
}

@test "AC-1: jq -r piped, rm -f at end does NOT block" {
  _run_hook 'cat .ccanvil/scratch.md | jq -r . && rm -f .ccanvil/scratch.md'
  [ "$status" -eq 0 ]
}

# =========================================================================
# AC-2: other unrelated r/f flag combos do NOT block
# =========================================================================

@test "AC-2: grep -F + rm -f does NOT block" {
  _run_hook "grep -F 'pattern' file.txt; rm -f /tmp/x"
  [ "$status" -eq 0 ]
}

@test "AC-2: git -C dir branch -r + rm -f does NOT block" {
  _run_hook "git -C /tmp/repo branch -r; rm -f /tmp/y"
  [ "$status" -eq 0 ]
}

@test "AC-2: find -name with .r in pattern + rm -f does NOT block" {
  _run_hook "find . -name '*.r' -print; rm -f /tmp/z"
  [ "$status" -eq 0 ]
}

# =========================================================================
# AC-3: canonical footguns still block
# =========================================================================

@test "AC-3: rm -rf /tmp/x still blocks" {
  _run_hook "rm -rf /tmp/x"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "AC-3: rm -fr /tmp/x still blocks" {
  _run_hook "rm -fr /tmp/x"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "AC-3: rm -Rf /tmp/x still blocks" {
  _run_hook "rm -Rf /tmp/x"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

@test "AC-3: rm -fR /tmp/x still blocks" {
  _run_hook "rm -fR /tmp/x"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOCKED"
}

# =========================================================================
# AC-4: cluster variations with extra letters still block
# =========================================================================

@test "AC-4: rm -rfv /tmp still blocks (verbose+rf)" {
  _run_hook "rm -rfv /tmp/x"
  [ "$status" -eq 2 ]
}

@test "AC-4: rm -vrf /tmp still blocks (verbose-then-rf)" {
  _run_hook "rm -vrf /tmp/x"
  [ "$status" -eq 2 ]
}

@test "AC-4: rm -rfi still blocks (rf+interactive)" {
  _run_hook "rm -rfi /tmp/x"
  [ "$status" -eq 2 ]
}

@test "AC-4: rm -fvR still blocks (force+verbose+R)" {
  _run_hook "rm -fvR /tmp/x"
  [ "$status" -eq 2 ]
}

# =========================================================================
# AC-5: long-form combination still blocks
# =========================================================================

@test "AC-5: rm --recursive --force /tmp/x still blocks" {
  _run_hook "rm --recursive --force /tmp/x"
  [ "$status" -eq 2 ]
}

@test "AC-5: rm --force --recursive /tmp/x still blocks (order-independent)" {
  _run_hook "rm --force --recursive /tmp/x"
  [ "$status" -eq 2 ]
}

# =========================================================================
# AC-6: split short-form NOT caught — documented trade-off
# =========================================================================

@test "AC-6: rm -r -f /tmp/x is NOT blocked (split-form trade-off)" {
  # Per ticket recommendation (C): accept that split short-form falls
  # through. Operator can ALLOW_DESTRUCTIVE=1 for deliberate use.
  _run_hook "rm -r -f /tmp/notreal"
  [ "$status" -eq 0 ]
}

# =========================================================================
# Drift-guard: BTS-202 reference present in guard-destructive.sh
# =========================================================================

@test "drift: BTS-202 referenced inline in guard-destructive.sh" {
  grep -q "BTS-202" "$HOOK"
}
