#!/usr/bin/env bash
# scaffold-sync.sh — Bi-directional sync between a project and the scaffold hub.
#
# Usage:
#   scaffold-sync.sh init [scaffold-path]   Generate lockfile from current state
#   scaffold-sync.sh status                 Show file provenance and sync state
#   scaffold-sync.sh diff [file]            Show diff between local and scaffold versions
#   scaffold-sync.sh hash <file>            Compute sha256 of a file
#   scaffold-sync.sh lock-get <file>        Read a lockfile entry (JSON)
#   scaffold-sync.sh lock-update <file> <field> <value>  Update a lockfile field
#   scaffold-sync.sh log <message>          Append to project sync log
#   scaffold-sync.sh changelog <message>    Append to scaffold changelog
#   scaffold-sync.sh section-merge <s> <l>  Merge hub/node sections of a delimited file
#   scaffold-sync.sh scan                   List all trackable files in the project

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
LOCKFILE=".claude/scaffold.lock"
SYNC_LOG=".claude/scaffold-sync.log"

# Directories and patterns to track (relative to project root)
TRACKED_PATTERNS=(
  ".claude/rules/*.md"
  ".claude/commands/*.md"
  ".claude/agents/*.md"
  ".claude/skills/*/SKILL.md"
  ".claude/settings.json"
  "docs/templates/*.md"
  "scripts/*.sh"
  "GUIDE.md"
  "CLAUDE.md"
  "SCAFFOLD_FRAMEWORK.md"
)

# Files to never track
EXCLUDED_FILES=(
  ".claude/scaffold.lock"
  ".claude/scaffold-sync.log"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed. Run: brew install jq"
}

require_lockfile() {
  [[ -f "$LOCKFILE" ]] || die "No $LOCKFILE found. Run: scaffold-sync.sh init"
}

get_scaffold_source() {
  jq -r '.scaffold_source' "$LOCKFILE" | sed "s|^~|$HOME|"
}

file_hash() {
  # Returns just the hex digest
  local file="$1"
  if [[ -f "$file" ]]; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "MISSING"
  fi
}

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

datestamp() {
  date +"%Y-%m-%d %H:%M"
}

get_sync_field() {
  # Returns the sync field for a file, defaulting to "tracked" for backward compat
  local file="$1"
  local val
  val=$(jq -r --arg f "$file" '.files[$f].sync // "tracked"' "$LOCKFILE")
  echo "$val"
}

is_node_only() {
  # Returns 0 (true) if file is marked node-only, 1 (false) otherwise
  local file="$1"
  [[ "$(get_sync_field "$file")" == "node-only" ]]
}

is_excluded() {
  local file="$1"
  for excluded in "${EXCLUDED_FILES[@]}"; do
    [[ "$file" == "$excluded" ]] && return 0
  done
  return 1
}

# Scan project for all files matching tracked patterns
scan_tracked_files() {
  local files=()
  for pattern in "${TRACKED_PATTERNS[@]}"; do
    # Use bash glob expansion (nullglob handles no-match)
    local matches
    matches=( $pattern ) 2>/dev/null || true
    for f in "${matches[@]}"; do
      [[ -f "$f" ]] && ! is_excluded "$f" && files+=("$f")
    done
  done
  # Deduplicate and sort
  printf '%s\n' "${files[@]}" | sort -u
}

