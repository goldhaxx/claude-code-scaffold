#!/usr/bin/env bash
# context-budget.sh — Measure token cost of always-loaded scaffold files.
#
# Reports per-file and aggregate token estimates for files that load into
# Claude's context at every session start. Budget thresholds are model-aware.
#
# Exit codes:
#   0 — HEALTHY (under 70% of budget)
#   1 — WARNING (70-90% of budget)
#   2 — CRITICAL (over 90% of budget), or usage error
#
# Usage:
#   context-budget.sh check [--project-dir DIR] [--text] [--budget N]
#                           [--context-window N] [--model MODEL_ID]

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

PROJECT_DIR="."
GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
TEXT_MODE=false
BUDGET_FLAG=""
CONTEXT_WINDOW_FLAG=""
MODEL_FLAG=""

DEFAULT_CONTEXT_WINDOW=200000
BUDGET_PERCENT=4  # 4% of context window

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

CMD=""

usage() {
  echo "Usage: context-budget.sh check [--project-dir DIR] [--global-claude-md PATH] [--text] [--budget N] [--context-window N] [--model MODEL_ID]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    check)
      CMD="$1"; shift ;;
    --project-dir)
      PROJECT_DIR="$2"; shift 2 ;;
    --global-claude-md)
      GLOBAL_CLAUDE_MD="$2"; shift 2 ;;
    --text)
      TEXT_MODE=true; shift ;;
    --budget)
      BUDGET_FLAG="$2"; shift 2 ;;
    --context-window)
      CONTEXT_WINDOW_FLAG="$2"; shift 2 ;;
    --model)
      MODEL_FLAG="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -z "$CMD" ]] && usage

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Measure a single file. Outputs JSON object: {path, lines, chars, estimated_tokens}
measure_file() {
  local filepath="$1"

  local chars lines tokens
  chars=$(wc -c < "$filepath" | tr -d ' ')
  lines=$(wc -l < "$filepath" | tr -d ' ')
  tokens=$(( (chars + 3) / 4 ))

  jq -n --arg p "$filepath" --argjson l "$lines" --argjson c "$chars" --argjson t "$tokens" \
    '{path: $p, lines: $l, chars: $c, estimated_tokens: $t}'
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_check() {
  local files_json="[]"
  local warnings_json="[]"

  # Global CLAUDE.md (optional — silently skip if missing)
  if [[ -f "$GLOBAL_CLAUDE_MD" ]]; then
    local entry
    entry=$(measure_file "$GLOBAL_CLAUDE_MD")
    files_json=$(echo "$files_json" | jq --argjson e "$entry" '. + [$e]')
  fi

  # Project CLAUDE.md (expected — warn if missing)
  if [[ -f "$PROJECT_DIR/CLAUDE.md" ]]; then
    local entry
    entry=$(measure_file "$PROJECT_DIR/CLAUDE.md")
    files_json=$(echo "$files_json" | jq --argjson e "$entry" '. + [$e]')

    # Check line count threshold (AC-10)
    local claude_lines
    claude_lines=$(wc -l < "$PROJECT_DIR/CLAUDE.md" | tr -d ' ')
    if [[ "$claude_lines" -gt 80 ]]; then
      warnings_json=$(echo "$warnings_json" | jq --arg p "$PROJECT_DIR/CLAUDE.md" --argjson l "$claude_lines" \
        '. + [{type: "line_count", path: $p, lines: $l, message: "CLAUDE.md exceeds 80-line recommended maximum"}]')
    fi
  else
    warnings_json=$(echo "$warnings_json" | jq --arg p "$PROJECT_DIR/CLAUDE.md" \
      '. + [{type: "missing_file", path: $p, message: "Project CLAUDE.md not found"}]')
  fi

  # Rules files
  for rule in "$PROJECT_DIR"/.claude/rules/*.md; do
    [[ -f "$rule" ]] || continue
    local entry
    entry=$(measure_file "$rule")
    files_json=$(echo "$files_json" | jq --argjson e "$entry" '. + [$e]')
  done

  # Settings file
  if [[ -f "$PROJECT_DIR/.claude/settings.json" ]]; then
    local entry
    entry=$(measure_file "$PROJECT_DIR/.claude/settings.json")
    files_json=$(echo "$files_json" | jq --argjson e "$entry" '. + [$e]')
  fi

  # .claudeignore
  if [[ -f "$PROJECT_DIR/.claudeignore" ]]; then
    local entry
    entry=$(measure_file "$PROJECT_DIR/.claudeignore")
    files_json=$(echo "$files_json" | jq --argjson e "$entry" '. + [$e]')
  fi

  # Compute totals
  local total_lines total_chars total_tokens
  total_lines=$(echo "$files_json" | jq '[.[].lines] | add // 0')
  total_chars=$(echo "$files_json" | jq '[.[].chars] | add // 0')
  total_tokens=$(echo "$files_json" | jq '[.[].estimated_tokens] | add // 0')

  # Determine context window from flags (precedence: budget > context-window > model > default)
  local context_window budget_ceiling source model
  context_window=$DEFAULT_CONTEXT_WINDOW
  source="default"
  model="null"

  # Model lookup (bash 3 compatible — no associative arrays)
  if [[ -n "$MODEL_FLAG" ]]; then
    model="$MODEL_FLAG"
    source="model"
    case "$MODEL_FLAG" in
      claude-opus-4-6\[1m\]) context_window=1000000 ;;
      claude-opus-4-6)       context_window=200000 ;;
      claude-sonnet-4-6)     context_window=200000 ;;
      claude-haiku-4-5)      context_window=200000 ;;
      *)
        echo "WARNING: Unknown model '$MODEL_FLAG', defaulting to ${DEFAULT_CONTEXT_WINDOW} token context window" >&2
        context_window=$DEFAULT_CONTEXT_WINDOW
        ;;
    esac
  fi

  # --context-window overrides model lookup
  if [[ -n "$CONTEXT_WINDOW_FLAG" ]]; then
    context_window=$CONTEXT_WINDOW_FLAG
    source="context-window"
  fi

  # Compute budget ceiling from context window
  budget_ceiling=$(( context_window * BUDGET_PERCENT / 100 ))

  # --budget overrides everything
  if [[ -n "$BUDGET_FLAG" ]]; then
    budget_ceiling=$BUDGET_FLAG
    source="flag"
  fi

  # Compute budget percentage
  local budget_percent
  if [[ "$budget_ceiling" -gt 0 ]]; then
    # Integer math: multiply by 100 first for precision, then by 10 for one decimal
    budget_percent=$(awk "BEGIN {printf \"%.1f\", ($total_tokens / $budget_ceiling) * 100}")
  else
    budget_percent="0.0"
  fi

  # Determine status and exit code
  local status_label exit_code
  local threshold_warning=$(( budget_ceiling * 70 / 100 ))
  local threshold_critical=$(( budget_ceiling * 90 / 100 ))

  if [[ "$total_tokens" -ge "$threshold_critical" ]]; then
    status_label="CRITICAL"
    exit_code=2
  elif [[ "$total_tokens" -ge "$threshold_warning" ]]; then
    status_label="WARNING"
    exit_code=1
  else
    status_label="HEALTHY"
    exit_code=0
  fi

  # Output
  if [[ "$TEXT_MODE" == "true" ]]; then
    print_text_report "$files_json" "$total_lines" "$total_tokens" "$budget_ceiling" \
      "$budget_percent" "$status_label" "$context_window" "$model" "$warnings_json"
  else
    jq -n --argjson files "$files_json" \
      --argjson tl "$total_lines" --argjson tc "$total_chars" --argjson tt "$total_tokens" \
      --arg bp "$budget_percent" --arg st "$status_label" \
      --arg model "$model" --argjson cw "$context_window" --argjson bc "$budget_ceiling" --arg src "$source" \
      --argjson warnings "$warnings_json" \
      '{
        files: $files,
        totals: {lines: $tl, chars: $tc, estimated_tokens: $tt, budget_percent: ($bp | tonumber), status: $st},
        context: {model: (if $model == "null" then null else $model end), context_window: $cw, budget_ceiling: $bc, source: $src},
        warnings: $warnings
      }'
  fi

  return "$exit_code"
}

# ---------------------------------------------------------------------------
# Text output
# ---------------------------------------------------------------------------

print_text_report() {
  local files_json="$1"
  local total_lines="$2"
  local total_tokens="$3"
  local budget_ceiling="$4"
  local budget_percent="$5"
  local status_label="$6"
  local context_window="$7"
  local model="$8"
  local warnings_json="$9"

  echo "Context Budget Report"
  echo "====================="
  echo ""

  # Context info line
  if [[ "$model" != "null" ]]; then
    echo "Model: $model  |  Context window: $context_window tokens  |  Budget ceiling: $budget_ceiling tokens"
  else
    echo "Context window: $context_window tokens  |  Budget ceiling: $budget_ceiling tokens"
  fi
  echo ""

  # Table header
  printf "%-50s %8s %8s %8s\n" "File" "Lines" "Tokens" "% Budget"
  printf "%-50s %8s %8s %8s\n" "----" "-----" "------" "--------"

  # File rows
  echo "$files_json" | jq -r '.[] | "\(.path)\t\(.lines)\t\(.estimated_tokens)"' | while IFS=$'\t' read -r path lines tokens; do
    # Shorten path for display — keep .claude/ prefix for rules/settings, mark global
    local display_path
    if [[ "$path" == *"/.claude/CLAUDE.md" ]] || [[ "$path" == "$HOME/.claude/CLAUDE.md" ]] || [[ "$path" == *"/global-claude"* ]]; then
      display_path="~/.claude/CLAUDE.md (global)"
    else
      display_path=$(echo "$path" | sed "s|.*/\(\.claude/[^/]*/[^/]*\)$|\1|; s|.*/\([^/]*\)$|\1|" | head -c 50)
    fi
    local pct
    pct=$(awk "BEGIN {printf \"%.1f\", ($tokens / $budget_ceiling) * 100}")
    printf "%-50s %8s %8s %7s%%\n" "$display_path" "$lines" "$tokens" "$pct"
  done

  # Total row
  printf "%-50s %8s %8s %8s\n" "" "-----" "------" "--------"
  printf "%-50s %8s %8s %7s%%\n" "TOTAL" "$total_lines" "$total_tokens" "$budget_percent"
  echo ""

  # Status
  echo "Status: $status_label ($budget_percent% of $budget_ceiling token budget)"

  # Warnings
  local warning_count
  warning_count=$(echo "$warnings_json" | jq 'length')
  if [[ "$warning_count" -gt 0 ]]; then
    echo ""
    echo "Warnings:"
    echo "$warnings_json" | jq -r '.[] | "  - \(.message)"'
  fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$CMD" in
  check) cmd_check ;;
  *)     usage ;;
esac
