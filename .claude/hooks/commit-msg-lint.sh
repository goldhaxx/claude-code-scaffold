#!/usr/bin/env bash
# commit-msg-lint.sh — PostToolUse hook for Bash
# Warns when a git commit message doesn't follow conventional commit format.
# Format: type(scope): description  OR  type: description
# Exit 0 always (warn, never block).

# @manifest
# purpose: PostToolUse Bash advisory that scans `git commit -m "<msg>"` invocations and warns to stderr when the message doesn't match conventional-commit shape `type(scope)?: description` (types: feat / fix / refactor / test / docs / chore / perf). Skips heredoc and interactive commits (no -m flag visible). Never blocks — same nudge philosophy as branch-name-lint.
# input: stdin JSON envelope `{tool_input:{command}}` from Claude Code's PostToolUse contract
# output: exit-code 0 always
# output: stderr on convention violation: WARNING with the offending message + expected shape
# caller: .claude/settings.json
# depends-on: jq
# side-effect: writes-stderr-on-violation
# failure-mode: never-fails | exit=0 | visible=stderr-WARNING-when-convention-broken | mitigation=use-type(scope):-prefix
# contract: never-blocks
# contract: silent-on-non-commit-or-heredoc-or-interactive-commits
# anchor: BTS-251 (manifest seed)

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Only check git commit commands with -m flag
if [[ ! "$COMMAND" =~ git[[:space:]]+commit[[:space:]] ]]; then
  exit 0
fi

# Extract message from -m flag (handle both single and double quotes)
COMMIT_MSG=""
if [[ "$COMMAND" =~ -m[[:space:]]+\"([^\"]+)\" ]]; then
  COMMIT_MSG="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ -m[[:space:]]+\'([^\']+)\' ]]; then
  COMMIT_MSG="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ -m[[:space:]]+([^[:space:]]+) ]]; then
  COMMIT_MSG="${BASH_REMATCH[1]}"
fi

# No -m flag found (heredoc or interactive commit) — skip
[[ -z "$COMMIT_MSG" ]] && exit 0

# Validate conventional commit format
VALID_TYPES="feat|fix|refactor|test|docs|chore|perf"
if [[ ! "$COMMIT_MSG" =~ ^($VALID_TYPES)(\(.+\))?:[[:space:]].+ ]]; then
  # @side-effect: writes-stderr-on-violation
  echo "WARNING: Commit message does not follow conventional format" >&2
  echo "  Got: $COMMIT_MSG" >&2
  echo "  Expected: type(scope): description" >&2
  echo "  Valid types: feat, fix, refactor, test, docs, chore, perf" >&2
fi

# @failure-mode: never-fails
exit 0