# Scan scaffold for all files matching tracked patterns
scan_scaffold_files() {
  local scaffold_path="$1"
  local files=()
  for pattern in "${TRACKED_PATTERNS[@]}"; do
    local matches
    matches=( "$scaffold_path"/$pattern ) 2>/dev/null || true
    for f in "${matches[@]}"; do
      if [[ -f "$f" ]]; then
        # Convert to relative path (strip scaffold_path prefix)
        local rel="${f#$scaffold_path/}"
        ! is_excluded "$rel" && files+=("$rel")
      fi
    done
  done
  printf '%s\n' "${files[@]}" | sort -u
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_init() {
  local scaffold_path="${1:-$HOME/projects/claude-code-scaffold}"
  scaffold_path="${scaffold_path/#\~/$HOME}"

  [[ -d "$scaffold_path" ]] || die "Scaffold not found at: $scaffold_path"

  # Get scaffold git version
  local scaffold_version="unknown"
  if git -C "$scaffold_path" rev-parse HEAD >/dev/null 2>&1; then
    scaffold_version=$(git -C "$scaffold_path" rev-parse --short HEAD)
  fi

  # Build the files object
  local files_json="{}"

  # Find all trackable files in the project
  while IFS= read -r file; do
    local scaffold_file="$scaffold_path/$file"
    local local_h
    local_h=$(file_hash "$file")

    if [[ -f "$scaffold_file" ]]; then
      local scaffold_h
      scaffold_h=$(file_hash "$scaffold_file")

      if [[ "$local_h" == "$scaffold_h" ]]; then
        local status="clean"
      else
        local status="modified"
      fi

      files_json=$(echo "$files_json" | jq --arg f "$file" --arg sh "$scaffold_h" --arg lh "$local_h" --arg st "$status" \
        '. + {($f): {"origin": "scaffold", "scaffold_hash": $sh, "local_hash": $lh, "status": $st, "sync": "tracked"}}')
    else
      # File exists locally but not in scaffold
      files_json=$(echo "$files_json" | jq --arg f "$file" --arg lh "$local_h" \
        '. + {($f): {"origin": "local", "scaffold_hash": null, "local_hash": $lh, "status": "local-only", "sync": "tracked"}}')
    fi
  done < <(scan_tracked_files)

  # Check for files in scaffold that are NOT in the project
  while IFS= read -r file; do
    if ! echo "$files_json" | jq -e --arg f "$file" '.[$f]' >/dev/null 2>&1; then
      local scaffold_h
      scaffold_h=$(file_hash "$scaffold_path/$file")
      files_json=$(echo "$files_json" | jq --arg f "$file" --arg sh "$scaffold_h" \
        '. + {($f): {"origin": "scaffold", "scaffold_hash": $sh, "local_hash": null, "status": "scaffold-only", "sync": "tracked"}}')
    fi
  done < <(scan_scaffold_files "$scaffold_path")

  # Write lockfile
  jq -n --arg src "$scaffold_path" --arg ver "$scaffold_version" --arg ts "$(timestamp)" --argjson files "$files_json" \
    '{scaffold_source: $src, scaffold_version: $ver, synced_at: $ts, files: $files}' > "$LOCKFILE"

  local total
  total=$(echo "$files_json" | jq 'length')
  local clean modified local_only scaffold_only
  clean=$(echo "$files_json" | jq '[.[] | select(.status == "clean")] | length')
  modified=$(echo "$files_json" | jq '[.[] | select(.status == "modified")] | length')
  local_only=$(echo "$files_json" | jq '[.[] | select(.status == "local-only")] | length')
  scaffold_only=$(echo "$files_json" | jq '[.[] | select(.status == "scaffold-only")] | length')

  echo "Scaffold lockfile generated: $LOCKFILE"
  echo "  Scaffold: $scaffold_path @ $scaffold_version"
  echo "  Total files: $total"
  echo "  Clean: $clean | Modified: $modified | Local: $local_only | Scaffold-only: $scaffold_only"
}

cmd_status() {
  require_lockfile

  local scaffold_source
  scaffold_source=$(get_scaffold_source)
  local scaffold_version
  scaffold_version=$(jq -r '.scaffold_version' "$LOCKFILE")
  local synced_at
  synced_at=$(jq -r '.synced_at' "$LOCKFILE")

  echo "Scaffold: $scaffold_source @ $scaffold_version"
  echo "Last synced: $synced_at"
  echo ""

  # Check if scaffold has new commits since last sync
  if git -C "$scaffold_source" rev-parse HEAD >/dev/null 2>&1; then
    local current_scaffold_version
    current_scaffold_version=$(git -C "$scaffold_source" rev-parse --short HEAD)
    if [[ "$current_scaffold_version" != "$scaffold_version" ]]; then
      echo "NOTE: Scaffold has new commits ($scaffold_version → $current_scaffold_version)"
      echo ""
    fi
  fi

  # Print each file's status
  local has_output=false
  while IFS= read -r file; do
    local status origin scaffold_hash local_hash
    status=$(jq -r --arg f "$file" '.files[$f].status' "$LOCKFILE")
    origin=$(jq -r --arg f "$file" '.files[$f].origin' "$LOCKFILE")

    # Check if local file has changed since lockfile was written
    local current_hash=""
    if [[ -f "$file" ]]; then
      current_hash=$(file_hash "$file")
    fi
    local recorded_local_hash
    recorded_local_hash=$(jq -r --arg f "$file" '.files[$f].local_hash // "null"' "$LOCKFILE")

    # Check node-only classification
    local sync_field
    sync_field=$(get_sync_field "$file")

    local display_status
    if [[ "$sync_field" == "node-only" ]]; then
      display_status="NODE-ONLY"
    else
      case "$status" in
        clean)
          if [[ -n "$current_hash" && "$current_hash" != "$recorded_local_hash" ]]; then
            display_status="MODIFIED*"  # Changed since last sync
          else
            display_status="CLEAN"
          fi
          ;;
        modified)     display_status="MODIFIED" ;;
        local-only)   display_status="LOCAL" ;;
        promoted)     display_status="PROMOTED" ;;
        scaffold-only) display_status="SCAFFOLD-ONLY" ;;
        *)            display_status="UNKNOWN" ;;
      esac
    fi

    printf "  %-16s %s\n" "$display_status" "$file"
    has_output=true
  done < <(jq -r '.files | keys[]' "$LOCKFILE" | sort)

  if [[ "$has_output" == "false" ]]; then
    echo "  No tracked files."
  fi

  echo ""
  echo "Statuses: CLEAN=synced, MODIFIED=locally changed, MODIFIED*=changed since last sync,"
  echo "          LOCAL=project-only, PROMOTED=pushed to scaffold, SCAFFOLD-ONLY=not yet pulled,"
  echo "          NODE-ONLY=excluded from sync (use /scaffold-ignore to set, scaffold-sync.sh track to undo)"
}

cmd_diff() {
  require_lockfile
  local file="${1:-}"
  local scaffold_source
  scaffold_source=$(get_scaffold_source)

  if [[ -n "$file" ]]; then
    # Diff a specific file
    local scaffold_file="$scaffold_source/$file"
    if [[ ! -f "$scaffold_file" ]]; then
      echo "File not in scaffold: $file"
      [[ -f "$file" ]] && echo "(exists locally as local-only file)"
      return 0
    fi
    if [[ ! -f "$file" ]]; then
      echo "File not in project: $file"
      echo "(exists in scaffold — run scaffold-pull to add it)"
      return 0
    fi
    echo "--- scaffold: $file"
    echo "+++ local: $file"
    diff --unified "$scaffold_source/$file" "$file" || true
  else
    # Diff all modified files
    while IFS= read -r f; do
      local status
      status=$(jq -r --arg f "$f" '.files[$f].status' "$LOCKFILE")
      if [[ "$status" == "modified" || "$status" == "clean" ]]; then
        local current_hash
        current_hash=$(file_hash "$f")
        local scaffold_hash
        scaffold_hash=$(jq -r --arg f "$f" '.files[$f].scaffold_hash // "null"' "$LOCKFILE")
        if [[ "$current_hash" != "$scaffold_hash" && -f "$scaffold_source/$f" ]]; then
          echo "=== $f ==="
          diff --unified "$scaffold_source/$f" "$f" || true
          echo ""
        fi
      fi
    done < <(jq -r '.files | keys[]' "$LOCKFILE")
  fi
}

