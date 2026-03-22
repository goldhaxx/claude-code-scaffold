#!/usr/bin/env bash
# lint-on-write.sh — PostToolUse hook for Write|Edit|MultiEdit
# Runs syntax checks after Claude writes files.
# Exit 2 blocks the write (syntax error must be fixed).
# Exit 0 allows the write to proceed.

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

case "$FILE_PATH" in
  *.sh)
    # Bash syntax check
    if ! bash -n "$FILE_PATH" 2>/tmp/lint-error.txt; then
      echo "BLOCKED: Bash syntax error in $FILE_PATH" >&2
      cat /tmp/lint-error.txt >&2
      exit 2
    fi
    ;;
  *.json)
    # JSON syntax check (if jq is available)
    if command -v jq >/dev/null 2>&1; then
      if ! jq empty "$FILE_PATH" 2>/tmp/lint-error.txt; then
        echo "BLOCKED: Invalid JSON in $FILE_PATH" >&2
        cat /tmp/lint-error.txt >&2
        exit 2
      fi
    fi
    ;;
  *.yaml|*.yml)
    # YAML syntax check (if python3 is available)
    if command -v python3 >/dev/null 2>&1; then
      if ! python3 -c "import yaml; yaml.safe_load(open('$FILE_PATH'))" 2>/tmp/lint-error.txt; then
        echo "BLOCKED: Invalid YAML in $FILE_PATH" >&2
        cat /tmp/lint-error.txt >&2
        exit 2
      fi
    fi
    ;;
  # Uncomment for your project's languages:
  # *.py)
  #   if ! python3 -m py_compile "$FILE_PATH" 2>/tmp/lint-error.txt; then
  #     echo "BLOCKED: Python syntax error in $FILE_PATH" >&2
  #     cat /tmp/lint-error.txt >&2
  #     exit 2
  #   fi
  #   ;;
  # *.ts|*.tsx)
  #   if ! npx tsc --noEmit "$FILE_PATH" 2>/tmp/lint-error.txt; then
  #     echo "BLOCKED: TypeScript error in $FILE_PATH" >&2
  #     cat /tmp/lint-error.txt >&2
  #     exit 2
  #   fi
  #   ;;
esac

exit 0
