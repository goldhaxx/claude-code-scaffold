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
# cmd_check_existence — Check which manifest paths exist on disk, find untracked files.
#
# Input: path to README
# Output: JSON with { found: [...], missing_from_disk: [...], missing_from_manifest: [...] }
# ---------------------------------------------------------------------------
cmd_check_existence() {
  local readme="${1:?Usage: manifest-check.sh check-existence <readme>}"

  # Parse manifest entries
  local entries
  entries="$(cmd_parse "$readme")"

  local found="[]"
  local missing_from_disk="[]"
  local manifest_paths=()

  # Check each manifest path against disk
  while IFS= read -r path; do
    manifest_paths+=("$path")
    if [[ -e "$path" ]]; then
      found="$(echo "$found" | jq --arg p "$path" '. + [{path: $p}]')"
    else
      local desc
      desc="$(echo "$entries" | jq -r --arg p "$path" '.[] | select(.path == $p) | .description')"
      missing_from_disk="$(echo "$missing_from_disk" | jq --arg p "$path" --arg d "$desc" '. + [{path: $p, description: $d}]')"
    fi
  done < <(echo "$entries" | jq -r '.[].path')

  # Discover untracked files in tracked directories
  local missing_from_manifest="[]"

  for dir in "${TRACKED_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue

    # List files in the tracked directory
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue

      # Check if this file is in the manifest
      local in_manifest=false
      for mp in "${manifest_paths[@]}"; do
        if [[ "$mp" == "$file" ]]; then
          in_manifest=true
          break
        fi
      done

      if [[ "$in_manifest" == false ]]; then
        missing_from_manifest="$(echo "$missing_from_manifest" | jq --arg p "$file" '. + [{path: $p}]')"
      fi
    done < <(find "$dir" -maxdepth 2 -type f | sort)
  done

  # Build output
  jq -n \
    --argjson found "$found" \
    --argjson missing_disk "$missing_from_disk" \
    --argjson missing_manifest "$missing_from_manifest" \
    '{found: $found, missing_from_disk: $missing_disk, missing_from_manifest: $missing_manifest}'
}

# ---------------------------------------------------------------------------
# file_hash — Compute sha256 of a file.
# ---------------------------------------------------------------------------
file_hash() {
  shasum -a 256 "$1" | cut -d' ' -f1
}

# ---------------------------------------------------------------------------
# cmd_init — Create .claude/manifest.lock from current README + file hashes.
#
# Input: path to README
# Output: writes LOCKFILE
# ---------------------------------------------------------------------------
cmd_init() {
  local readme="${1:?Usage: manifest-check.sh init <readme>}"

  local entries
  entries="$(cmd_parse "$readme")"

  local commit
  commit="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
  local now
  now="$(date +%s)"

  local lock_entries="{}"

  while IFS= read -r path; do
    [[ -f "$path" ]] || continue

    local hash
    hash="$(file_hash "$path")"

    lock_entries="$(echo "$lock_entries" | jq \
      --arg p "$path" \
      --arg h "$hash" \
      --arg c "$commit" \
      --argjson d "$now" \
      '. + {($p): {file_hash: $h, verified_at_commit: $c, verified: $d}}')"
  done < <(echo "$entries" | jq -r '.[].path')

  mkdir -p "$(dirname "$LOCKFILE")"

  jq -n \
    --argjson date "$now" \
    --arg commit "$commit" \
    --argjson entries "$lock_entries" \
    '{meta: {last_verified: $date, commit: $commit}, entries: $entries}' \
    > "$LOCKFILE"

  echo "Created $LOCKFILE with $(echo "$lock_entries" | jq 'length') entries."
}

