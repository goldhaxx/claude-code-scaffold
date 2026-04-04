#!/usr/bin/env bash
# branch-name-lint.sh — PostToolUse hook for Bash
# Warns when a branch is created not matching the claude/<type>/<name> convention.
# Exit 0 always (warn, never block).

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Extract branch name from branch-creation commands
BRANCH_NAME=""
if [[ "$COMMAND" =~ git[[:space:]]+checkout[[:space:]]+-b[[:space:]]+([^[:space:]]+) ]]; then
  BRANCH_NAME="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ git[[:space:]]+switch[[:space:]]+-c[[:space:]]+([^[:space:]]+) ]]; then
  BRANCH_NAME="${BASH_REMATCH[1]}"
fi

# No branch creation detected — nothing to check
[[ -z "$BRANCH_NAME" ]] && exit 0

# Check against convention: claude/<type>/<name>
VALID_TYPES="feat|fix|refactor|test|docs|chore"
if [[ ! "$BRANCH_NAME" =~ ^claude/($VALID_TYPES)/ ]]; then
  echo "WARNING: Branch '$BRANCH_NAME' does not follow convention: claude/<type>/<name>" >&2
  echo "Valid types: feat, fix, refactor, test, docs, chore" >&2
  echo "Example: claude/feat/auth-system" >&2
fi

exit 0
