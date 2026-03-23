#!/usr/bin/env bash
# permissions-audit.sh — Deterministic permissions auditor for Claude Code settings.
#
# Parses Bash permission entries from .claude/settings.json and
# .claude/settings.local.json, classifies each as DANGER / UNREVIEWED / REVIEWED
# based on pattern matching and a decision log.
#
# Exit codes:
#   0 — all entries REVIEWED, no DANGER
#   1 — UNREVIEWED entries exist (no DANGER)
#   2 — DANGER entries exist (or usage/parse error)
#
# Usage:
#   permissions-audit.sh check [--settings-dir DIR] [--log FILE]
#   permissions-audit.sh init  [--settings-dir DIR] [--log FILE]

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

SETTINGS_DIR=".claude"
LOG_FILE=""  # set after parsing args; defaults to SETTINGS_DIR/permissions-log.json

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

CMD=""
TEXT_MODE=false
VERBOSE=false

usage() {
  echo "Usage: permissions-audit.sh <check|init> [--settings-dir DIR] [--log FILE] [--text] [--verbose]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    check|init)
      CMD="$1"; shift ;;
    --settings-dir)
      SETTINGS_DIR="$2"; shift 2 ;;
    --log)
      LOG_FILE="$2"; shift 2 ;;
    --text)
      TEXT_MODE=true; shift ;;
    --verbose)
      VERBOSE=true; shift ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -z "$CMD" ]] && usage