# ---------------------------------------------------------------------------
# cmd_hash_check — Compare current file hashes against lockfile.
#
# Output: JSON { verified: [...], stale: [...] }
# ---------------------------------------------------------------------------
cmd_hash_check() {
  if [[ ! -f "$LOCKFILE" ]]; then
    echo "Error: $LOCKFILE not found. Run 'manifest-check.sh init <readme>' first." >&2
    return 1
  fi

  local verified="[]"
  local stale="[]"

  while IFS= read -r path; do
    [[ -f "$path" ]] || continue

    local stored_hash current_hash
    stored_hash="$(jq -r --arg p "$path" '.entries[$p].file_hash' "$LOCKFILE")"
    current_hash="$(file_hash "$path")"

    if [[ "$stored_hash" == "$current_hash" ]]; then
      verified="$(echo "$verified" | jq --arg p "$path" '. + [{path: $p, status: "unchanged"}]')"
    else
      # Generate diff for stale entry
      local diff_text=""
      local verified_commit
      verified_commit="$(jq -r --arg p "$path" '.entries[$p].verified_at_commit' "$LOCKFILE")"

      if [[ "$verified_commit" != "null" ]] && [[ "$verified_commit" != "unknown" ]] && \
         git cat-file -t "$verified_commit" &>/dev/null; then
        # Try git diff from the verified commit
        diff_text="$(git diff "$verified_commit" -- "$path" 2>/dev/null || true)"
      fi

      # Fallback: diff against HEAD if git diff failed or was empty
      if [[ -z "$diff_text" ]]; then
        diff_text="$(git diff HEAD -- "$path" 2>/dev/null || true)"
      fi

      # Last fallback: note that diff is unavailable
      if [[ -z "$diff_text" ]]; then
        diff_text="[hash changed, diff unavailable]"
      fi

      local json_diff
      json_diff="$(printf '%s' "$diff_text" | jq -Rs '.')"
      stale="$(echo "$stale" | jq --arg p "$path" --argjson d "$json_diff" '. + [{path: $p, diff: $d}]')"
    fi
  done < <(jq -r '.entries | keys[]' "$LOCKFILE")

  jq -n \
    --argjson verified "$verified" \
    --argjson stale "$stale" \
    '{verified: $verified, stale: $stale}'
}

