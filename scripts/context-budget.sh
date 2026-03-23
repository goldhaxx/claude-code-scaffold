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
# Commands
# ---------------------------------------------------------------------------

cmd_check() {
  echo '{}'
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$CMD" in
  check) cmd_check ;;
  *)     usage ;;
esac