cmd_hash() {
  local file="${1:?Usage: scaffold-sync.sh hash <file>}"
  echo "$(file_hash "$file")  $file"
}

cmd_lock_get() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh lock-get <file>}"
  jq --arg f "$file" '.files[$f] // "not found"' "$LOCKFILE"
}

cmd_lock_update() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh lock-update <file> <field> <value>}"
  local field="${2:?}"
  local value="${3:?}"

  local tmp
  tmp=$(mktemp)
  if [[ "$value" == "null" ]]; then
    jq --arg f "$file" --arg k "$field" '.files[$f][$k] = null' "$LOCKFILE" > "$tmp"
  else
    jq --arg f "$file" --arg k "$field" --arg v "$value" '.files[$f][$k] = $v' "$LOCKFILE" > "$tmp"
  fi
  mv "$tmp" "$LOCKFILE"
}

cmd_lock_add() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh lock-add <file> <origin> <scaffold_hash> <local_hash> <status>}"
  local origin="${2:?}"
  local scaffold_hash="${3}"
  local local_hash="${4}"
  local status="${5:?}"

  local tmp
  tmp=$(mktemp)
  if [[ "$scaffold_hash" == "null" ]]; then
    jq --arg f "$file" --arg o "$origin" --arg lh "$local_hash" --arg st "$status" \
      '.files[$f] = {"origin": $o, "scaffold_hash": null, "local_hash": $lh, "status": $st}' "$LOCKFILE" > "$tmp"
  elif [[ "$local_hash" == "null" ]]; then
    jq --arg f "$file" --arg o "$origin" --arg sh "$scaffold_hash" --arg st "$status" \
      '.files[$f] = {"origin": $o, "scaffold_hash": $sh, "local_hash": null, "status": $st}' "$LOCKFILE" > "$tmp"
  else
    jq --arg f "$file" --arg o "$origin" --arg sh "$scaffold_hash" --arg lh "$local_hash" --arg st "$status" \
      '.files[$f] = {"origin": $o, "scaffold_hash": $sh, "local_hash": $lh, "status": $st}' "$LOCKFILE" > "$tmp"
  fi
  mv "$tmp" "$LOCKFILE"
}

cmd_lock_remove() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh lock-remove <file>}"

  local tmp
  tmp=$(mktemp)
  jq --arg f "$file" 'del(.files[$f])' "$LOCKFILE" > "$tmp"
  mv "$tmp" "$LOCKFILE"
}

cmd_lock_set_version() {
  require_lockfile
  local version="${1:?Usage: scaffold-sync.sh lock-set-version <version>}"

  local tmp
  tmp=$(mktemp)
  jq --arg v "$version" --arg ts "$(timestamp)" '.scaffold_version = $v | .synced_at = $ts' "$LOCKFILE" > "$tmp"
  mv "$tmp" "$LOCKFILE"
}

cmd_log() {
  local message="${1:?Usage: scaffold-sync.sh log <message>}"

  # Prepend entry to sync log (newest first)
  local entry
  entry="## $(datestamp) — $message"

  if [[ -f "$SYNC_LOG" ]]; then
    local tmp
    tmp=$(mktemp)
    echo "$entry" > "$tmp"
    echo "" >> "$tmp"
    cat "$SYNC_LOG" >> "$tmp"
    mv "$tmp" "$SYNC_LOG"
  else
    echo "$entry" > "$SYNC_LOG"
    echo "" >> "$SYNC_LOG"
  fi
}

cmd_log_detail() {
  # Append a detail line to the most recent log entry
  local detail="${1:?Usage: scaffold-sync.sh log-detail <detail>}"

  if [[ -f "$SYNC_LOG" ]]; then
    # Insert detail after the first line (the header)
    local tmp
    tmp=$(mktemp)
    local header_done=false
    local inserted=false
    while IFS= read -r line; do
      echo "$line" >> "$tmp"
      if [[ "$header_done" == "false" && "$line" == "## "* ]]; then
        header_done=true
      elif [[ "$header_done" == "true" && "$inserted" == "false" ]]; then
        # Insert before first empty line after header
        if [[ -z "$line" ]]; then
          echo "- $detail" >> "$tmp"
          inserted=true
        fi
      fi
    done < "$SYNC_LOG"
    # If we never found an empty line, append
    if [[ "$inserted" == "false" ]]; then
      echo "- $detail" >> "$tmp"
    fi
    mv "$tmp" "$SYNC_LOG"
  fi
}

cmd_changelog() {
  require_lockfile
  local message="${1:?Usage: scaffold-sync.sh changelog <message>}"

  local scaffold_source
  scaffold_source=$(get_scaffold_source)
  local changelog="$scaffold_source/SCAFFOLD_CHANGELOG.md"

  if [[ ! -f "$changelog" ]]; then
    echo "# Scaffold Changelog" > "$changelog"
    echo "" >> "$changelog"
    echo "All CRUD operations on the scaffold are logged here, newest first." >> "$changelog"
    echo "" >> "$changelog"
  fi

  # Insert new entry after the header (after "newest first." line)
  local entry="## $(datestamp) — $message"
  local tmp
  tmp=$(mktemp)
  local inserted=false
  while IFS= read -r line; do
    echo "$line" >> "$tmp"
    if [[ "$inserted" == "false" && "$line" == "" ]]; then
      # Check if previous content suggests we're past the header
      if grep -q "newest first" "$changelog" 2>/dev/null; then
        echo "$entry" >> "$tmp"
        echo "" >> "$tmp"
        inserted=true
      fi
    fi
  done < "$changelog"
  if [[ "$inserted" == "false" ]]; then
    echo "" >> "$tmp"
    echo "$entry" >> "$tmp"
    echo "" >> "$tmp"
  fi
  mv "$tmp" "$changelog"
}

