#!/usr/bin/env bash
# guard-force-push.sh — PreToolUse hook for Bash
# Blocks force push operations to prevent overwriting remote history.
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

# @manifest
# purpose: PreToolUse Bash gate that blocks `git push --force` / `-f` variants (including `--force-with-lease` shape) so Claude cannot rewrite remote history. Honors ALLOW_FORCE=1 prefix bypass for the rare deliberate force-push.
# input: stdin JSON envelope `{tool_input:{command}}` from Claude Code's PreToolUse contract
# output: exit-codes 0 allow / 2 block (stderr message becomes Claude's feedback)
# output: stderr on block: BLOCKED reason + bypass hint
# caller: .claude/settings.json
# depends-on: jq
# side-effect: writes-stderr-on-block
# failure-mode: force-push-blocked | exit=2 | visible=stderr-BLOCKED-message-with-bypass-hint | mitigation=ALLOW_FORCE=1-prefix-or-omit-force-flag
# contract: never-blocks-non-push
# contract: env-prefix-bypass-via-ALLOW_FORCE=1
# anchor: BTS-251 (manifest seed)

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
  # @failure-mode: force-push-blocked
  # @side-effect: writes-stderr-on-block
  echo "BLOCKED: force push is not allowed — it overwrites remote history." >&2
  echo "  To bypass: ALLOW_FORCE=1 git push --force" >&2
  exit 2
fi

exit 0
