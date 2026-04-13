#!/usr/bin/env bash
# guard-force-push.sh — PreToolUse hook for Bash
# Blocks force push operations to prevent overwriting remote history.
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Only check git push commands
if [[ ! "$COMMAND" =~ git[[:space:]]+push ]]; then
  exit 0
fi

# Allow bypass with ALLOW_FORCE=1
if [[ "$COMMAND" =~ ALLOW_FORCE=1 ]]; then
  exit 0
fi

# Block force push variants: --force, -f, --force-with-lease
if [[ "$COMMAND" =~ --force|[[:space:]]-f[[:space:]]|[[:space:]]-f$|^git[[:space:]]+push[[:space:]]+-f ]]; then
  echo "BLOCKED: force push is not allowed — it overwrites remote history." >&2
  echo "  To bypass: ALLOW_FORCE=1 git push --force" >&2
  exit 2
fi

exit 0