cmd_changelog_detail() {
  require_lockfile
  local detail="${1:?Usage: scaffold-sync.sh changelog-detail <detail>}"

  local scaffold_source
  scaffold_source=$(get_scaffold_source)
  local changelog="$scaffold_source/SCAFFOLD_CHANGELOG.md"

  [[ -f "$changelog" ]] || die "Changelog not found at: $changelog"

  # Find the most recent entry and append detail
  local tmp
  tmp=$(mktemp)
  local found_entry=false
  local inserted=false
  while IFS= read -r line; do
    if [[ "$found_entry" == "false" && "$line" == "## "* ]]; then
      found_entry=true
      echo "$line" >> "$tmp"
      continue
    fi
    if [[ "$found_entry" == "true" && "$inserted" == "false" && -z "$line" ]]; then
      echo "- $detail" >> "$tmp"
      echo "" >> "$tmp"
      inserted=true
      continue
    fi
    echo "$line" >> "$tmp"
  done < "$changelog"
  if [[ "$found_entry" == "true" && "$inserted" == "false" ]]; then
    echo "- $detail" >> "$tmp"
  fi
  mv "$tmp" "$changelog"
}

cmd_section_merge() {
  local scaffold_file="${1:?Usage: scaffold-sync.sh section-merge <scaffold-file> <local-file>}"
  local local_file="${2:?Usage: scaffold-sync.sh section-merge <scaffold-file> <local-file>}"

  [[ -f "$scaffold_file" ]] || die "Scaffold file not found: $scaffold_file"
  [[ -f "$local_file" ]] || die "Local file not found: $local_file"

  # Detect which delimiter the scaffold file uses
  local delimiter=""
  if grep -q '<!-- NODE-SPECIFIC-START -->' "$scaffold_file"; then
    delimiter="<!-- NODE-SPECIFIC-START -->"
  elif grep -q '<!-- HUB-MANAGED-START -->' "$scaffold_file"; then
    delimiter="<!-- HUB-MANAGED-START -->"
  else
    # No delimiter in scaffold file — not a section-merge file
    echo "ERROR: No section delimiter found in scaffold file" >&2
    return 1
  fi

  if [[ "$delimiter" == "<!-- NODE-SPECIFIC-START -->" ]]; then
    # Pattern: hub content above delimiter, node content below
    # Take ABOVE delimiter from scaffold, BELOW delimiter from local

    # Get hub content (everything before delimiter) from scaffold
    sed -n "/$delimiter/q;p" "$scaffold_file"

    # Get node content (delimiter + everything after) from local
    if grep -q "$delimiter" "$local_file"; then
      sed -n "/$delimiter/,\$p" "$local_file"
    else
      # Local has no delimiter — treat entire local file as node content
      echo "$delimiter"
      echo "<!-- Everything above is managed by the scaffold hub and updated via /scaffold-pull. -->"
      echo "<!-- Everything below is specific to this project. -->"
      echo ""
      echo "## Project-Specific Features"
      echo ""
      echo "_Migrated from pre-delimiter version:_"
      echo ""
      cat "$local_file"
    fi

  elif [[ "$delimiter" == "<!-- HUB-MANAGED-START -->" ]]; then
    # Pattern: node content above delimiter, hub content below
    # Take ABOVE delimiter from local, BELOW delimiter from scaffold

    # Get node content (everything before delimiter) from local
    if grep -q "$delimiter" "$local_file"; then
      sed -n "/$delimiter/q;p" "$local_file"
    else
      # Local has no delimiter — treat entire local file as node content
      cat "$local_file"
      echo ""
    fi

    # Get hub content (delimiter + everything after) from scaffold
    sed -n "/$delimiter/,\$p" "$scaffold_file"
  fi
}

# ---------------------------------------------------------------------------
# Compound Commands — high-level operations that replace manual orchestration
# ---------------------------------------------------------------------------

# Node-only classification commands
cmd_node_only() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh node-only <file>}"

  # Verify file exists in lockfile
  local exists
  exists=$(jq -r --arg f "$file" '.files[$f] // "null"' "$LOCKFILE")
  [[ "$exists" != "null" ]] || die "File not tracked in lockfile: $file"

  local current_sync
  current_sync=$(get_sync_field "$file")
  if [[ "$current_sync" == "node-only" ]]; then
    echo "SKIP: $file is already node-only."
    return 0
  fi

  local tmp; tmp=$(mktemp)
  jq --arg f "$file" '.files[$f].sync = "node-only"' "$LOCKFILE" > "$tmp"
  mv "$tmp" "$LOCKFILE"

  cmd_log "classify"
  cmd_log_detail "NODE-ONLY $file — excluded from sync"
  echo "NODE-ONLY: $file (excluded from future pull/push)"
}

cmd_track() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh track <file>}"

  local exists
  exists=$(jq -r --arg f "$file" '.files[$f] // "null"' "$LOCKFILE")
  [[ "$exists" != "null" ]] || die "File not tracked in lockfile: $file"

  local current_sync
  current_sync=$(get_sync_field "$file")
  if [[ "$current_sync" == "tracked" ]]; then
    echo "SKIP: $file is already tracked."
    return 0
  fi

  local tmp; tmp=$(mktemp)
  jq --arg f "$file" '.files[$f].sync = "tracked"' "$LOCKFILE" > "$tmp"
  mv "$tmp" "$LOCKFILE"

  cmd_log "classify"
  cmd_log_detail "TRACKED $file — re-included in sync"
  echo "TRACKED: $file (re-included in future pull/push)"
}

