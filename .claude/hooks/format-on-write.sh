#!/usr/bin/env bash
# format-on-write.sh — PostToolUse hook for Write|Edit|MultiEdit
#
# Config-driven auto-formatting. Nodes register formatters via .claude/lint.json.
# No built-in formatters — formatting is always project-specific.
#
# Exit 0 always — formatting failures should never block writes.

# @manifest
# purpose: PostToolUse Write/Edit/MultiEdit hook that reads `.claude/lint.json`'s `formatters` map (glob → `{format, name}`) and runs the matching formatter (Prettier / Ruff / gofmt / rustfmt / shfmt / etc.) on the just-written file. Provider-neutral; ships zero built-in formatters — every project chooses. Never blocks: a formatter failure is silent (formatters mutate-on-pass; if the formatter fails, leave the file alone).
# input: stdin JSON envelope `{tool_input:{file_path}}` from Claude Code's PostToolUse contract
# input: file `.claude/lint.json` (config — `{formatters:{<glob>:{format, name}}}`)
# output: exit-code 0 always
# output: side-effect — file rewritten in place by the matched formatter
# caller: .claude/settings.json
# depends-on: jq
# depends-on: awk
# side-effect: rewrites-file-via-formatter
# failure-mode: never-fails | exit=0 | visible=silent | mitigation=formatter-errors-suppressed-deliberately
# contract: never-blocks
# contract: silent-when-no-config-or-no-matching-glob
# contract: silent-when-formatter-binary-missing
# anchor: BTS-251 (manifest seed)

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
          # @side-effect: rewrites-file-via-formatter
          $format_cmd "$FILE_PATH" 2>/dev/null || true
        fi
      fi
    fi
  done < <(jq -r '.formatters | keys[]' "$LINT_CONFIG" 2>/dev/null)
fi

# @failure-mode: never-fails
exit 0
