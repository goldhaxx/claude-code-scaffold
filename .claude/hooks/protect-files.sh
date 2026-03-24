#!/usr/bin/env bash
# protect-files.sh — PreToolUse hook for Write|Edit|MultiEdit
# Blocks writes to sensitive files and protected scaffold files.
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Nothing to check if no file path
[[ -z "$FILE_PATH" ]] && exit 0

# --- Sensitive files (secrets, credentials, environment) ---
case "$FILE_PATH" in
  *.env|*.env.*|*credentials*|*secret*|*.pem|*.key|*id_rsa*)
    echo "BLOCKED: Cannot write to sensitive file: $FILE_PATH" >&2
    echo "These files may contain secrets and should be managed outside of Claude." >&2
    exit 2
    ;;
esac

# --- Protected scaffold files ---
case "$FILE_PATH" in
  *docs/scaffold-guide/scaffold-framework.md)
    echo "BLOCKED: scaffold-framework.md is research source material — read-only." >&2
    echo "Only modify with explicit user approval for paradigm shifts or new research." >&2
    exit 2
    ;;
esac

# --- Generated/dependency directories ---
case "$FILE_PATH" in
  */node_modules/*|*/dist/*|*/generated/*|*/.git/*)
    echo "BLOCKED: Cannot write to managed directory: $FILE_PATH" >&2
    exit 2
    ;;
esac

exit 0
