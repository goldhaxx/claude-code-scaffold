#!/usr/bin/env bash
# commit-msg-lint.sh — PostToolUse hook for Bash
# Warns when a git commit message doesn't follow conventional commit format.
# Format: type(scope): description  OR  type: description
# Exit 0 always (warn, never block).

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
  echo "WARNING: Commit message does not follow conventional format" >&2
  echo "  Got: $COMMIT_MSG" >&2
  echo "  Expected: type(scope): description" >&2
  echo "  Valid types: feat, fix, refactor, test, docs, chore, perf" >&2
fi

exit 0
