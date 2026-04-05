#!/usr/bin/env bash
# format-on-write.sh — PostToolUse hook for Write|Edit|MultiEdit
#
# Config-driven auto-formatting. Nodes register formatters via .claude/lint.json.
# No built-in formatters — formatting is always project-specific.
#
# Exit 0 always — formatting failures should never block writes.

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# ---------------------------------------------------------------------------
# Project-specific formatters (from .claude/lint.json)
#
# Format:
# {
#   "formatters": {
#     "*.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md": { "format": "npx prettier --write", "name": "Prettier" },
#     "*.py": { "format": "ruff format", "name": "Ruff" },
#     "*.go": { "format": "gofmt -w", "name": "gofmt" },
#     "*.rs": { "format": "rustfmt", "name": "rustfmt" },
#     "*.sh": { "format": "shfmt -w", "name": "shfmt" }
#   }
# }
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
      format_cmd=$(jq -r --arg p "$pattern" '.formatters[$p].format' "$LINT_CONFIG")
      name=$(jq -r --arg p "$pattern" '.formatters[$p].name // "Formatter"' "$LINT_CONFIG")

      if [[ -n "$format_cmd" && "$format_cmd" != "null" ]]; then
        base_cmd=$(echo "$format_cmd" | awk '{print $1}')
        if command -v "$base_cmd" >/dev/null 2>&1; then
          $format_cmd "$FILE_PATH" 2>/dev/null || true
        fi
      fi
    fi
  done < <(jq -r '.formatters | keys[]' "$LINT_CONFIG" 2>/dev/null)
fi

exit 0