# ---------------------------------------------------------------------------
# cmd_extract_identity — Extract identity metadata from a file.
#
# Shell scripts: leading comment block (lines starting with #)
# Markdown: YAML frontmatter + first heading
# Other: first 3 lines
#
# Output: JSON { path, type, identity, size_bytes }
# ---------------------------------------------------------------------------
cmd_extract_identity() {
  local filepath="${1:?Usage: manifest-check.sh extract-identity <file>}"

  if [[ ! -f "$filepath" ]]; then
    echo "Error: File does not exist: $filepath" >&2
    return 1
  fi

  local size_bytes type identity

  # File size (portable: wc -c)
  size_bytes="$(wc -c < "$filepath" | tr -d ' ')"

  case "$filepath" in
    *.sh)
      type="shell"
      # Extract leading comment block (shebang + # lines)
      identity=""
      while IFS= read -r line; do
        if [[ "$line" =~ ^#.* ]] || [[ "$line" =~ ^$ && -z "$identity" ]]; then
          identity+="$line"$'\n'
        else
          break
        fi
      done < "$filepath"
      # Trim trailing newlines
      identity="$(printf '%s' "$identity")"
      ;;
    *.md)
      type="markdown"
      identity=""
      local in_frontmatter=false
      local frontmatter_done=false
      local found_heading=false
      while IFS= read -r line; do
        # YAML frontmatter
        if [[ "$line" == "---" ]] && [[ "$frontmatter_done" == false ]]; then
          if [[ "$in_frontmatter" == false ]]; then
            in_frontmatter=true
            continue
          else
            in_frontmatter=false
            frontmatter_done=true
            continue
          fi
        fi
        if [[ "$in_frontmatter" == true ]]; then
          identity+="$line"$'\n'
          continue
        fi
        # First heading
        if [[ "$line" =~ ^#\  ]] && [[ "$found_heading" == false ]]; then
          identity+="$line"$'\n'
          found_heading=true
          break
        fi
      done < "$filepath"
      identity="$(printf '%s' "$identity")"
      ;;
    *)
      type="other"
      identity="$(head -3 "$filepath")"
      ;;
  esac

  local json_identity
  json_identity="$(printf '%s' "$identity" | jq -Rs '.')"

  jq -n \
    --arg p "$filepath" \
    --arg t "$type" \
    --argjson i "$json_identity" \
    --argjson s "$size_bytes" \
    '{path: $p, type: $t, identity: $i, size_bytes: $s}'
}

# ---------------------------------------------------------------------------
# cmd_check — Full manifest verification report.
#
# Combines parse, check-existence, hash-check, and extract-identity into
# one JSON report with: verified, stale, missing_from_disk,
# missing_from_manifest, summary.
#
# Input: path to README
# Output: JSON report
# ---------------------------------------------------------------------------
cmd_check() {
  local readme="${1:?Usage: manifest-check.sh check <readme>}"

  local entries
  entries="$(cmd_parse "$readme")"

  local verified="[]"
  local stale="[]"
  local missing_from_disk="[]"
  local missing_from_manifest="[]"
  local manifest_paths=()
  local has_lockfile=false

  [[ -f "$LOCKFILE" ]] && has_lockfile=true

  # Check each manifest entry
  while IFS= read -r path; do
    manifest_paths+=("$path")

    if [[ ! -e "$path" ]]; then
      local desc
      desc="$(echo "$entries" | jq -r --arg p "$path" '.[] | select(.path == $p) | .description')"
      missing_from_disk="$(echo "$missing_from_disk" | jq --arg p "$path" --arg d "$desc" '. + [{path: $p, description: $d}]')"
      continue
    fi

    if [[ "$has_lockfile" == true ]]; then
      local stored_hash
      stored_hash="$(jq -r --arg p "$path" '.entries[$p].file_hash // empty' "$LOCKFILE")"

      if [[ -n "$stored_hash" ]]; then
        local current_hash
        current_hash="$(file_hash "$path")"

        if [[ "$stored_hash" == "$current_hash" ]]; then
          verified="$(echo "$verified" | jq --arg p "$path" '. + [{path: $p, status: "unchanged"}]')"
        else
          # Generate diff
          local diff_text=""
          local verified_commit
          verified_commit="$(jq -r --arg p "$path" '.entries[$p].verified_at_commit' "$LOCKFILE")"

          if [[ "$verified_commit" != "null" ]] && [[ "$verified_commit" != "unknown" ]] && \
             git cat-file -t "$verified_commit" &>/dev/null; then
            diff_text="$(git diff "$verified_commit" -- "$path" 2>/dev/null || true)"
          fi
          if [[ -z "$diff_text" ]]; then
            diff_text="$(git diff HEAD -- "$path" 2>/dev/null || true)"
          fi
          if [[ -z "$diff_text" ]]; then
            diff_text="[hash changed, diff unavailable]"
          fi

          local desc
          desc="$(echo "$entries" | jq -r --arg p "$path" '.[] | select(.path == $p) | .description')"
          local json_diff
          json_diff="$(printf '%s' "$diff_text" | jq -Rs '.')"
          stale="$(echo "$stale" | jq --arg p "$path" --arg d "$desc" --argjson df "$json_diff" \
            '. + [{path: $p, description: $d, diff: $df}]')"
        fi
      else
        # In manifest but not in lockfile — treat as unverified (stale)
        local desc
        desc="$(echo "$entries" | jq -r --arg p "$path" '.[] | select(.path == $p) | .description')"
        stale="$(echo "$stale" | jq --arg p "$path" --arg d "$desc" '. + [{path: $p, description: $d, diff: "[no lockfile entry]"}]')"
      fi
    else
      # No lockfile — all entries are unverified
      local desc
      desc="$(echo "$entries" | jq -r --arg p "$path" '.[] | select(.path == $p) | .description')"
      stale="$(echo "$stale" | jq --arg p "$path" --arg d "$desc" '. + [{path: $p, description: $d, diff: "[no lockfile]"}]')"
    fi
  done < <(echo "$entries" | jq -r '.[].path')

  # Discover untracked files in tracked directories
  for dir in "${TRACKED_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      local in_manifest=false
      for mp in "${manifest_paths[@]}"; do
        if [[ "$mp" == "$file" ]]; then
          in_manifest=true
          break
        fi
      done
      if [[ "$in_manifest" == false ]]; then
        local id_json
        id_json="$(cmd_extract_identity "$file")"
        local identity size_bytes
        identity="$(echo "$id_json" | jq -r '.identity')"
        size_bytes="$(echo "$id_json" | jq '.size_bytes')"
        local json_id
        json_id="$(printf '%s' "$identity" | jq -Rs '.')"
        missing_from_manifest="$(echo "$missing_from_manifest" | jq \
          --arg p "$file" --argjson i "$json_id" --argjson s "$size_bytes" \
          '. + [{path: $p, identity: $i, size_bytes: $s}]')"
      fi
    done < <(find "$dir" -maxdepth 2 -type f | sort)
  done

  # Build summary
  local total verified_count stale_count missing_disk_count missing_manifest_count
  verified_count="$(echo "$verified" | jq 'length')"
  stale_count="$(echo "$stale" | jq 'length')"
  missing_disk_count="$(echo "$missing_from_disk" | jq 'length')"
  missing_manifest_count="$(echo "$missing_from_manifest" | jq 'length')"
  total=$((verified_count + stale_count + missing_disk_count + missing_manifest_count))

  jq -n \
    --argjson verified "$verified" \
    --argjson stale "$stale" \
    --argjson missing_disk "$missing_from_disk" \
    --argjson missing_manifest "$missing_from_manifest" \
    --argjson total "$total" \
    --argjson vc "$verified_count" \
    --argjson sc "$stale_count" \
    --argjson mdc "$missing_disk_count" \
    --argjson mmc "$missing_manifest_count" \
    '{
      verified: $verified,
      stale: $stale,
      missing_from_disk: $missing_disk,
      missing_from_manifest: $missing_manifest,
      summary: {total: $total, verified: $vc, stale: $sc, missing_from_disk: $mdc, missing_from_manifest: $mmc}
    }'
}

