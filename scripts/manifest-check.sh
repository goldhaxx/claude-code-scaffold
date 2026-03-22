#!/usr/bin/env bash
# manifest-check.sh — Deterministic README manifest verification.
#
# Usage:
#   manifest-check.sh parse <readme>          Parse manifest tables → JSON [{path, description}]
#   manifest-check.sh check                   Compare manifest against disk + lockfile → JSON report
#   manifest-check.sh init                    Create .claude/manifest.lock from current state
#   manifest-check.sh verify <paths...>       Update lockfile entries for verified paths

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

LOCKFILE=".claude/manifest.lock"

# Tracked directories — files here should appear in the README manifest.
TRACKED_DIRS=(
  ".claude/rules"
  ".claude/commands"
  ".claude/agents"
  ".claude/skills"
  ".claude/hooks"
  "scripts"
  "docs/templates"
)

# ---------------------------------------------------------------------------
# cmd_parse — Extract (path, description) pairs from README markdown tables.
#
# Parses all tables in the file. For each data row (not header/separator):
#   - Column 1 → path (backticks stripped)
#   - Last meaningful column with a sentence → description
#
# For 4-column tables: | path | copy-to | description | customize |
# For 3-column tables: | path | meta | description |
#
# Output: JSON array of {path, description} objects.
# ---------------------------------------------------------------------------
cmd_parse() {
  local readme="${1:?Usage: manifest-check.sh parse <readme>}"

  if [[ ! -f "$readme" ]]; then
    echo "Error: File does not exist: $readme" >&2
    return 1
  fi

  local entries="[]"

  while IFS= read -r line; do
    # Skip non-table lines
    [[ "$line" =~ ^\| ]] || continue

    # Skip separator rows (|---|---|...)
    [[ "$line" =~ ^\|[\ \-:|]+\|$ ]] && continue

    # Split on | and trim
    # Remove leading/trailing pipes, then split
    local stripped="${line#|}"
    stripped="${stripped%|}"

    # Split into array by |
    IFS='|' read -ra cols <<< "$stripped"

    # Need at least 3 columns
    [[ ${#cols[@]} -ge 3 ]] || continue

    # Column 1: path — strip whitespace and backticks
    local path="${cols[0]}"
    path="$(echo "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/`//g')"

    # Skip header rows: if col1 looks like a header (contains "File" or "Command")
    if [[ "$path" == *"File"* ]] || [[ "$path" == *"Command"* ]]; then
      continue
    fi

    # Skip empty paths
    [[ -n "$path" ]] || continue

    # Description: column 3 (index 2) for both 3-col and 4-col tables
    local desc="${cols[2]}"
    desc="$(echo "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # For descriptions that are multi-sentence, take the first sentence
    # to keep it manageable. Strip markdown bold markers.
    desc="$(echo "$desc" | sed 's/\*\*//g')"

    # Build JSON entry
    local json_path json_desc
    json_path="$(printf '%s' "$path" | jq -Rs '.')"
    json_desc="$(printf '%s' "$desc" | jq -Rs '.')"

    entries="$(echo "$entries" | jq --argjson p "$json_path" --argjson d "$json_desc" '. + [{path: $p, description: $d}]')"

  done < "$readme"

  echo "$entries" | jq '.'
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  parse)
    shift
    cmd_parse "$@"
    ;;
  *)
    echo "Usage: manifest-check.sh {parse|check|init|verify} [args...]" >&2
    exit 1
    ;;
esac