# Default log file location
[[ -z "$LOG_FILE" ]] && LOG_FILE="$SETTINGS_DIR/permissions-log.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Collect all permission entries from a settings file into a jq-compatible format.
# Outputs JSON array of {permission, source} objects.
parse_settings_file() {
  local file="$1"
  local source_name="$2"

  if [[ ! -f "$file" ]]; then
    echo "[]"
    return
  fi

  jq -r --arg src "$source_name" '
    [
      (.permissions.allow // [] | .[] | {permission: ., source: $src, type: "allow"}),
      (.permissions.deny // [] | .[] | {permission: ., source: $src, type: "deny"})
    ]
  ' "$file"
}

# ---------------------------------------------------------------------------
# Dangerous pattern detection
# ---------------------------------------------------------------------------

# Each pattern: "label|regex"
# The regex is matched against the inner command (after stripping Bash(...) wrapper).
# Order matters — first match wins.
DANGER_PATTERNS=(
  # Broad command wildcards — grants access to entire command namespace
  "broad-wildcard|^(echo|cat|find|bash|env|sort|rm|cp|mv|chmod|chown):\*$"
  # Compound operators — bypass allow-list matching
  "compound-operator|;|&&|[|][|]"
  # Redirect operators — can overwrite arbitrary files (excludes 2>&1 stderr redirect)
  "redirect| [^2][^>]*>[^&]| >>|^>"
  # Env-prefix commands — execute arbitrary commands with modified environment
  "env-prefix|^[A-Z_]+="
  # find -exec / find -delete — arbitrary command execution via find
  "find-exec|find .* -exec|find .* -delete"
  # Loop primitives — shell control flow shouldn't be in permissions
  "loop-primitive|^for |^do |^done"
  # Arbitrary execution — run arbitrary commands
  "arbitrary-exec|xargs -I|^env "
  # File mutation — destructive git operations or file overwrites
  "file-mutation|sort -o|git branch -[Dd]|git tag -d|git push.*--force|git reset --hard"
)

# Extract the inner command from a permission string.
# "Bash(git status:*)" → "git status:*"
# "Bash(rm -rf /)*" → "rm -rf /)*"  (deny entries may have trailing pattern)
strip_bash_wrapper() {
  local perm="$1"
  # Remove leading "Bash(" and trailing ")" if present
  perm="${perm#Bash(}"
  # Remove trailing ) only if it's the last char
  if [[ "$perm" == *")" ]]; then
    perm="${perm%)}"
  fi
  echo "$perm"
}

# Check if a permission matches any dangerous pattern.
# Returns the pattern label if matched, empty string if safe.
check_danger() {
  local inner="$1"

  for pattern_entry in "${DANGER_PATTERNS[@]}"; do
    local label="${pattern_entry%%|*}"
    local regex="${pattern_entry#*|}"

    if echo "$inner" | grep -qE "$regex"; then
      echo "$label"
      return 0
    fi
  done

  echo ""
  return 1
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_check() {
  local settings_file="$SETTINGS_DIR/settings.json"
  local settings_local_file="$SETTINGS_DIR/settings.local.json"

  # settings.json must exist
  if [[ ! -f "$settings_file" ]]; then
    echo "ERROR: $settings_file not found" >&2
    exit 2
  fi

  # Parse both files
  local entries_main entries_local all_entries
  entries_main=$(parse_settings_file "$settings_file" "settings.json")
  entries_local=$(parse_settings_file "$settings_local_file" "settings.local.json")

  # Merge and deduplicate: group by permission, collect sources into arrays
  all_entries=$(jq -n --argjson a "$entries_main" --argjson b "$entries_local" '
    ($a + $b) | group_by(.permission) | map({
      permission: .[0].permission,
      source: [.[].source] | unique
    })
  ')

  # Load permissions log if available
  local log_data="{}"
  local log_missing=false
  if [[ ! -f "$LOG_FILE" ]]; then
    log_missing=true
    echo "NOTE: $LOG_FILE not found — run permissions-audit.sh init" >&2
  elif ! jq empty "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: $LOG_FILE is not valid JSON" >&2
    exit 2
  else
    log_data=$(jq '.entries // {}' "$LOG_FILE")
  fi

  # Classify each entry
  local classified danger_count=0 unreviewed_count=0 reviewed_count=0
  classified="[]"

  local entry_count
  entry_count=$(echo "$all_entries" | jq 'length')

  for (( i=0; i<entry_count; i++ )); do
    local perm sources
    perm=$(echo "$all_entries" | jq -r ".[$i].permission")
    sources=$(echo "$all_entries" | jq -c ".[$i].source")

    # Skip non-Bash entries — out of scope per spec
    if [[ "$perm" != Bash\(* ]]; then
      unreviewed_count=$((unreviewed_count + 1))
      classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
        '. + [{permission: $p, source: $s, status: "UNREVIEWED"}]')
      continue
    fi

    local inner matched_pattern
    inner=$(strip_bash_wrapper "$perm")
    matched_pattern=$(check_danger "$inner" || true)

    if [[ -n "$matched_pattern" ]]; then
      # DANGER takes precedence regardless of log status
      danger_count=$((danger_count + 1))
      classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" --arg mp "$matched_pattern" \
        '. + [{permission: $p, source: $s, status: "DANGER", matched_pattern: $mp}]')
    else
      # Check log for review status
      local log_entry is_reviewed
      log_entry=$(echo "$log_data" | jq -c --arg p "$perm" '.[$p] // null')
      is_reviewed=$(echo "$log_entry" | jq '
        if . == null then false
        elif .risk == "" or .risk == "TODO" then false
        elif .rationale == "" or .rationale == "TODO" then false
        elif .efficiency_justification == "" or .efficiency_justification == "TODO" then false
        elif .reviewer == "" or .reviewer == "TODO" then false
        else true
        end
      ')

      if [[ "$is_reviewed" == "true" ]]; then
        reviewed_count=$((reviewed_count + 1))
        local risk rationale
        risk=$(echo "$log_entry" | jq -r '.risk')
        rationale=$(echo "$log_entry" | jq -r '.rationale')
        classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
          --arg risk "$risk" --arg rationale "$rationale" \
          '. + [{permission: $p, source: $s, status: "REVIEWED", risk: $risk, rationale: $rationale}]')
      else
        unreviewed_count=$((unreviewed_count + 1))
        classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
          '. + [{permission: $p, source: $s, status: "UNREVIEWED"}]')
      fi
    fi
  done

  # Output
  if [[ "$TEXT_MODE" == "true" ]]; then
    print_text_report "$classified" "$danger_count" "$unreviewed_count" "$reviewed_count"
  else
    jq -n --argjson entries "$classified" \
      --argjson d "$danger_count" --argjson u "$unreviewed_count" --argjson r "$reviewed_count" \
      '{entries: $entries, danger: $d, unreviewed: $u, reviewed: $r}'
  fi

  # Exit codes: 2 = DANGER, 1 = UNREVIEWED, 0 = all REVIEWED
  if [[ "$danger_count" -gt 0 ]]; then
    return 2
  elif [[ "$unreviewed_count" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Text output
# ---------------------------------------------------------------------------

print_text_report() {
  local entries="$1"
  local danger_count="$2"
  local unreviewed_count="$3"
  local reviewed_count="$4"

  echo "Permissions Audit"
  echo "================="
  echo ""
  echo "Summary: $danger_count DANGER, $unreviewed_count UNREVIEWED, $reviewed_count REVIEWED"
  echo ""

  # DANGER entries first
  if [[ "$danger_count" -gt 0 ]]; then
    echo "--- DANGER ---"
    echo "$entries" | jq -r '
      [.[] | select(.status == "DANGER")] | .[] |
      "  \(.permission)  [\(.matched_pattern)]  (from: \(.source | join(", ")))"
    '
    echo ""
  fi

  # UNREVIEWED entries
  if [[ "$unreviewed_count" -gt 0 ]]; then
    echo "--- UNREVIEWED ---"
    echo "$entries" | jq -r '
      [.[] | select(.status == "UNREVIEWED")] | .[] |
      "  \(.permission)  (from: \(.source | join(", ")))"
    '
    echo ""
  fi

  # REVIEWED entries (only with --verbose)
  if [[ "$VERBOSE" == "true" && "$reviewed_count" -gt 0 ]]; then
    echo "--- REVIEWED ---"
    echo "$entries" | jq -r '
      [.[] | select(.status == "REVIEWED")] | .[] |
      "  \(.permission)  [\(.risk // "?")] \(.rationale // "")  (from: \(.source | join(", ")))"
    '
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Init command
# ---------------------------------------------------------------------------

cmd_init() {
  local settings_file="$SETTINGS_DIR/settings.json"
  local settings_local_file="$SETTINGS_DIR/settings.local.json"

  # settings.json must exist
  if [[ ! -f "$settings_file" ]]; then
    echo "ERROR: $settings_file not found" >&2
    exit 2
  fi

  # Parse both files to get all permission strings
  local entries_main entries_local all_perms
  entries_main=$(parse_settings_file "$settings_file" "settings.json")
  entries_local=$(parse_settings_file "$settings_local_file" "settings.local.json")

  # Get unique permission strings
  all_perms=$(jq -n --argjson a "$entries_main" --argjson b "$entries_local" '
    ($a + $b) | [.[].permission] | unique
  ')

  # Load existing log or start fresh
  local existing="{}"
  if [[ -f "$LOG_FILE" ]]; then
    if ! jq empty "$LOG_FILE" 2>/dev/null; then
      echo "ERROR: $LOG_FILE is not valid JSON" >&2
      exit 2
    fi
    existing=$(jq '.entries // {}' "$LOG_FILE")
  fi

  # Merge: keep existing reviewed entries, add stubs for new ones
  local stub='{"risk":"","rationale":"TODO","efficiency_justification":"","reviewer":"","reviewed_epoch":0}'
  local merged
  merged=$(jq -n --argjson perms "$all_perms" --argjson existing "$existing" --argjson stub "$stub" '
    reduce $perms[] as $p (
      {};
      . + {($p): ($existing[$p] // $stub)}
    )
  ')

  # Write the log file
  jq -n --argjson entries "$merged" '{entries: $entries}' > "$LOG_FILE"

  local total
  total=$(echo "$all_perms" | jq 'length')
  local existing_count
  existing_count=$(echo "$existing" | jq 'length')
  local new_count=$((total - existing_count))
  if [[ "$new_count" -lt 0 ]]; then
    new_count=0
  fi

  echo "Initialized $LOG_FILE: $total entries ($new_count new stubs, rest preserved)"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$CMD" in
  check) cmd_check ;;
  init)  cmd_init ;;
  *)     usage ;;
esac