# classify: list all modified/local files that need classification
# Output: JSON array of {file, status, origin, sync} for unclassified files
cmd_classify() {
  require_lockfile
  local candidates="[]"

  while IFS= read -r file; do
    local status origin sync_field
    status=$(jq -r --arg f "$file" '.files[$f].status' "$LOCKFILE")
    origin=$(jq -r --arg f "$file" '.files[$f].origin' "$LOCKFILE")
    sync_field=$(get_sync_field "$file")

    # Only show files that are modified or local-only and not yet classified as node-only
    if [[ "$sync_field" != "node-only" && ("$status" == "modified" || "$status" == "local-only") ]]; then
      candidates=$(echo "$candidates" | jq --arg f "$file" --arg s "$status" --arg o "$origin" \
        '. + [{"file": $f, "status": $s, "origin": $o}]')
    fi
  done < <(jq -r '.files | keys[]' "$LOCKFILE" | sort)

  echo "$candidates" | jq '.'
}

# Pre-check: verify scaffold repo is clean and accessible
cmd_pre_check() {
  require_lockfile
  local scaffold_source
  scaffold_source=$(get_scaffold_source)

  [[ -d "$scaffold_source" ]] || die "Scaffold not found at: $scaffold_source"

  if git -C "$scaffold_source" rev-parse HEAD >/dev/null 2>&1; then
    local dirty
    dirty=$(git -C "$scaffold_source" status --porcelain 2>/dev/null)
    if [[ -n "$dirty" ]]; then
      echo "ERROR: Scaffold repo has uncommitted changes:" >&2
      echo "$dirty" >&2
      echo "" >&2
      echo "Commit or stash changes in $scaffold_source before syncing." >&2
      exit 1
    fi
  fi
  echo "OK"
}

# pull-plan: Compute the full pull plan as JSON
# Output: JSON array of {file, action, reason} objects
# Actions: auto-update, section-merge, conflict, new, removed, skip
cmd_pull_plan() {
  require_lockfile
  local scaffold_source
  scaffold_source=$(get_scaffold_source)

  local plan="[]"

  # Check each tracked file in the lockfile
  while IFS= read -r file; do
    local status origin scaffold_hash local_hash
    status=$(jq -r --arg f "$file" '.files[$f].status' "$LOCKFILE")
    origin=$(jq -r --arg f "$file" '.files[$f].origin' "$LOCKFILE")
    scaffold_hash=$(jq -r --arg f "$file" '.files[$f].scaffold_hash // "null"' "$LOCKFILE")
    local_hash=$(jq -r --arg f "$file" '.files[$f].local_hash // "null"' "$LOCKFILE")

    # Skip node-only files (permanently excluded from sync)
    if is_node_only "$file"; then
      continue
    fi

    # Skip local-only files (nothing to pull)
    if [[ "$status" == "local-only" ]]; then
      continue
    fi

    local scaffold_file="$scaffold_source/$file"

    # Check if file was removed from scaffold
    if [[ ! -f "$scaffold_file" ]]; then
      plan=$(echo "$plan" | jq --arg f "$file" \
        '. + [{"file": $f, "action": "removed", "reason": "File no longer exists in scaffold"}]')
      continue
    fi

    # Compute current hashes
    local current_scaffold_h current_local_h
    current_scaffold_h=$(file_hash "$scaffold_file")
    current_local_h=$(file_hash "$file" 2>/dev/null || echo "MISSING")

    # Has scaffold changed since last sync?
    local scaffold_changed=false
    if [[ "$current_scaffold_h" != "$scaffold_hash" ]]; then
      scaffold_changed=true
    fi

    # Has local file changed since last sync?
    local local_changed=false
    if [[ "$current_local_h" != "$local_hash" && "$current_local_h" != "MISSING" ]]; then
      local_changed=true
    fi

    if [[ "$scaffold_changed" == "false" ]]; then
      # Scaffold hasn't changed — nothing to pull
      continue
    fi

    if [[ "$current_local_h" == "MISSING" ]]; then
      # File exists in lockfile but not locally (deleted locally)
      plan=$(echo "$plan" | jq --arg f "$file" \
        '. + [{"file": $f, "action": "new", "reason": "File missing locally but exists in scaffold"}]')
      continue
    fi

    # Scaffold changed — check if local is clean or modified
    if [[ "$local_changed" == "false" && "$status" != "modified" ]]; then
      # Local is clean — safe to auto-update
      plan=$(echo "$plan" | jq --arg f "$file" \
        '. + [{"file": $f, "action": "auto-update", "reason": "Scaffold changed, local is clean"}]')
    else
      # Both sides changed — check for section-merge capability
      # Only markdown files can have section delimiters (avoids false positives
      # in scripts that contain delimiter strings as literals)
      local has_delimiter=false
      if [[ "$file" == *.md ]] && \
         (grep -qx '<!-- NODE-SPECIFIC-START -->' "$scaffold_file" 2>/dev/null || \
          grep -qx '<!-- HUB-MANAGED-START -->' "$scaffold_file" 2>/dev/null); then
        has_delimiter=true
      fi

      if [[ "$has_delimiter" == "true" ]]; then
        plan=$(echo "$plan" | jq --arg f "$file" \
          '. + [{"file": $f, "action": "section-merge", "reason": "Both changed, file has section delimiter"}]')
      else
        plan=$(echo "$plan" | jq --arg f "$file" \
          '. + [{"file": $f, "action": "conflict", "reason": "Both scaffold and local have changes"}]')
      fi
    fi
  done < <(jq -r '.files | keys[]' "$LOCKFILE" | sort)

  # Check for new files in scaffold not in lockfile
  while IFS= read -r file; do
    if ! jq -e --arg f "$file" '.files[$f]' "$LOCKFILE" >/dev/null 2>&1; then
      plan=$(echo "$plan" | jq --arg f "$file" \
        '. + [{"file": $f, "action": "new", "reason": "New file in scaffold, not yet tracked"}]')
    fi
  done < <(scan_scaffold_files "$scaffold_source")

  echo "$plan" | jq '.'
}

