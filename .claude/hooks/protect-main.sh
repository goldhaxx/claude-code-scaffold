#!/usr/bin/env bash
# protect-main.sh — PreToolUse hook for Bash
# Blocks git commit on main/master to prevent divergent branch errors.
# The land command depends on this invariant: main never has local-only commits.
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

# @manifest
# purpose: PreToolUse Bash gate that blocks `git commit` while HEAD is on `main` or `master`. Preserves the lifecycle invariant the BTS-72 land flow relies on (local main is a cache of origin/main; never carries local-only commits). ALLOW_MAIN=1 prefix bypass for init / migration / hotfix / stasis-archive workflows.
# input: stdin JSON envelope `{tool_input:{command}}` from Claude Code's PreToolUse contract
# output: exit-codes 0 allow / 2 block
# output: stderr on block: BLOCKED reason + bypass hint
# caller: .claude/settings.json
# depends-on: jq
# depends-on: git
# side-effect: writes-stderr-on-block
# failure-mode: main-commit-blocked | exit=2 | visible=stderr-BLOCKED-message-with-bypass-hint | mitigation=use-feature-branch-or-ALLOW_MAIN=1-prefix
# contract: never-blocks-non-commit
# contract: env-prefix-bypass-via-ALLOW_MAIN=1
# anchor: BTS-251 (manifest seed)

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Only check git commit commands
if [[ ! "$COMMAND" =~ git[[:space:]]+commit ]]; then
  exit 0
fi

# Allow bypass with ALLOW_MAIN=1 (for init commits, migrations, hotfixes)
if [[ "$COMMAND" =~ ALLOW_MAIN=1 ]]; then
  exit 0
fi

# Check current branch
BRANCH=$(git branch --show-current 2>/dev/null || echo "")

if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  # @failure-mode: main-commit-blocked
  # @side-effect: writes-stderr-on-block
  echo "BLOCKED: Direct commits to main are not allowed. Create a feature branch first." >&2
  echo "  Use docs-check.sh activate <feature-id> to create a branch." >&2
  echo "  To bypass (init/migration/hotfix): ALLOW_MAIN=1 git commit -m \"...\"" >&2
  exit 2
fi

exit 0
