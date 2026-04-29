#!/usr/bin/env bash
# branch-name-lint.sh — PostToolUse hook for Bash
# Warns when a branch is created not matching the claude/<type>/<name> convention.
# Exit 0 always (warn, never block).

# @manifest
# purpose: PostToolUse Bash advisory that detects `git checkout -b <name>` or `git switch -c <name>` and warns to stderr when the new branch doesn't match the `claude/<feat|fix|refactor|test|docs|chore>/<name>` convention. Never blocks — visibility-only nudge so the operator catches drift from the workflow.md naming convention before the PR title goes out.
# input: stdin JSON envelope `{tool_input:{command}}` from Claude Code's PostToolUse contract
# output: exit-code 0 always (advisory hook, never blocks)
# output: stderr on convention violation: WARNING with example
# caller: .claude/settings.json
# depends-on: jq
# side-effect: writes-stderr-on-violation
# failure-mode: never-fails | exit=0 | visible=stderr-WARNING-when-convention-broken | mitigation=rename-branch-to-claude/type/name
# contract: never-blocks
# contract: silent-when-no-branch-creation-detected
# anchor: BTS-251 (manifest seed)

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
  # @side-effect: writes-stderr-on-violation
  echo "WARNING: Branch '$BRANCH_NAME' does not follow convention: claude/<type>/<name>" >&2
  echo "Valid types: feat, fix, refactor, test, docs, chore" >&2
  echo "Example: claude/feat/auth-system" >&2
fi

# @failure-mode: never-fails
exit 0