# pull-auto: Execute all auto-updates in one pass
# Processes only files with action "auto-update" from pull-plan
cmd_pull_auto() {
  require_lockfile
  local scaffold_source
  scaffold_source=$(get_scaffold_source)

  local count=0
  local plan
  plan=$(cmd_pull_plan)

  echo "$plan" | jq -r '.[] | select(.action == "auto-update") | .file' | while IFS= read -r file; do
    local scaffold_file="$scaffold_source/$file"
    local new_hash
    new_hash=$(file_hash "$scaffold_file")

    # Ensure target directory exists
    mkdir -p "$(dirname "$file")"

    # Copy scaffold version
    cp "$scaffold_file" "$file"

    # Update lockfile in one pass
    local tmp
    tmp=$(mktemp)
    jq --arg f "$file" --arg h "$new_hash" \
      '.files[$f].scaffold_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean"' \
      "$LOCKFILE" > "$tmp"
    mv "$tmp" "$LOCKFILE"

    # Log
    cmd_log_detail "AUTO-UPDATED $file"
    count=$((count + 1))
    echo "AUTO-UPDATED: $file"
  done

  echo "---"
  echo "Auto-updated files complete."
}

# pull-apply: Apply a specific resolution for a single file
# Usage: pull-apply <file> <action> [merged-content-file]
# Actions: take-scaffold, keep-local, section-merge, accept-new, delete, write-merged <path>
cmd_pull_apply() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh pull-apply <file> <action> [merged-content-file]}"
  local action="${2:?}"
  local merged_file="${3:-}"

  local scaffold_source
  scaffold_source=$(get_scaffold_source)
  local scaffold_file="$scaffold_source/$file"

  case "$action" in
    take-scaffold)
      [[ -f "$scaffold_file" ]] || die "Scaffold file not found: $scaffold_file"
      mkdir -p "$(dirname "$file")"
      cp "$scaffold_file" "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg h "$new_hash" \
        '.files[$f].scaffold_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean"' \
        "$LOCKFILE" > "$tmp"
      mv "$tmp" "$LOCKFILE"
      cmd_log_detail "OVERWRITTEN $file — took scaffold version"
      echo "APPLIED: $file (took scaffold)"
      ;;

    keep-local)
      # Update scaffold_hash to acknowledge we've seen the change, keep local as-is
      local new_scaffold_hash
      new_scaffold_hash=$(file_hash "$scaffold_file")
      local current_local_hash
      current_local_hash=$(file_hash "$file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg sh "$new_scaffold_hash" --arg lh "$current_local_hash" \
        '.files[$f].scaffold_hash = $sh | .files[$f].local_hash = $lh | .files[$f].status = "modified"' \
        "$LOCKFILE" > "$tmp"
      mv "$tmp" "$LOCKFILE"
      cmd_log_detail "SKIPPED $file — kept local version"
      echo "APPLIED: $file (kept local)"
      ;;

    section-merge)
      [[ -f "$scaffold_file" ]] || die "Scaffold file not found: $scaffold_file"
      [[ -f "$file" ]] || die "Local file not found: $file"
      local merged
      merged=$(cmd_section_merge "$scaffold_file" "$file")
      echo "$merged" > "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      local new_scaffold_hash
      new_scaffold_hash=$(file_hash "$scaffold_file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg sh "$new_scaffold_hash" --arg lh "$new_hash" \
        '.files[$f].scaffold_hash = $sh | .files[$f].local_hash = $lh | .files[$f].status = "clean"' \
        "$LOCKFILE" > "$tmp"
      mv "$tmp" "$LOCKFILE"
      cmd_log_detail "SECTION-MERGED $file"
      echo "APPLIED: $file (section-merged)"
      ;;

    accept-new)
      [[ -f "$scaffold_file" ]] || die "Scaffold file not found: $scaffold_file"
      mkdir -p "$(dirname "$file")"
      cp "$scaffold_file" "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      # Add new lockfile entry
      cmd_lock_add "$file" "scaffold" "$new_hash" "$new_hash" "clean"
      cmd_log_detail "ADDED $file"
      echo "APPLIED: $file (accepted new)"
      ;;

    delete)
      if [[ -f "$file" ]]; then
        rm "$file"
      fi
      cmd_lock_remove "$file"
      cmd_log_detail "DELETED $file"
      echo "APPLIED: $file (deleted)"
      ;;

    write-merged)
      [[ -n "$merged_file" ]] || die "Usage: pull-apply <file> write-merged <merged-content-file>"
      [[ -f "$merged_file" ]] || die "Merged content file not found: $merged_file"
      mkdir -p "$(dirname "$file")"
      cp "$merged_file" "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      local new_scaffold_hash
      new_scaffold_hash=$(file_hash "$scaffold_file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg sh "$new_scaffold_hash" --arg lh "$new_hash" \
        '.files[$f].scaffold_hash = $sh | .files[$f].local_hash = $lh | .files[$f].status = "modified"' \
        "$LOCKFILE" > "$tmp"
      mv "$tmp" "$LOCKFILE"
      cmd_log_detail "MERGED $file — Claude-proposed merge applied"
      echo "APPLIED: $file (merged)"
      ;;

    *)
      die "Unknown action: $action. Use: take-scaffold, keep-local, section-merge, accept-new, delete, write-merged"
      ;;
  esac
}

# pull-finalize: Update version, write log header, output summary
cmd_pull_finalize() {
  require_lockfile
  local scaffold_source
  scaffold_source=$(get_scaffold_source)

  local new_version
  if git -C "$scaffold_source" rev-parse HEAD >/dev/null 2>&1; then
    new_version=$(git -C "$scaffold_source" rev-parse --short HEAD)
  else
    new_version="unknown"
  fi

  cmd_lock_set_version "$new_version"
  cmd_log "pull from scaffold @ $new_version"

  echo "Pull finalized. Scaffold version: $new_version"
}

