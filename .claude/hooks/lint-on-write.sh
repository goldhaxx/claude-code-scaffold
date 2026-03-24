#!/usr/bin/env bash
# lint-on-write.sh — PostToolUse hook for Write|Edit|MultiEdit
#
# Config-driven syntax validation. The hub provides universal linters (sh, json, yaml).
# Nodes add project-specific linters via .claude/lint.json without modifying this script.
#
# Exit 2 blocks the write (syntax error must be fixed).
# Exit 0 allows the write to proceed.

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

LINT_ERROR=$(mktemp)
trap 'rm -f "$LINT_ERROR"' EXIT

# ---------------------------------------------------------------------------
# Run a linter command. If it fails, block the write.
# Usage: run_linter "description" command arg1 arg2 ...
# ---------------------------------------------------------------------------
run_linter() {
  local desc="$1"; shift
  if ! "$@" 2>"$LINT_ERROR"; then
    echo "BLOCKED: $desc — $FILE_PATH" >&2
    cat "$LINT_ERROR" >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Built-in linters (universal — work in any project)
# ---------------------------------------------------------------------------
case "$FILE_PATH" in
  *.sh|*.bash)
    run_linter "Bash syntax error" bash -n "$FILE_PATH"
    ;;
  *.json)
    if command -v jq >/dev/null 2>&1; then
      run_linter "Invalid JSON" jq empty "$FILE_PATH"
    fi
    ;;
  *.yaml|*.yml)
    if command -v python3 >/dev/null 2>&1; then
      run_linter "Invalid YAML" python3 -c "import yaml; yaml.safe_load(open('$FILE_PATH'))"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# File size check — warn on large files that degrade context performance.
# Claude Code warns at 40k chars for always-loaded files. We block at 40k
# for known always-loaded files and warn (but allow) at 80k for others.
# ---------------------------------------------------------------------------
ALWAYS_LOADED_PATTERNS="CLAUDE.md|docs/scaffold-guide/index.md|.claude/rules/*.md"
MAX_ALWAYS_LOADED=40000
MAX_GENERAL=80000

char_count=$(wc -c < "$FILE_PATH" 2>/dev/null | tr -d ' ')
if [[ -n "$char_count" ]]; then
  is_always_loaded=false
  FILE_BASENAME=$(basename "$FILE_PATH")
  FILE_RELPATH="$FILE_PATH"
  IFS='|' read -ra al_patterns <<< "$ALWAYS_LOADED_PATTERNS"
  for pat in "${al_patterns[@]}"; do
    # shellcheck disable=SC2254
    case "$pat" in
      */*)
        # Path pattern (e.g., .claude/rules/*.md) — match against full path
        case "$FILE_RELPATH" in
          *$pat) is_always_loaded=true; break ;;
        esac
        ;;
      *)
        # Filename pattern (e.g., CLAUDE.md) — match against basename only
        case "$FILE_BASENAME" in
          $pat) is_always_loaded=true; break ;;
        esac
        ;;
    esac
  done

  if [[ "$is_always_loaded" == "true" && "$char_count" -gt "$MAX_ALWAYS_LOADED" ]]; then
    echo "BLOCKED: File too large for always-loaded context — $FILE_PATH (${char_count} chars > ${MAX_ALWAYS_LOADED} limit). See BTS-26." >&2
    exit 2
  elif [[ "$char_count" -gt "$MAX_GENERAL" ]]; then
    echo "WARNING: Large file — $FILE_PATH (${char_count} chars > ${MAX_GENERAL} recommended). Consider splitting." >&2
  fi
fi

# ---------------------------------------------------------------------------
# Project-specific linters (from .claude/lint.json)
#
# Format:
# {
#   "linters": {
#     "*.py": { "check": "python3 -m py_compile", "name": "Python syntax" },
#     "*.ts|*.tsx": { "check": "npx tsc --noEmit", "name": "TypeScript" },
#     "*.cpp|*.ino": { "check": "platformio check", "name": "PlatformIO" },
#     "*.rs": { "check": "cargo check", "name": "Rust" }
#   }
# }
#
# Each linter entry: "glob_pattern": { "check": "command", "name": "display name" }
# The file path is appended to the check command automatically.
# ---------------------------------------------------------------------------
LINT_CONFIG=".claude/lint.json"
if [[ -f "$LINT_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r pattern; do
    # Check if file matches the glob pattern (supports | for alternatives)
    match=false
    IFS='|' read -ra globs <<< "$pattern"
    for glob in "${globs[@]}"; do
      # shellcheck disable=SC2254
      case "$FILE_PATH" in
        $glob) match=true; break ;;
      esac
    done

    if [[ "$match" == "true" ]]; then
      check_cmd=$(jq -r --arg p "$pattern" '.linters[$p].check' "$LINT_CONFIG")
      name=$(jq -r --arg p "$pattern" '.linters[$p].name // "Lint check"' "$LINT_CONFIG")

      if [[ -n "$check_cmd" && "$check_cmd" != "null" ]]; then
        # Check if the command exists
        base_cmd=$(echo "$check_cmd" | awk '{print $1}')
        if command -v "$base_cmd" >/dev/null 2>&1; then
          run_linter "$name error" $check_cmd "$FILE_PATH"
        fi
      fi
    fi
  done < <(jq -r '.linters | keys[]' "$LINT_CONFIG" 2>/dev/null)
fi

exit 0
