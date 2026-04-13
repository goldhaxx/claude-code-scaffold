#!/usr/bin/env bash
# guard-destructive.sh — PreToolUse hook for Bash
# Blocks destructive git operations: hard reset, force branch delete, remote delete, clean.
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Allow bypass with ALLOW_DESTRUCTIVE=1
if [[ "$COMMAND" =~ ALLOW_DESTRUCTIVE=1 ]]; then
  exit 0
fi

# Block git reset --hard
if [[ "$COMMAND" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
  echo "BLOCKED: git reset --hard discards commits and changes." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git reset --hard ..." >&2
  exit 2
fi

# Block git branch -D (force delete, uppercase D only)
if [[ "$COMMAND" =~ git[[:space:]]+branch[[:space:]]+-D[[:space:]] || "$COMMAND" =~ git[[:space:]]+branch[[:space:]]+-D$ ]]; then
  echo "BLOCKED: git branch -D force-deletes unmerged branches." >&2
  echo "  Use git branch -d for merged branches, or bypass: ALLOW_DESTRUCTIVE=1 git branch -D ..." >&2
  exit 2
fi

# Block git push origin --delete
if [[ "$COMMAND" =~ git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+--delete ]]; then
  echo "BLOCKED: git push --delete removes remote branches." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git push origin --delete ..." >&2
  exit 2
fi

# Block git clean -f (any variant with -f flag)
if [[ "$COMMAND" =~ git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f ]]; then
  echo "BLOCKED: git clean -f permanently deletes untracked files." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git clean -f ..." >&2
  exit 2
fi

exit 0