# push-candidates: List files eligible for push with current state
# Output: JSON array of {file, status, has_diff, first_lines}
cmd_push_candidates() {
  require_lockfile
  local scaffold_source
  scaffold_source=$(get_scaffold_source)
  local specific_file="${1:-}"

  local candidates="[]"

  while IFS= read -r file; do
    local status
    status=$(jq -r --arg f "$file" '.files[$f].status' "$LOCKFILE")

    # Skip node-only files (permanently excluded from sync)
    if is_node_only "$file"; then
      continue
    fi

    # Only modified and local-only files are push candidates
    if [[ "$status" != "modified" && "$status" != "local-only" && "$status" != "promoted" ]]; then
      continue
    fi

    # If user specified a file, skip others
    if [[ -n "$specific_file" && "$file" != "$specific_file" ]]; then
      continue
    fi

    [[ -f "$file" ]] || continue

    local has_diff="false"
    local scaffold_file="$scaffold_source/$file"
    if [[ -f "$scaffold_file" ]]; then
      if ! diff -q "$scaffold_file" "$file" >/dev/null 2>&1; then
        has_diff="true"
      fi
    fi

    candidates=$(echo "$candidates" | jq --arg f "$file" --arg s "$status" --arg d "$has_diff" \
      '. + [{"file": $f, "status": $s, "has_diff": ($d == "true")}]')
  done < <(jq -r '.files | keys[]' "$LOCKFILE" | sort)

  echo "$candidates" | jq '.'
}

# push-apply: Push a single file to the scaffold
# Usage: push-apply <file> [description]
cmd_push_apply() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh push-apply <file> [description]}"
  local description="${2:-updated $file}"

  local scaffold_source
  scaffold_source=$(get_scaffold_source)
  local status
  status=$(jq -r --arg f "$file" '.files[$f].status // "unknown"' "$LOCKFILE")

  [[ -f "$file" ]] || die "File not found: $file"

  # Ensure target directory exists in scaffold
  mkdir -p "$(dirname "$scaffold_source/$file")"

  # Copy to scaffold
  cp "$file" "$scaffold_source/$file"

  # Update lockfile based on current status
  local new_hash
  new_hash=$(file_hash "$file")

  local tmp; tmp=$(mktemp)
  if [[ "$status" == "local-only" ]]; then
    # Promoting: update origin and status
    jq --arg f "$file" --arg h "$new_hash" \
      '.files[$f].origin = "scaffold" | .files[$f].scaffold_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "promoted"' \
      "$LOCKFILE" > "$tmp"
    cmd_log_detail "PROMOTED $file"
    cmd_changelog_detail "ADDED $file — $description"
  else
    # Modified → synced: update hashes and status
    jq --arg f "$file" --arg h "$new_hash" \
      '.files[$f].scaffold_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean"' \
      "$LOCKFILE" > "$tmp"
    cmd_log_detail "UPDATED $file"
    cmd_changelog_detail "MODIFIED $file — $description"
  fi
  mv "$tmp" "$LOCKFILE"

  echo "PUSHED: $file ($status → pushed)"
}

# push-finalize: Commit in scaffold repo, update version, write logs
# Usage: push-finalize <commit-message>
cmd_push_finalize() {
  require_lockfile
  local message="${1:?Usage: scaffold-sync.sh push-finalize <commit-message>}"

  local scaffold_source
  scaffold_source=$(get_scaffold_source)

  # Get project name for logging
  local project_name
  project_name=$(basename "$(pwd)")

  # Stage and commit in scaffold
  git -C "$scaffold_source" add -A
  git -C "$scaffold_source" commit -m "$message" || echo "Nothing to commit in scaffold"

  # Update version
  local new_version
  if git -C "$scaffold_source" rev-parse HEAD >/dev/null 2>&1; then
    new_version=$(git -C "$scaffold_source" rev-parse --short HEAD)
  else
    new_version="unknown"
  fi

  cmd_lock_set_version "$new_version"
  cmd_log "push to scaffold @ $new_version"
  cmd_changelog "push from $project_name"

  echo "Push finalized. Scaffold version: $new_version"
}

# promote: Full promote workflow for a single file
# Usage: promote <file>
cmd_promote() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh promote <file>}"

  local status
  status=$(jq -r --arg f "$file" '.files[$f].status // "unknown"' "$LOCKFILE")

  if [[ "$status" == "clean" || "$status" == "promoted" ]]; then
    echo "SKIP: $file is already $status — nothing to promote."
    exit 0
  fi

  if [[ "$status" != "local-only" ]]; then
    die "Cannot promote: $file has status '$status'. Only local-only files can be promoted."
  fi

  [[ -f "$file" ]] || die "File not found: $file"

  local scaffold_source
  scaffold_source=$(get_scaffold_source)

  # Copy to scaffold
  mkdir -p "$(dirname "$scaffold_source/$file")"
  cp "$file" "$scaffold_source/$file"

  # Update lockfile
  local new_hash
  new_hash=$(file_hash "$file")
  local tmp; tmp=$(mktemp)
  jq --arg f "$file" --arg h "$new_hash" \
    '.files[$f].origin = "scaffold" | .files[$f].scaffold_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "promoted"' \
    "$LOCKFILE" > "$tmp"
  mv "$tmp" "$LOCKFILE"

  # Log
  cmd_log_detail "PROMOTED $file"
  cmd_changelog_detail "ADDED $file — promoted from $(basename "$(pwd)")"

  # Commit in scaffold
  git -C "$scaffold_source" add -A
  git -C "$scaffold_source" commit -m "chore(scaffold): add $(basename "$file") from $(basename "$(pwd)")"

  # Update version
  local new_version
  new_version=$(git -C "$scaffold_source" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  cmd_lock_set_version "$new_version"
  cmd_log "promote to scaffold @ $new_version"
  cmd_changelog "promote from $(basename "$(pwd)")"

  echo "PROMOTED: $file → scaffold @ $new_version"
}

