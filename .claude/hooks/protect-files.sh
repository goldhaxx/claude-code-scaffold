#!/usr/bin/env bash
# protect-files.sh — PreToolUse hook for Write|Edit|MultiEdit
# Blocks writes to sensitive files and protected preset files.
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

# @manifest
# purpose: PreToolUse Write/Edit/MultiEdit gate that blocks writes to (1) sensitive files (`.env`, `*credentials*`, `*secret*`, `*.pem`, `*.key`, `*id_rsa*`), (2) protected preset files (`.ccanvil/guide/foundations.md` — research source material), and (3) generated/dependency directories (`node_modules/`, `dist/`, `generated/`, `.git/`). Pattern-based; no regex DSL — bash glob `case` matches.
# input: stdin JSON envelope `{tool_input:{file_path}}` from Claude Code's PreToolUse contract
# output: exit-codes 0 allow / 2 block
# output: stderr on block: BLOCKED reason
# caller: .claude/settings.json
# depends-on: jq
# side-effect: writes-stderr-on-block
# failure-mode: sensitive-file-blocked | exit=2 | visible=stderr-BLOCKED-with-rationale | mitigation=manage-secrets-outside-claude
# failure-mode: foundations-write-blocked | exit=2 | visible=stderr-BLOCKED-with-rationale | mitigation=explicit-user-approval-for-paradigm-shift
# failure-mode: managed-dir-write-blocked | exit=2 | visible=stderr-BLOCKED-with-rationale | mitigation=write-to-source-not-generated
# contract: never-blocks-non-write-tools
# anchor: BTS-251 (manifest seed)

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Nothing to check if no file path
[[ -z "$FILE_PATH" ]] && exit 0

# --- Sensitive files (secrets, credentials, environment) ---
case "$FILE_PATH" in
  *.env|*.env.*|*credentials*|*secret*|*.pem|*.key|*id_rsa*)
    # @failure-mode: sensitive-file-blocked
    # @side-effect: writes-stderr-on-block
    echo "BLOCKED: Cannot write to sensitive file: $FILE_PATH" >&2
    echo "These files may contain secrets and should be managed outside of Claude." >&2
    exit 2
    ;;
esac

# --- Protected preset files ---
case "$FILE_PATH" in
  *.ccanvil/guide/foundations.md)
    # @failure-mode: foundations-write-blocked
    echo "BLOCKED: foundations.md is research source material — read-only." >&2
    echo "Only modify with explicit user approval for paradigm shifts or new research." >&2
    exit 2
    ;;
esac

# --- Generated/dependency directories ---
case "$FILE_PATH" in
  */node_modules/*|*/dist/*|*/generated/*|*/.git/*)
    # @failure-mode: managed-dir-write-blocked
    echo "BLOCKED: Cannot write to managed directory: $FILE_PATH" >&2
    exit 2
    ;;
esac

exit 0