# ---------------------------------------------------------------------------
# cmd_verify — Update lockfile entries for verified paths.
#
# Input: one or more file paths
# Output: updates LOCKFILE
# ---------------------------------------------------------------------------
cmd_verify() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: manifest-check.sh verify <path> [<path>...]" >&2
    return 1
  fi

  if [[ ! -f "$LOCKFILE" ]]; then
    echo "Error: $LOCKFILE not found. Run 'manifest-check.sh init <readme>' first." >&2
    return 1
  fi

  local commit
  commit="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
  local now
  now="$(date +%s)"

  for path in "$@"; do
    if [[ ! -f "$path" ]]; then
      echo "Warning: $path does not exist, skipping." >&2
      continue
    fi

    local hash
    hash="$(file_hash "$path")"

    # Update the lockfile entry
    local tmp
    tmp="$(jq \
      --arg p "$path" \
      --arg h "$hash" \
      --arg c "$commit" \
      --argjson d "$now" \
      '.entries[$p] = {file_hash: $h, verified_at_commit: $c, verified: $d} | .meta.last_verified = $d | .meta.commit = $c' \
      "$LOCKFILE")"
    echo "$tmp" > "$LOCKFILE"

    echo "Verified: $path"
  done
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  parse)
    shift
    cmd_parse "$@"
    ;;
  check-existence)
    shift
    cmd_check_existence "$@"
    ;;
  init)
    shift
    cmd_init "$@"
    ;;
  hash-check)
    shift
    cmd_hash_check "$@"
    ;;
  extract-identity)
    shift
    cmd_extract_identity "$@"
    ;;
  check)
    shift
    cmd_check "$@"
    ;;
  verify)
    shift
    cmd_verify "$@"
    ;;
  *)
    echo "Usage: manifest-check.sh {parse|check-existence|init|hash-check|extract-identity|check|verify} [args...]" >&2
    exit 1
    ;;
esac