# demote: Full demote workflow for a single file
# Usage: demote <file>
cmd_demote() {
  require_lockfile
  local file="${1:?Usage: scaffold-sync.sh demote <file>}"

  local status
  status=$(jq -r --arg f "$file" '.files[$f].status // "unknown"' "$LOCKFILE")

  if [[ "$status" == "modified" || "$status" == "local-only" ]]; then
    echo "SKIP: $file is already $status — effectively demoted."
    exit 0
  fi

  if [[ "$status" != "clean" ]]; then
    die "Cannot demote: $file has status '$status'. Only clean files can be demoted."
  fi

  # Mark as modified (prevents auto-update on future pulls)
  local tmp; tmp=$(mktemp)
  jq --arg f "$file" '.files[$f].status = "modified"' "$LOCKFILE" > "$tmp"
  mv "$tmp" "$LOCKFILE"

  # Log
  cmd_log "demote"
  cmd_log_detail "DEMOTED $file — marked as local override"

  echo "DEMOTED: $file (future pulls will show diff instead of auto-updating)"
}

cmd_scan() {
  echo "Tracked files in project:"
  scan_tracked_files | while IFS= read -r f; do
    echo "  $f"
  done

  if [[ -f "$LOCKFILE" ]]; then
    local scaffold_source
    scaffold_source=$(get_scaffold_source)
    echo ""
    echo "Tracked files in scaffold ($scaffold_source):"
    scan_scaffold_files "$scaffold_source" | while IFS= read -r f; do
      echo "  $f"
    done
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

require_jq

case "${1:-}" in
  # --- Atomic commands (building blocks) ---
  init)             shift; cmd_init "$@" ;;
  status)           cmd_status ;;
  diff)             shift; cmd_diff "${1:-}" ;;
  hash)             shift; cmd_hash "$@" ;;
  lock-get)         shift; cmd_lock_get "$@" ;;
  lock-update)      shift; cmd_lock_update "$@" ;;
  lock-add)         shift; cmd_lock_add "$@" ;;
  lock-remove)      shift; cmd_lock_remove "$@" ;;
  lock-set-version) shift; cmd_lock_set_version "$@" ;;
  log)              shift; cmd_log "$@" ;;
  log-detail)       shift; cmd_log_detail "$@" ;;
  changelog)        shift; cmd_changelog "$@" ;;
  changelog-detail) shift; cmd_changelog_detail "$@" ;;
  section-merge)    shift; cmd_section_merge "$@" ;;
  scan)             cmd_scan ;;

  # --- Classification commands ---
  node-only)        shift; cmd_node_only "$@" ;;
  track)            shift; cmd_track "$@" ;;
  classify)         cmd_classify ;;

  # --- Compound commands (replace manual orchestration) ---
  pre-check)        cmd_pre_check ;;
  pull-plan)        cmd_pull_plan ;;
  pull-auto)        cmd_pull_auto ;;
  pull-apply)       shift; cmd_pull_apply "$@" ;;
  pull-finalize)    cmd_pull_finalize ;;
  push-candidates)  shift; cmd_push_candidates "${1:-}" ;;
  push-apply)       shift; cmd_push_apply "$@" ;;
  push-finalize)    shift; cmd_push_finalize "$@" ;;
  promote)          shift; cmd_promote "$@" ;;
  demote)           shift; cmd_demote "$@" ;;

  *)
    echo "Usage: scaffold-sync.sh <command> [args]"
    echo ""
    echo "Classification commands:"
    echo "  node-only <file>                      Mark file as node-only (exclude from sync)"
    echo "  track <file>                          Mark file as tracked (re-include in sync)"
    echo "  classify                              List unclassified modified/local files as JSON"
    echo ""
    echo "Compound commands (use these — they handle copy + lockfile + log in one call):"
    echo "  pre-check                             Verify scaffold repo is clean"
    echo "  pull-plan                             Compute pull plan as JSON"
    echo "  pull-auto                             Execute all auto-updates in one pass"
    echo "  pull-apply <file> <action> [merged]   Apply a conflict resolution"
    echo "  pull-finalize                         Update version and write log"
    echo "  push-candidates [file]                List push-eligible files as JSON"
    echo "  push-apply <file> [description]       Push a file to scaffold"
    echo "  push-finalize <commit-message>        Commit in scaffold and update version"
    echo "  promote <file>                        Full promote workflow"
    echo "  demote <file>                         Full demote workflow"
    echo ""
    echo "Atomic commands (building blocks — prefer compound commands):"
    echo "  init [scaffold-path]                  Generate lockfile from current state"
    echo "  status                                Show file provenance and sync state"
    echo "  diff [file]                           Show diff between local and scaffold"
    echo "  hash <file>                           Compute sha256 of a file"
    echo "  lock-get <file>                       Read a lockfile entry"
    echo "  lock-update <file> <field> <value>    Update a lockfile field"
    echo "  lock-add <file> <origin> <sh> <lh> <status>  Add a lockfile entry"
    echo "  lock-remove <file>                    Remove a lockfile entry"
    echo "  lock-set-version <version>            Update scaffold version in lockfile"
    echo "  log <message>                         Append to project sync log"
    echo "  log-detail <detail>                   Add detail to last log entry"
    echo "  changelog <message>                   Append to scaffold changelog"
    echo "  changelog-detail <detail>             Add detail to last changelog entry"
    echo "  section-merge <scaffold> <local>       Merge hub/node sections of delimited file"
    echo "  scan                                  List all trackable files"
    exit 1
    ;;
esac
