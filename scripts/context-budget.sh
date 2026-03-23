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
  echo "Usage: context-budget.sh check [--project-dir DIR] [--text] [--budget N] [--context-window N] [--model MODEL_ID]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    check)
      CMD="$1"; shift ;;
    --project-dir)
      PROJECT_DIR="$2"; shift 2 ;;
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

  # Project CLAUDE.md
  if [[ -f "$PROJECT_DIR/CLAUDE.md" ]]; then
    local entry
    entry=$(measure_file "$PROJECT_DIR/CLAUDE.md")
    files_json=$(echo "$files_json" | jq --argjson e "$entry" '. + [$e]')
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

  jq -n --argjson files "$files_json" \
    --argjson tl "$total_lines" --argjson tc "$total_chars" --argjson tt "$total_tokens" \
    --arg bp "$budget_percent" --arg st "$status_label" \
    --arg model "$model" --argjson cw "$context_window" --argjson bc "$budget_ceiling" --arg src "$source" \
    '{
      files: $files,
      totals: {lines: $tl, chars: $tc, estimated_tokens: $tt, budget_percent: ($bp | tonumber), status: $st},
      context: {model: (if $model == "null" then null else $model end), context_window: $cw, budget_ceiling: $bc, source: $src}
    }'

  return "$exit_code"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$CMD" in
  check) cmd_check ;;
  *)     usage ;;
esac
