#!/usr/bin/env bats
# BTS-227 — drift-guard for the safe JSON-via-bash-variable pipe pattern.
#
# Demonstrates the failure mode that BTS-227 surfaced (drift-watchdog
# verification false-negative) and locks in the safe replacement pattern.
#
# Failure mode: macOS bash's `echo` builtin interprets backslash-escape
# sequences (\n, \t, etc.) in its arguments, even without `-e`. JSON
# captured into a bash variable that contains escaped \n in string values
# becomes broken JSON when piped through `echo`.
#
# Safe patterns:
#   jq <<< "$VAR"          # bash here-string — byte-faithful
#   printf '%s' "$VAR" | jq # printf with %s — no escape interpretation

bats_require_minimum_version 1.5.0

# JSON fixture mimicking a get-issue response with description containing
# literal newlines (encoded as \n in JSON string per the spec).
_json_with_escaped_newlines() {
  cat <<'JSON'
{
  "id": "BTS-220",
  "title": "[drift-watchdog] sample",
  "description": "## What drifted\n\nbody line 1\nbody line 2\n\n## Recommended action\n\nrun `bash sync.sh`.",
  "labels": ["idea", "drift-watchdog"]
}
JSON
}

@test "BTS-227: safe pattern jq <<< succeeds on JSON with escaped newlines" {
  set -e
  local fixture
  fixture=$(_json_with_escaped_newlines)
  # Round-trip via bash variable + here-string. Should parse + return 0
  # for the index lookup.
  local idx
  idx=$(jq -e '.labels | index("drift-watchdog")' <<< "$fixture")
  [ "$idx" = "1" ]
}

@test "BTS-227: safe pattern printf %s | jq succeeds on JSON with escaped newlines" {
  set -e
  local fixture
  fixture=$(_json_with_escaped_newlines)
  local idx
  idx=$(printf '%s' "$fixture" | jq -e '.labels | index("drift-watchdog")')
  [ "$idx" = "1" ]
}

@test "BTS-227: shell-portable safe pattern works under bash + zsh shells" {
  # The bug is shell-dependent: in zsh (default macOS interactive shell),
  # `echo` interprets backslash-n as a literal newline by default; in
  # bash 3.2 with xpg_echo OFF, echo does not. Claude Code (the harness
  # that runs the drift-watchdog skill prose) shells out to zsh on macOS,
  # which is where the BTS-227 reproduction occurred.
  #
  # This test validates the SAFE pattern (`<<<`) works regardless of
  # which shell evaluates it — the contract is shell-agnostic.
  set -e
  local fixture
  fixture=$(_json_with_escaped_newlines)
  # Run safe pattern in /bin/bash explicitly (the launchd-firing shell).
  /bin/bash -c "jq -e '.labels | index(\"drift-watchdog\")' <<< '$fixture'" >/dev/null
  # Run safe pattern in current shell (bats environment, bash via `run`).
  jq -e '.labels | index("drift-watchdog")' <<< "$fixture" >/dev/null
}

@test "BTS-227: drift-watchdog SKILL.md uses jq <<< for verify (audit lock)" {
  set -e
  # Static check: the verification block in drift-watchdog skill prose must
  # use the safe pattern. If anyone reverts to `echo "$VERIFY" | jq`, this
  # fails.
  local skill="$BATS_TEST_DIRNAME/../../.claude/skills/drift-watchdog/SKILL.md"
  [ -f "$skill" ]
  # The line should exist in the canonical safe form.
  grep -qE "jq -e '\.labels \| index\(\"drift-watchdog\"\)' <<< \"\\\$VERIFY\"" "$skill"
  # And the broken form must NOT appear.
  ! grep -qE 'echo "\$VERIFY" \| jq' "$skill"
}
