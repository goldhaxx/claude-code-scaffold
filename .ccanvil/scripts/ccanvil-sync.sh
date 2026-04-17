#!/usr/bin/env bash
# ccanvil-sync.sh — Bi-directional sync between a project and the hub.
#
# Usage:
#   ccanvil-sync.sh init [hub-path]          Generate lockfile from current state
#   ccanvil-sync.sh init-preflight <hub>       Scan for conflicts, output merge plan
#   ccanvil-sync.sh init-apply <hub> <plan>    Execute an approved merge plan
#   ccanvil-sync.sh status                     Show file provenance and sync state
#   ccanvil-sync.sh changelog                List hub commits since last sync (JSON)
#   ccanvil-sync.sh diff [file]            Show diff between local and hub versions
#   ccanvil-sync.sh hash <file>            Compute sha256 of a file
#   ccanvil-sync.sh lock-get <file>        Read a lockfile entry (JSON)
#   ccanvil-sync.sh lock-update <file> <field> <value>  Update a lockfile field
#   ccanvil-sync.sh section-merge <s> <l>  Merge hub/node sections of a delimited file
#   ccanvil-sync.sh scan                   List all trackable files in the project

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
LOCKFILE=".ccanvil/ccanvil.lock"

# Directories and patterns to track (relative to project root)
TRACKED_PATTERNS=(
  ".claude/rules/*.md"
  ".claude/commands/*.md"
  ".claude/agents/*.md"
  ".claude/skills/*/SKILL.md"
  ".claude/hooks/*.sh"
  ".claude/settings.json"
  ".claude/ccanvil.json"
  ".ccanvil/templates/*.md"
  ".ccanvil/scripts/*.sh"
  ".ccanvil/guide/*.md"
  "CLAUDE.md"
)

# Files to never track
EXCLUDED_FILES=(
  ".ccanvil/ccanvil.lock"
)

# Extra files copied during init that aren't in TRACKED_PATTERNS
INIT_EXTRA_FILES=(
  ".gitignore"
  ".claudeignore"
  ".claude/lint.json"
)

# GitHub template mappings: hub_source_path:destination_path
# Source paths are relative to dist_root/.ccanvil/templates/github/
# Destination paths are relative to project root
INIT_GITHUB_TEMPLATES=(
  "README.md:README.md"
  "CONTRIBUTING.md:CONTRIBUTING.md"
  "PULL_REQUEST_TEMPLATE.md:.github/PULL_REQUEST_TEMPLATE.md"
  "workflows/ci.yml:.github/workflows/ci.yml"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

guard_fail() {
  local operation="${1:?}"
  local file="${2:?}"
  local reason="${3:?}"
  echo "GUARD_FAIL: $operation on $file: $reason" >&2
  exit 3
}

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed. Run: brew install jq"
}

# Validate jq output is non-empty valid JSON before mv — prevents lockfile corruption
# commit_hub_file: auto-commit a single file in the hub repo.
# No-op if: hub isn't a git repo, file unchanged, file not tracked.
# On commit failure: prints a warning, returns 0 (AC-8 failure tolerance).
# Usage: commit_hub_file <hub_path> <rel_file> <commit_message>
commit_hub_file() {
  local hub_path="$1"
  local rel_file="$2"
  local message="$3"

  # Must be a git repo
  git -C "$hub_path" rev-parse --git-dir >/dev/null 2>&1 || return 0

  # Must actually have changes to the file (tracked-and-modified OR untracked)
  if git -C "$hub_path" diff --quiet -- "$rel_file" 2>/dev/null && \
     git -C "$hub_path" diff --cached --quiet -- "$rel_file" 2>/dev/null; then
    # Not modified or staged. Check if untracked.
    if ! git -C "$hub_path" ls-files --others --exclude-standard -- "$rel_file" 2>/dev/null | grep -q .; then
      return 0
    fi
  fi

  (cd "$hub_path" && \
    ALLOW_MAIN=1 git add -- "$rel_file" && \
    ALLOW_MAIN=1 git commit -m "$message" --quiet --only -- "$rel_file" 2>&1) || \
    echo "WARNING: auto-commit of $rel_file failed (hub left dirty)" >&2
  return 0
}

safe_lock_mv() {
  local tmp="$1"
  local target="$2"
  local context="${3:-lockfile mutation}"
  if [[ ! -s "$tmp" ]] || ! jq empty "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    guard_fail "jq" "$target" "jq produced invalid JSON during $context"
  fi
  mv "$tmp" "$target"
}

require_lockfile() {
  [[ -f "$LOCKFILE" ]] || die "No $LOCKFILE found. Run: ccanvil-sync.sh init"
}

get_hub_source_raw() {
  # Returns absolute path to the hub root (for git operations on the hub)
  jq -r '.hub_source' "$LOCKFILE" | sed "s|^~|$HOME|"
}

get_hub_source() {
  # Returns absolute path to the hub root (where distributable files live).
  get_hub_source_raw
}

get_hub_source_display() {
  # Returns path with ~ (for commit messages, output — no PII)
  jq -r '.hub_source' "$LOCKFILE"
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
  date +%s
}

# UUID v4 regex (lowercase)
UUID_V4_REGEX='^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'

generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
  else
    die "No UUID generator available. Install uuidgen or python3."
  fi
}

validate_uuid() {
  local uuid="$1"
  [[ "$uuid" =~ $UUID_V4_REGEX ]]
}

normalize_path() {
  # Convert absolute path to ~-form if under $HOME
  local path="$1"
  echo "${path/#$HOME/~}"
}

expand_path() {
  # Expand ~-form path to absolute using current $HOME
  local path="$1"
  echo "${path/#\~/$HOME}"
}

# Get or create node UUID. Canonical source: .claude/ccanvil.local.json.
# Mirrors to .ccanvil/ccanvil.lock if lockfile exists.
get_or_create_node_uuid() {
  local ccanvil_json=".claude/ccanvil.local.json"
  local existing=""

  # Check canonical source first
  if [[ -f "$ccanvil_json" ]]; then
    existing=$(jq -r '.node_uuid // empty' "$ccanvil_json" 2>/dev/null || true)
    if [[ -n "$existing" ]]; then
      validate_uuid "$existing" || die "Invalid UUID in $ccanvil_json: $existing"
      echo "$existing"
      return 0
    fi
  fi

  # Fall back to lockfile
  if [[ -f "$LOCKFILE" ]]; then
    existing=$(jq -r '.node_uuid // empty' "$LOCKFILE" 2>/dev/null || true)
    if [[ -n "$existing" ]]; then
      validate_uuid "$existing" || die "Invalid UUID in $LOCKFILE: $existing"
      echo "$existing"
      return 0
    fi
  fi

  # Generate new
  local new_uuid
  new_uuid=$(generate_uuid)
  validate_uuid "$new_uuid" || die "Generated invalid UUID: $new_uuid"
  echo "$new_uuid"
}

# Migrate path-keyed registry entries to UUID-keyed. Idempotent.
# For each legacy path-key, resolve the node's UUID (from its ccanvil.json),
# rewrite the entry under the UUID key, delete the old path key.
migrate_registry() {
  local registry="$1"
  [[ -f "$registry" ]] || return 0

  local legacy_keys
  legacy_keys=$(jq -r '.nodes | keys[] | select(test("^[/~]"))' "$registry" 2>/dev/null || true)
  [[ -z "$legacy_keys" ]] && return 0

  while IFS= read -r legacy_key; do
    [[ -z "$legacy_key" ]] && continue

    # Resolve path and check node existence
    local resolved
    resolved=$(expand_path "$legacy_key")
    if [[ ! -d "$resolved" ]]; then
      # Leave entry as-is; will be reported as STALE during iteration.
      continue
    fi

    # Read UUID from ccanvil.local.json if present; otherwise generate in the node.
    local node_uuid=""
    if [[ -f "$resolved/.claude/ccanvil.local.json" ]]; then
      node_uuid=$(jq -r '.node_uuid // empty' "$resolved/.claude/ccanvil.local.json" 2>/dev/null)
    fi
    if [[ -z "$node_uuid" ]]; then
      # Generate + persist inside the node via subshell (cd doesn't leak).
      node_uuid=$(cd "$resolved" && {
        u=$(get_or_create_node_uuid 2>/dev/null) && \
        persist_node_uuid "$u" 2>/dev/null && \
        echo "$u"
      })
      [[ -z "$node_uuid" ]] && continue
      validate_uuid "$node_uuid" || continue
    fi

    # Rewrite entry under UUID key with portable path
    local portable_path
    portable_path=$(normalize_path "$resolved")
    local node_name
    node_name=$(basename "$resolved")

    local tmp
    tmp=$(mktemp)
    jq --arg old "$legacy_key" --arg u "$node_uuid" --arg p "$portable_path" --arg n "$node_name" '
      .nodes[$u] = (.nodes[$u] // {}) + (.nodes[$old] // {}) + {"name": $n, "path": $p}
      | del(.nodes[$old])
    ' "$registry" > "$tmp"
    if [[ -s "$tmp" ]] && jq empty "$tmp" 2>/dev/null; then
      mv "$tmp" "$registry"
    else
      rm -f "$tmp"
    fi
  done <<< "$legacy_keys"
}

# Write UUID to both canonical (.claude/ccanvil.local.json) and mirror (lockfile).
persist_node_uuid() {
  local uuid="$1"
  validate_uuid "$uuid" || die "Cannot persist invalid UUID: $uuid"

  # Canonical: .claude/ccanvil.local.json
  local ccanvil_json=".claude/ccanvil.local.json"
  mkdir -p "$(dirname "$ccanvil_json")"
  if [[ ! -f "$ccanvil_json" ]]; then
    echo '{}' > "$ccanvil_json"
  fi
  local tmp
  tmp=$(mktemp)
  jq --arg u "$uuid" '.node_uuid = $u' "$ccanvil_json" > "$tmp" && mv "$tmp" "$ccanvil_json"

  # Mirror: lockfile (if it exists)
  if [[ -f "$LOCKFILE" ]]; then
    tmp=$(mktemp)
    jq --arg u "$uuid" '.node_uuid = $u' "$LOCKFILE" > "$tmp"
    if [[ -s "$tmp" ]] && jq empty "$tmp" 2>/dev/null; then
      mv "$tmp" "$LOCKFILE"
    else
      rm -f "$tmp"
    fi
  fi
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


# Scan hub for all files matching tracked patterns
scan_hub_files() {
  local hub_path="$1"
  local dist_root
  dist_root="$hub_path"
  local files=()
  for pattern in "${TRACKED_PATTERNS[@]}"; do
    local matches
    matches=( "$dist_root"/$pattern ) 2>/dev/null || true
    for f in "${matches[@]}"; do
      if [[ -f "$f" ]]; then
        # Convert to relative path (strip dist_root prefix)
        local rel="${f#$dist_root/}"
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
  local hub_path="${1:-$HOME/projects/ccanvil}"
  hub_path="${hub_path/#\~/$HOME}"

  [[ -d "$hub_path" ]] || die "Hub not found at: $hub_path"

  # Resolve dist root (hub root where distributable files live)
  local dist_root
  dist_root="$hub_path"

  # Get hub git version
  local hub_version="unknown"
  if git -C "$hub_path" rev-parse HEAD >/dev/null 2>&1; then
    hub_version=$(git -C "$hub_path" rev-parse --short HEAD)
  fi

  # Build the files object
  local files_json="{}"

  # Find all trackable files in the project
  while IFS= read -r file; do
    local hub_file="$dist_root/$file"
    local local_h
    local_h=$(file_hash "$file")

    if [[ -f "$hub_file" ]]; then
      local hub_h
      hub_h=$(file_hash "$hub_file")

      if [[ "$local_h" == "$hub_h" ]]; then
        local status="clean"
      else
        local status="modified"
      fi

      files_json=$(echo "$files_json" | jq --arg f "$file" --arg sh "$hub_h" --arg lh "$local_h" --arg st "$status" \
        '. + {($f): {"origin": "hub", "hub_hash": $sh, "local_hash": $lh, "status": $st, "sync": "tracked"}}')
    else
      # File exists locally but not in hub
      files_json=$(echo "$files_json" | jq --arg f "$file" --arg lh "$local_h" \
        '. + {($f): {"origin": "local", "hub_hash": null, "local_hash": $lh, "status": "local-only", "sync": "tracked"}}')
    fi
  done < <(scan_tracked_files)

  # Check for files in hub that are NOT in the project
  while IFS= read -r file; do
    if ! echo "$files_json" | jq -e --arg f "$file" '.[$f]' >/dev/null 2>&1; then
      local hub_h
      hub_h=$(file_hash "$dist_root/$file")
      files_json=$(echo "$files_json" | jq --arg f "$file" --arg sh "$hub_h" \
        '. + {($f): {"origin": "hub", "hub_hash": $sh, "local_hash": null, "status": "hub-only", "sync": "tracked"}}')
    fi
  done < <(scan_hub_files "$hub_path")

  # Write lockfile (store ~ instead of absolute home path to avoid PII in tracked files)
  local display_path="${hub_path/#$HOME/~}"
  jq -n --arg src "$display_path" --arg ver "$hub_version" --arg ts "$(timestamp)" --argjson files "$files_json" \
    '{hub_source: $src, hub_version: $ver, synced_at: $ts, files: $files}' > "$LOCKFILE"

  local total
  total=$(echo "$files_json" | jq 'length')
  local clean modified local_only hub_only
  clean=$(echo "$files_json" | jq '[.[] | select(.status == "clean")] | length')
  modified=$(echo "$files_json" | jq '[.[] | select(.status == "modified")] | length')
  local_only=$(echo "$files_json" | jq '[.[] | select(.status == "local-only")] | length')
  hub_only=$(echo "$files_json" | jq '[.[] | select(.status == "hub-only")] | length')

  echo "Lockfile generated: $LOCKFILE"
  echo "  Hub: $display_path @ $hub_version"
  echo "  Total files: $total"
  echo "  Clean: $clean | Modified: $modified | Local: $local_only | Hub-only: $hub_only"

  # Ensure node UUID exists and is mirrored in both lockfile and ccanvil.json
  local node_uuid
  node_uuid=$(get_or_create_node_uuid)
  persist_node_uuid "$node_uuid"

  # Auto-register with the hub
  cmd_register 2>/dev/null || echo "WARNING: Hub registration failed (non-fatal)"
}

cmd_init_preflight() {
  local hub_path="${1:?Usage: ccanvil-sync.sh init-preflight <hub-path>}"
  hub_path="${hub_path/#\~/$HOME}"
  shift

  [[ -d "$hub_path" ]] || die "Hub not found at: $hub_path"

  # Parse --stack flags
  local stack_ids=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stack) shift; stack_ids+=("${1:?--stack requires an argument}"); shift ;;
      *) shift ;;
    esac
  done

  # Also read stacks from ccanvil.json if present
  if [[ -f ".claude/ccanvil.json" ]]; then
    while IFS= read -r sid; do
      [[ -z "$sid" ]] && continue
      # Avoid duplicates
      local already=false
      for existing in "${stack_ids[@]+"${stack_ids[@]}"}"; do
        [[ "$existing" == "$sid" ]] && already=true && break
      done
      $already || stack_ids+=("$sid")
    done < <(jq -r '.stacks[]? // empty' ".claude/ccanvil.json" 2>/dev/null)
  fi

  local dist_root
  dist_root="$hub_path"
  local github_tpl_root="$dist_root/.ccanvil/templates/github"

  local plan="[]"
  local seen_files=()

  # Helper: classify a single file
  # Args: hub_file_abs local_file_rel
  classify_file() {
    local hub_file="$1"
    local local_file="$2"

    if [[ ! -f "$local_file" ]]; then
      # Hub-only: no local file exists
      plan=$(echo "$plan" | jq --arg f "$local_file" \
        '. + [{"file": $f, "source": "hub-only", "recommended_action": "copy", "reason": "New file from hub"}]')
    else
      local hub_h local_h
      hub_h=$(file_hash "$hub_file")
      local_h=$(file_hash "$local_file")

      if [[ "$hub_h" == "$local_h" ]]; then
        # Identical — skip
        plan=$(echo "$plan" | jq --arg f "$local_file" \
          '. + [{"file": $f, "source": "both", "recommended_action": "skip", "reason": "Already matches hub"}]')
      else
        # Different — check for section-merge delimiter
        local has_delimiter=false
        if [[ "$local_file" == *.md ]] && \
           (grep -qx '<!-- NODE-SPECIFIC-START -->' "$hub_file" 2>/dev/null || \
            grep -qx '<!-- HUB-MANAGED-START -->' "$hub_file" 2>/dev/null); then
          has_delimiter=true
        fi

        if [[ "$has_delimiter" == "true" ]]; then
          plan=$(echo "$plan" | jq --arg f "$local_file" \
            '. + [{"file": $f, "source": "both", "recommended_action": "section-merge", "reason": "Both versions exist; can merge hub and local sections"}]')
        else
          plan=$(echo "$plan" | jq --arg f "$local_file" \
            '. + [{"file": $f, "source": "both", "recommended_action": "review", "reason": "Local differs from hub; needs user decision"}]')
        fi
      fi
    fi
    seen_files+=("$local_file")
  }

  # 1. Scan hub tracked files
  while IFS= read -r file; do
    classify_file "$dist_root/$file" "$file"
  done < <(scan_hub_files "$hub_path")

  # 2. Scan init extra files
  for file in "${INIT_EXTRA_FILES[@]}"; do
    if [[ -f "$dist_root/$file" ]]; then
      classify_file "$dist_root/$file" "$file"
    fi
  done

  # 3. Scan GitHub templates (source:destination mapping)
  for mapping in "${INIT_GITHUB_TEMPLATES[@]}"; do
    local src="${mapping%%:*}"
    local dst="${mapping#*:}"
    local hub_file="$github_tpl_root/$src"
    if [[ -f "$hub_file" ]]; then
      classify_file "$hub_file" "$dst"
    fi
  done

  # 4. Scan local tracked files for local-only entries
  if compgen -G ".claude/rules/*.md" >/dev/null 2>&1 || \
     compgen -G ".claude/commands/*.md" >/dev/null 2>&1 || \
     compgen -G ".claude/agents/*.md" >/dev/null 2>&1 || \
     compgen -G ".claude/skills/*/SKILL.md" >/dev/null 2>&1 || \
     compgen -G ".claude/hooks/*.sh" >/dev/null 2>&1; then
    while IFS= read -r file; do
      # Skip if already seen
      local already_seen=false
      for s in "${seen_files[@]}"; do
        [[ "$s" == "$file" ]] && already_seen=true && break
      done
      $already_seen && continue

      plan=$(echo "$plan" | jq --arg f "$file" \
        '. + [{"file": $f, "source": "local-only", "recommended_action": "skip", "reason": "Local file, not in hub"}]')
    done < <(scan_tracked_files)
  fi

  # 5. Scan stack profile files (AC-5)
  for sid in "${stack_ids[@]+"${stack_ids[@]}"}"; do
    local stack_manifest="$dist_root/hub/stacks/$sid/manifest.json"
    [[ -f "$stack_manifest" ]] || continue
    local stack_dir="$dist_root/hub/stacks/$sid"
    local fc
    fc=$(jq '.files | length' "$stack_manifest")
    for i in $(seq 0 $((fc - 1))); do
      local src tgt
      src=$(jq -r ".files[$i].source" "$stack_manifest")
      tgt=$(jq -r ".files[$i].target" "$stack_manifest")
      # Skip if already seen
      local already_seen=false
      for s in "${seen_files[@]+"${seen_files[@]}"}"; do
        [[ "$s" == "$tgt" ]] && already_seen=true && break
      done
      $already_seen && continue

      if [[ -f "$tgt" ]]; then
        local hub_h local_h
        hub_h=$(file_hash "$stack_dir/$src")
        local_h=$(file_hash "$tgt")
        if [[ "$hub_h" == "$local_h" ]]; then
          plan=$(echo "$plan" | jq --arg f "$tgt" --arg s "stack:$sid" \
            '. + [{"file": $f, "source": $s, "recommended_action": "skip", "reason": "Already matches stack"}]')
        else
          plan=$(echo "$plan" | jq --arg f "$tgt" --arg s "stack:$sid" \
            '. + [{"file": $f, "source": $s, "recommended_action": "review", "reason": "Local differs from stack; needs user decision"}]')
        fi
      else
        plan=$(echo "$plan" | jq --arg f "$tgt" --arg s "stack:$sid" \
          '. + [{"file": $f, "source": $s, "recommended_action": "copy", "reason": "New file from stack"}]')
      fi
      seen_files+=("$tgt")
    done
  done

  # Compute summary
  local conflicts auto total
  conflicts=$(echo "$plan" | jq '[.[] | select(.recommended_action == "review")] | length')
  auto=$(echo "$plan" | jq '[.[] | select(.recommended_action != "review")] | length')
  total=$(echo "$plan" | jq 'length')

  jq -n --argjson conflicts "$conflicts" --argjson auto "$auto" --argjson total "$total" --argjson plan "$plan" \
    '{"summary": {"conflicts": $conflicts, "auto": $auto, "total": $total}, "plan": $plan}'
}

cmd_init_apply() {
  local hub_path="${1:?Usage: ccanvil-sync.sh init-apply <hub-path> <plan-file>}"
  local plan_file="${2:?Usage: ccanvil-sync.sh init-apply <hub-path> <plan-file>}"
  hub_path="${hub_path/#\~/$HOME}"

  [[ -d "$hub_path" ]] || die "Hub not found at: $hub_path"
  [[ -f "$plan_file" ]] || die "Plan file not found: $plan_file"

  local dist_root
  dist_root="$hub_path"
  local github_tpl_root="$dist_root/.ccanvil/templates/github"

  local copied=0 skipped=0 merged=0 errors=0

  # Auto-detect format: accept both {plan:[], summary:{}} and bare []
  local plan_expr='.'
  if jq -e 'type == "object" and has("plan")' "$plan_file" > /dev/null 2>&1; then
    plan_expr='.plan'
  elif ! jq -e 'type == "array"' "$plan_file" > /dev/null 2>&1; then
    die "Invalid plan file: expected JSON array or object with .plan key"
  fi

  # Process each entry in the plan
  local entry_count
  entry_count=$(jq "$plan_expr | length" "$plan_file")

  local i=0
  while [[ $i -lt $entry_count ]]; do
    local file action source
    file=$(jq -r "$plan_expr | .[$i].file" "$plan_file")
    action=$(jq -r "$plan_expr | .[$i].recommended_action" "$plan_file")
    source=$(jq -r "$plan_expr | .[$i].source // empty" "$plan_file")

    # Resolve hub source file path
    local hub_file=""

    # Check stack source first (AC-6)
    if [[ "$source" == stack:* ]]; then
      local stack_id="${source#stack:}"
      local stack_manifest="$dist_root/hub/stacks/$stack_id/manifest.json"
      if [[ -f "$stack_manifest" ]]; then
        local stack_src
        stack_src=$(jq -r --arg t "$file" '.files[] | select(.target == $t) | .source' "$stack_manifest")
        if [[ -n "$stack_src" ]]; then
          hub_file="$dist_root/hub/stacks/$stack_id/$stack_src"
        fi
      fi
    fi

    # Check GitHub template mappings
    if [[ -z "$hub_file" ]]; then
      for mapping in "${INIT_GITHUB_TEMPLATES[@]}"; do
        local tpl_src="${mapping%%:*}"
        local tpl_dst="${mapping#*:}"
        if [[ "$tpl_dst" == "$file" ]]; then
          hub_file="$github_tpl_root/$tpl_src"
          break
        fi
      done
    fi
    if [[ -z "$hub_file" && -f "$dist_root/$file" ]]; then
      hub_file="$dist_root/$file"
    fi

    case "$action" in
      copy|overwrite)
        if [[ -z "$hub_file" || ! -f "$hub_file" ]]; then
          echo "ERROR: Hub source not found for $file" >&2
          errors=$((errors + 1))
          i=$((i + 1)); continue
        fi
        mkdir -p "$(dirname "$file")"
        cp "$hub_file" "$file"
        copied=$((copied + 1))
        echo "COPIED: $file"
        ;;
      skip)
        skipped=$((skipped + 1))
        ;;
      section-merge)
        if [[ -z "$hub_file" || ! -f "$hub_file" ]]; then
          echo "ERROR: Hub source not found for $file" >&2
          errors=$((errors + 1))
          i=$((i + 1)); continue
        fi
        if [[ ! -f "$file" ]]; then
          # Local doesn't exist — just copy
          mkdir -p "$(dirname "$file")"
          cp "$hub_file" "$file"
          copied=$((copied + 1))
          echo "COPIED: $file (no local to merge)"
        else
          local merge_result
          merge_result=$(cmd_section_merge "$hub_file" "$file" 2>/dev/null) && {
            echo "$merge_result" > "$file"
            merged=$((merged + 1))
            echo "MERGED: $file"
          } || {
            echo "ERROR: Section-merge failed for $file" >&2
            errors=$((errors + 1))
          }
        fi
        ;;
      *)
        echo "UNKNOWN ACTION: $action for $file — skipping" >&2
        skipped=$((skipped + 1))
        ;;
    esac
    i=$((i + 1))
  done

  jq -n --argjson copied "$copied" --argjson skipped "$skipped" --argjson merged "$merged" --argjson errors "$errors" \
    '{"copied": $copied, "skipped": $skipped, "merged": $merged, "errors": $errors}'
}

cmd_status() {
  require_lockfile

  # Parse flags
  local json_mode=false
  local filter_status=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      --filter) filter_status="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local hub_source
  hub_source=$(get_hub_source)
  local hub_root
  hub_root=$(get_hub_source_raw)
  local hub_version
  hub_version=$(jq -r '.hub_version' "$LOCKFILE")
  local synced_at
  synced_at=$(jq -r '.synced_at' "$LOCKFILE")

  # Build files array (shared by both output modes)
  local files_json="[]"
  while IFS= read -r file; do
    local status origin hub_hash local_hash sync_field
    status=$(jq -r --arg f "$file" '.files[$f].status' "$LOCKFILE")
    origin=$(jq -r --arg f "$file" '.files[$f].origin' "$LOCKFILE")
    hub_hash=$(jq -r --arg f "$file" '.files[$f].hub_hash // "null"' "$LOCKFILE")
    local_hash=$(jq -r --arg f "$file" '.files[$f].local_hash // "null"' "$LOCKFILE")
    sync_field=$(get_sync_field "$file")

    # Apply filter
    if [[ -n "$filter_status" ]]; then
      if [[ "$filter_status" == "non-clean" ]]; then
        [[ "$status" == "clean" && "$sync_field" != "node-only" ]] && continue
      else
        [[ "$status" != "$filter_status" ]] && continue
      fi
    fi

    files_json=$(echo "$files_json" | jq --arg f "$file" --arg o "$origin" --arg s "$status" \
      --arg sy "$sync_field" --arg hh "$hub_hash" --arg lh "$local_hash" \
      '. + [{"file": $f, "origin": $o, "status": $s, "sync": $sy, "hub_hash": $hh, "local_hash": $lh}]')
  done < <(jq -r '.files | keys[]' "$LOCKFILE" | sort)

  # JSON output mode
  if $json_mode; then
    jq -n --arg hs "$(get_hub_source_display)" --arg hv "$hub_version" \
      --arg sa "$synced_at" --argjson files "$files_json" \
      '{"hub_source": $hs, "hub_version": $hv, "synced_at": $sa, "files": $files}'
    return 0
  fi

  # Human-readable output mode (original behavior)
  echo "Hub: $(get_hub_source_display) @ $hub_version"
  echo "Last synced: $synced_at"
  echo ""

  # Check if hub has new commits since last sync
  if git -C "$hub_root" rev-parse HEAD >/dev/null 2>&1; then
    local current_hub_version
    current_hub_version=$(git -C "$hub_root" rev-parse --short HEAD)
    if [[ "$current_hub_version" != "$hub_version" ]]; then
      echo "NOTE: Hub has new commits ($hub_version → $current_hub_version)"
      echo ""
    fi
  fi

  # Print each file's status
  local has_output=false
  echo "$files_json" | jq -r '.[] | "\(.status)\t\(.sync)\t\(.file)"' | while IFS=$'\t' read -r status sync_field file; do
    local display_status
    if [[ "$sync_field" == "node-only" ]]; then
      display_status="NODE-ONLY"
    else
      case "$status" in
        clean)        display_status="CLEAN" ;;
        modified)     display_status="MODIFIED" ;;
        local-only)   display_status="LOCAL" ;;
        promoted)     display_status="PROMOTED" ;;
        hub-only)     display_status="HUB-ONLY" ;;
        *)            display_status="UNKNOWN" ;;
      esac
    fi
    printf "  %-16s %s\n" "$display_status" "$file"
    has_output=true
  done

  if [[ "$has_output" == "false" ]]; then
    echo "  No tracked files."
  fi

  echo ""
  echo "Statuses: CLEAN=synced, MODIFIED=locally changed, MODIFIED*=changed since last sync,"
  echo "          LOCAL=project-only, PROMOTED=pushed to hub, HUB-ONLY=not yet pulled,"
  echo "          NODE-ONLY=excluded from sync (use /ccanvil-ignore to set, ccanvil-sync.sh track to undo)"
}

cmd_changelog() {
  require_lockfile
  local hub_root
  hub_root=$(get_hub_source_raw)

  [[ -d "$hub_root" ]] || die "Hub not found at: $hub_root"

  local last_version
  last_version=$(jq -r '.hub_version' "$LOCKFILE")

  local current_version
  current_version=$(git -C "$hub_root" rev-parse --short HEAD)

  # Up-to-date: no new commits
  if [[ "$last_version" == "$current_version" ]]; then
    jq -n --arg from "$last_version" --arg to "$current_version" \
      '{"status":"up-to-date","from":$from,"to":$to,"commit_count":0,"commits":[],"files_changed":[]}'
    return 0
  fi

  # Validate last_version exists in hub repo
  if ! git -C "$hub_root" rev-parse "$last_version" >/dev/null 2>&1; then
    die "Last synced version $last_version not found in hub repo. History may have been rewritten."
  fi

  # Commit log
  local commits_json="[]"
  while IFS=$'\t' read -r hash subject; do
    commits_json=$(echo "$commits_json" | jq --arg h "$hash" --arg s "$subject" \
      '. + [{"hash": $h, "subject": $s}]')
  done < <(git -C "$hub_root" log --format="%h%x09%s" "$last_version".."$current_version")

  local commit_count
  commit_count=$(echo "$commits_json" | jq 'length')

  # Files changed across the range
  local files_json="[]"
  while IFS=$'\t' read -r change_type filepath; do
    files_json=$(echo "$files_json" | jq --arg t "$change_type" --arg f "$filepath" \
      '. + [{"type": $t, "file": $f}]')
  done < <(git -C "$hub_root" diff --name-status "$last_version".."$current_version")

  jq -n --arg from "$last_version" --arg to "$current_version" \
    --argjson count "$commit_count" \
    --argjson commits "$commits_json" --argjson files "$files_json" \
    '{"status":"behind","from":$from,"to":$to,"commit_count":$count,"commits":$commits,"files_changed":$files}'
}

cmd_diff() {
  require_lockfile
  local file="${1:-}"
  local hub_source
  hub_source=$(get_hub_source)

  if [[ -n "$file" ]]; then
    # Diff a specific file
    local hub_file="$hub_source/$file"
    if [[ ! -f "$hub_file" ]]; then
      echo "File not in hub: $file"
      [[ -f "$file" ]] && echo "(exists locally as local-only file)"
      return 0
    fi
    if [[ ! -f "$file" ]]; then
      echo "File not in project: $file"
      echo "(exists in hub — run ccanvil-pull to add it)"
      return 0
    fi
    echo "--- hub: $file"
    echo "+++ local: $file"
    diff --unified "$hub_source/$file" "$file" || true
  else
    # Diff all modified files
    while IFS= read -r f; do
      local status
      status=$(jq -r --arg f "$f" '.files[$f].status' "$LOCKFILE")
      if [[ "$status" == "modified" || "$status" == "clean" ]]; then
        local current_hash
        current_hash=$(file_hash "$f")
        local hub_hash
        hub_hash=$(jq -r --arg f "$f" '.files[$f].hub_hash // "null"' "$LOCKFILE")
        if [[ "$current_hash" != "$hub_hash" && -f "$hub_source/$f" ]]; then
          echo "=== $f ==="
          diff --unified "$hub_source/$f" "$f" || true
          echo ""
        fi
      fi
    done < <(jq -r '.files | keys[]' "$LOCKFILE")
  fi
}

cmd_hash() {
  local file="${1:?Usage: ccanvil-sync.sh hash <file>}"
  echo "$(file_hash "$file")  $file"
}

cmd_lock_get() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh lock-get <file>}"
  jq --arg f "$file" '.files[$f] // "not found"' "$LOCKFILE"
}

cmd_lock_update() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh lock-update <file> <field> <value>}"
  local field="${2:?}"
  local value="${3:?}"

  local tmp
  tmp=$(mktemp)
  if [[ "$value" == "null" ]]; then
    jq --arg f "$file" --arg k "$field" '.files[$f][$k] = null' "$LOCKFILE" > "$tmp" || true
  else
    jq --arg f "$file" --arg k "$field" --arg v "$value" '.files[$f][$k] = $v' "$LOCKFILE" > "$tmp" || true
  fi
  safe_lock_mv "$tmp" "$LOCKFILE" "lock-update $file $field"
}

cmd_lock_add() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh lock-add <file> <origin> <hub_hash> <local_hash> <status>}"
  local origin="${2:?}"
  local hub_hash="${3}"
  local local_hash="${4}"
  local status="${5:?}"

  local tmp
  tmp=$(mktemp)
  if [[ "$hub_hash" == "null" ]]; then
    jq --arg f "$file" --arg o "$origin" --arg lh "$local_hash" --arg st "$status" \
      '.files[$f] = {"origin": $o, "hub_hash": null, "local_hash": $lh, "status": $st}' "$LOCKFILE" > "$tmp" || true
  elif [[ "$local_hash" == "null" ]]; then
    jq --arg f "$file" --arg o "$origin" --arg sh "$hub_hash" --arg st "$status" \
      '.files[$f] = {"origin": $o, "hub_hash": $sh, "local_hash": null, "status": $st}' "$LOCKFILE" > "$tmp" || true
  else
    jq --arg f "$file" --arg o "$origin" --arg sh "$hub_hash" --arg lh "$local_hash" --arg st "$status" \
      '.files[$f] = {"origin": $o, "hub_hash": $sh, "local_hash": $lh, "status": $st}' "$LOCKFILE" > "$tmp" || true
  fi
  safe_lock_mv "$tmp" "$LOCKFILE" "lock-add $file"
}

cmd_lock_remove() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh lock-remove <file>}"

  local tmp
  tmp=$(mktemp)
  jq --arg f "$file" 'del(.files[$f])' "$LOCKFILE" > "$tmp" || true
  safe_lock_mv "$tmp" "$LOCKFILE" "lock-remove $file"
}

cmd_lock_set_version() {
  require_lockfile
  local version="${1:?Usage: ccanvil-sync.sh lock-set-version <version>}"

  local tmp
  tmp=$(mktemp)
  jq --arg v "$version" --arg ts "$(timestamp)" '.hub_version = $v | .synced_at = $ts' "$LOCKFILE" > "$tmp" || true
  safe_lock_mv "$tmp" "$LOCKFILE" "lock-set-version"
}

cmd_section_merge() {
  local hub_file="${1:?Usage: ccanvil-sync.sh section-merge <hub-file> <local-file>}"
  local local_file="${2:?Usage: ccanvil-sync.sh section-merge <hub-file> <local-file>}"

  [[ -f "$hub_file" ]] || die "Hub file not found: $hub_file"
  [[ -f "$local_file" ]] || die "Local file not found: $local_file"

  # Detect which delimiter the hub file uses
  local delimiter=""
  if grep -q '<!-- NODE-SPECIFIC-START -->' "$hub_file"; then
    delimiter="<!-- NODE-SPECIFIC-START -->"
  elif grep -q '<!-- HUB-MANAGED-START -->' "$hub_file"; then
    delimiter="<!-- HUB-MANAGED-START -->"
  else
    # No delimiter in hub file — not a section-merge file
    echo "ERROR: No section delimiter found in hub file" >&2
    return 1
  fi

  if [[ "$delimiter" == "<!-- NODE-SPECIFIC-START -->" ]]; then
    # Pattern: hub content above delimiter, node content below
    # Take ABOVE delimiter from hub, BELOW delimiter from local

    # Get hub content (everything before delimiter) from hub
    sed -n "/$delimiter/q;p" "$hub_file"

    # Get node content (delimiter + everything after) from local
    if grep -q "$delimiter" "$local_file"; then
      sed -n "/$delimiter/,\$p" "$local_file"
    else
      # Local has no delimiter — treat entire local file as node content
      echo "$delimiter"
      echo "<!-- Everything above is managed by the hub and updated via /ccanvil-pull. -->"
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
    # Take ABOVE delimiter from local, BELOW delimiter from hub

    # Get node content (everything before delimiter) from local
    if grep -q "$delimiter" "$local_file"; then
      sed -n "/$delimiter/q;p" "$local_file"
    else
      # Local has no delimiter — treat entire local file as node content
      cat "$local_file"
      echo ""
    fi

    # Get hub content (delimiter + everything after) from hub
    sed -n "/$delimiter/,\$p" "$hub_file"
  fi
}

# ---------------------------------------------------------------------------
# Compound Commands — high-level operations that replace manual orchestration
# ---------------------------------------------------------------------------

# Node-only classification commands
cmd_node_only() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh node-only <file>}"

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
  jq --arg f "$file" '.files[$f].sync = "node-only"' "$LOCKFILE" > "$tmp" || true
  safe_lock_mv "$tmp" "$LOCKFILE" "node-only $file"

  echo "NODE-ONLY: $file (excluded from future pull/push)"
}

cmd_track() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh track <file>}"

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
  jq --arg f "$file" '.files[$f].sync = "tracked"' "$LOCKFILE" > "$tmp" || true
  safe_lock_mv "$tmp" "$LOCKFILE" "track $file"

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

# Pre-check: verify hub repo is clean and accessible
cmd_pre_check() {
  require_lockfile
  local hub_source
  hub_source=$(get_hub_source)
  local hub_root
  hub_root=$(get_hub_source_raw)

  [[ -d "$hub_source" ]] || die "Hub not found at: $hub_source"

  # Check hub repo is clean
  if git -C "$hub_root" rev-parse HEAD >/dev/null 2>&1; then
    local dirty
    dirty=$(git -C "$hub_root" status --porcelain 2>/dev/null)
    if [[ -n "$dirty" ]]; then
      echo "ERROR: Hub repo has uncommitted changes:" >&2
      echo "$dirty" >&2
      echo "" >&2
      echo "Commit or stash changes in $hub_source before syncing." >&2
      exit 1
    fi
  fi

  # Check node (current project) is clean
  if git rev-parse HEAD >/dev/null 2>&1; then
    local node_dirty
    node_dirty=$(git status --porcelain 2>/dev/null)
    if [[ -n "$node_dirty" ]]; then
      echo "ERROR: This project has uncommitted changes:" >&2
      echo "$node_dirty" >&2
      echo "" >&2
      echo "Commit or stash changes before syncing." >&2
      exit 1
    fi
  fi

  # Bootstrap: if the hub has a newer sync script, copy it before proceeding
  local hub_script="$hub_source/.ccanvil/scripts/ccanvil-sync.sh"
  local local_script=".ccanvil/scripts/ccanvil-sync.sh"
  if [[ -f "$hub_script" && -f "$local_script" ]]; then
    local hub_hash local_hash
    hub_hash=$(file_hash "$hub_script")
    local_hash=$(file_hash "$local_script")
    if [[ "$hub_hash" != "$local_hash" ]]; then
      cp "$hub_script" "$local_script"
      # Update lockfile hashes so status shows clean after bootstrap
      local new_hash
      new_hash=$(file_hash "$local_script")
      local tmp; tmp=$(mktemp)
      jq --arg f "$local_script" --arg h "$new_hash" \
        '.files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean"' \
        "$LOCKFILE" > "$tmp" || true
      safe_lock_mv "$tmp" "$LOCKFILE" "bootstrap hash update"
      echo "BOOTSTRAPPED: Updated .ccanvil/scripts/ccanvil-sync.sh from hub"
      echo "  Re-run your command to use the updated script."
      exit 0
    fi
  fi

  echo "OK"
}

# pull-plan: Compute the full pull plan as JSON
# Output: JSON array of {file, action, reason} objects
# Actions: auto-update, section-merge, conflict, new, removed, skip
cmd_pull_plan() {
  require_lockfile
  local hub_source
  hub_source=$(get_hub_source)

  local plan="[]"

  # Check each tracked file in the lockfile
  while IFS= read -r file; do
    local status origin hub_hash local_hash
    status=$(jq -r --arg f "$file" '.files[$f].status' "$LOCKFILE")
    origin=$(jq -r --arg f "$file" '.files[$f].origin' "$LOCKFILE")
    hub_hash=$(jq -r --arg f "$file" '.files[$f].hub_hash // "null"' "$LOCKFILE")
    local_hash=$(jq -r --arg f "$file" '.files[$f].local_hash // "null"' "$LOCKFILE")

    # Skip node-only files (permanently excluded from sync)
    if is_node_only "$file"; then
      continue
    fi

    # Skip local-only files (nothing to pull)
    if [[ "$status" == "local-only" ]]; then
      continue
    fi

    local hub_file="$hub_source/$file"

    # Check if file was removed from hub
    if [[ ! -f "$hub_file" ]]; then
      local clh
      clh=$(file_hash "$file" 2>/dev/null || echo "MISSING")
      plan=$(echo "$plan" | jq --arg f "$file" --arg lh "$clh" \
        '. + [{"file": $f, "action": "removed", "reason": "File no longer exists in hub", "local_hash": $lh}]')
      continue
    fi

    # Compute current hashes
    local current_hub_h current_local_h
    current_hub_h=$(file_hash "$hub_file")
    current_local_h=$(file_hash "$file" 2>/dev/null || echo "MISSING")

    # Has hub changed since last sync?
    local hub_changed=false
    if [[ "$current_hub_h" != "$hub_hash" ]]; then
      hub_changed=true
    fi

    # Has local file changed since last sync?
    local local_changed=false
    if [[ "$current_local_h" != "$local_hash" && "$current_local_h" != "MISSING" ]]; then
      local_changed=true
    fi

    if [[ "$hub_changed" == "false" ]]; then
      # Hub hasn't changed — nothing to pull
      continue
    fi

    if [[ "$current_local_h" == "MISSING" ]]; then
      # File exists in lockfile but not locally (deleted locally)
      plan=$(echo "$plan" | jq --arg f "$file" \
        '. + [{"file": $f, "action": "new", "reason": "File missing locally but exists in hub", "local_hash": "MISSING"}]')
      continue
    fi

    # Hub changed — check if local is clean or modified
    if [[ "$local_changed" == "false" && "$status" != "modified" ]]; then
      # Local is clean — safe to auto-update
      plan=$(echo "$plan" | jq --arg f "$file" --arg lh "$current_local_h" \
        '. + [{"file": $f, "action": "auto-update", "reason": "Hub changed, local is clean", "local_hash": $lh}]')
    else
      # Both sides changed — check for section-merge capability
      # Only markdown files can have section delimiters (avoids false positives
      # in scripts that contain delimiter strings as literals)
      local has_delimiter=false
      if [[ "$file" == *.md ]] && \
         (grep -qx '<!-- NODE-SPECIFIC-START -->' "$hub_file" 2>/dev/null || \
          grep -qx '<!-- HUB-MANAGED-START -->' "$hub_file" 2>/dev/null); then
        has_delimiter=true
      fi

      if [[ "$has_delimiter" == "true" ]]; then
        plan=$(echo "$plan" | jq --arg f "$file" --arg lh "$current_local_h" \
          '. + [{"file": $f, "action": "section-merge", "reason": "Both changed, file has section delimiter", "local_hash": $lh}]')
      else
        plan=$(echo "$plan" | jq --arg f "$file" --arg lh "$current_local_h" \
          '. + [{"file": $f, "action": "conflict", "reason": "Both hub and local have changes", "local_hash": $lh}]')
      fi
    fi
  done < <(jq -r '.files | keys[]' "$LOCKFILE" | sort)

  # Check for new files in hub not in lockfile
  while IFS= read -r file; do
    if ! jq -e --arg f "$file" '.files[$f]' "$LOCKFILE" >/dev/null 2>&1; then
      if [[ -f "$file" ]]; then
        # File exists locally but isn't in lockfile (e.g., manual copy)
        local hub_h local_h
        hub_h=$(file_hash "$hub_source/$file")
        local_h=$(file_hash "$file")
        if [[ "$hub_h" == "$local_h" ]]; then
          plan=$(echo "$plan" | jq --arg f "$file" --arg lh "$local_h" \
            '. + [{"file": $f, "action": "adopt-clean", "reason": "New in hub, identical local copy exists — will track as clean", "local_hash": $lh}]')
        else
          plan=$(echo "$plan" | jq --arg f "$file" --arg lh "$local_h" \
            '. + [{"file": $f, "action": "adopt-conflict", "reason": "New in hub, different local copy exists — needs resolution", "local_hash": $lh}]')
        fi
      else
        plan=$(echo "$plan" | jq --arg f "$file" \
          '. + [{"file": $f, "action": "new", "reason": "New file in hub, not yet tracked", "local_hash": "MISSING"}]')
      fi
    fi
  done < <(scan_hub_files "$hub_source")

  echo "$plan" | jq '.'
}

# pull-auto: Execute all auto-updates in one pass
# Processes only files with action "auto-update" from pull-plan
# Usage: pull-auto [--dry-run]
cmd_pull_auto() {
  local dry_run=false
  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
  fi

  require_lockfile
  local hub_source
  hub_source=$(get_hub_source)

  local count=0
  local plan
  plan=$(cmd_pull_plan)

  # Also adopt-clean files (identical local copies not yet in lockfile)
  echo "$plan" | jq -r '.[] | select(.action == "auto-update" or .action == "adopt-clean") | .file' | while IFS= read -r file; do
    if $dry_run; then
      echo "DRY-RUN: would copy $file"
      count=$((count + 1))
      continue
    fi

    local hub_file="$hub_source/$file"
    local new_hash
    new_hash=$(file_hash "$hub_file")

    # Ensure target directory exists
    mkdir -p "$(dirname "$file")"

    # Copy hub version
    cp "$hub_file" "$file"

    # Update lockfile in one pass (works for both existing and new entries)
    local tmp
    tmp=$(mktemp)
    jq --arg f "$file" --arg h "$new_hash" \
      '.files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean" | .files[$f].origin = "hub" | .files[$f].sync = "tracked"' \
      "$LOCKFILE" > "$tmp" || true
    safe_lock_mv "$tmp" "$LOCKFILE" "pull-auto $file"

    # Log
    count=$((count + 1))
    echo "AUTO-UPDATED: $file"
  done

  echo "---"
  if $dry_run; then
    echo "Dry-run complete. No files were modified."
  else
    echo "Auto-updated files complete."
  fi
}

# pull-apply: Apply a specific resolution for a single file
# Usage: pull-apply <file> <action> [merged-content-file] [--dry-run]
# Actions: take-hub, keep-local, section-merge, accept-new, adopt-conflict, delete, write-merged <path>
cmd_pull_apply() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh pull-apply <file> <action> [merged-content-file]}"
  local action="${2:?}"
  local merged_file=""
  local dry_run=false

  # Parse remaining args — could be merged_file and/or --dry-run
  shift 2
  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
      dry_run=true
    else
      merged_file="$arg"
    fi
  done

  local hub_source
  hub_source=$(get_hub_source)
  local hub_file="$hub_source/$file"

  # Guard: if PLAN_LOCAL_HASH is set, verify file hasn't changed since plan
  if [[ -n "${PLAN_LOCAL_HASH:-}" && -f "$file" ]]; then
    local current_hash
    current_hash=$(file_hash "$file")
    if [[ "$current_hash" != "$PLAN_LOCAL_HASH" ]]; then
      guard_fail "cp" "$file" "file changed after plan (expected $PLAN_LOCAL_HASH, got $current_hash)"
    fi
  fi

  # Dry-run: describe action without executing
  if $dry_run; then
    echo "DRY-RUN: would $action $file"
    return 0
  fi

  case "$action" in
    take-hub)
      [[ -f "$hub_file" ]] || die "Hub file not found: $hub_file"
      mkdir -p "$(dirname "$file")"
      cp "$hub_file" "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg h "$new_hash" \
        '.files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean"' \
        "$LOCKFILE" > "$tmp" || true
      safe_lock_mv "$tmp" "$LOCKFILE" "pull-apply take-hub $file"
      echo "APPLIED: $file (took hub)"
      ;;

    keep-local)
      # Update hub_hash to acknowledge we've seen the change, keep local as-is
      local new_hub_hash
      new_hub_hash=$(file_hash "$hub_file")
      local current_local_hash
      current_local_hash=$(file_hash "$file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg sh "$new_hub_hash" --arg lh "$current_local_hash" \
        '.files[$f].hub_hash = $sh | .files[$f].local_hash = $lh | .files[$f].status = "modified"' \
        "$LOCKFILE" > "$tmp" || true
      safe_lock_mv "$tmp" "$LOCKFILE" "pull-apply keep-local $file"
      echo "APPLIED: $file (kept local)"
      ;;

    section-merge)
      [[ -f "$hub_file" ]] || die "Hub file not found: $hub_file"
      [[ -f "$file" ]] || die "Local file not found: $file"
      local merged
      merged=$(cmd_section_merge "$hub_file" "$file")
      echo "$merged" > "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      local new_hub_hash
      new_hub_hash=$(file_hash "$hub_file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg sh "$new_hub_hash" --arg lh "$new_hash" \
        '.files[$f].hub_hash = $sh | .files[$f].local_hash = $lh | .files[$f].status = "clean"' \
        "$LOCKFILE" > "$tmp" || true
      safe_lock_mv "$tmp" "$LOCKFILE" "pull-apply section-merge $file"
      echo "APPLIED: $file (section-merged)"
      ;;

    adopt-conflict)
      # File exists locally with different content and isn't in lockfile yet.
      # Same as take-hub but adds a new lockfile entry.
      [[ -f "$hub_file" ]] || die "Hub file not found: $hub_file"
      mkdir -p "$(dirname "$file")"
      cp "$hub_file" "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      cmd_lock_add "$file" "hub" "$new_hash" "$new_hash" "clean"
      echo "APPLIED: $file (adopted — took hub)"
      ;;

    accept-new)
      [[ -f "$hub_file" ]] || die "Hub file not found: $hub_file"
      if [[ -f "$file" ]]; then
        echo "WARNING: $file already exists locally. Use 'take-hub', 'adopt-conflict', or 'section-merge' instead." >&2
        die "Refusing to overwrite existing file with accept-new. File: $file"
      fi
      mkdir -p "$(dirname "$file")"
      cp "$hub_file" "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      # Add new lockfile entry
      cmd_lock_add "$file" "hub" "$new_hash" "$new_hash" "clean"
      echo "APPLIED: $file (accepted new)"
      ;;

    delete)
      # Guard: if PLAN_LOCAL_STATUS is set, verify lockfile status hasn't changed
      if [[ -n "${PLAN_LOCAL_STATUS:-}" ]]; then
        local current_status
        current_status=$(jq -r --arg f "$file" '.files[$f].status // "unknown"' "$LOCKFILE")
        if [[ "$current_status" != "$PLAN_LOCAL_STATUS" ]]; then
          guard_fail "rm" "$file" "lockfile status changed after plan (expected $PLAN_LOCAL_STATUS, got $current_status)"
        fi
      fi
      if [[ -f "$file" ]]; then
        rm "$file"
      fi
      cmd_lock_remove "$file"
      echo "APPLIED: $file (deleted)"
      ;;

    write-merged)
      [[ -n "$merged_file" ]] || die "Usage: pull-apply <file> write-merged <merged-content-file>"
      [[ -f "$merged_file" ]] || die "Merged content file not found: $merged_file"
      mkdir -p "$(dirname "$file")"
      cp "$merged_file" "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      local new_hub_hash
      new_hub_hash=$(file_hash "$hub_file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg sh "$new_hub_hash" --arg lh "$new_hash" \
        '.files[$f].hub_hash = $sh | .files[$f].local_hash = $lh | .files[$f].status = "modified"' \
        "$LOCKFILE" > "$tmp" || true
      safe_lock_mv "$tmp" "$LOCKFILE" "pull-apply write-merged $file"
      echo "APPLIED: $file (merged)"
      ;;

    *)
      die "Unknown action: $action. Use: take-hub, keep-local, section-merge, accept-new, delete, write-merged"
      ;;
  esac
}

# pull-finalize: Update version, commit all changes, output summary
# Usage: pull-finalize [--dry-run]
cmd_pull_finalize() {
  local dry_run=false
  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
  fi

  require_lockfile
  local hub_source
  hub_source=$(get_hub_source)
  local hub_root
  hub_root=$(get_hub_source_raw)

  local new_version
  if git -C "$hub_root" rev-parse HEAD >/dev/null 2>&1; then
    new_version=$(git -C "$hub_root" rev-parse --short HEAD)
  else
    new_version="unknown"
  fi

  if ! $dry_run; then
    cmd_lock_set_version "$new_version"
  fi

  # Build commit message from changed files
  if git rev-parse HEAD >/dev/null 2>&1; then
    local changed_files
    changed_files=$(git diff --name-only 2>/dev/null)
    local staged_files
    staged_files=$(git diff --cached --name-only 2>/dev/null)

    # Combine staged and unstaged changes
    local all_changes
    all_changes=$(printf '%s\n%s' "$changed_files" "$staged_files" | sort -u | grep -v '^$')

    if [[ -n "$all_changes" ]]; then
      local file_count
      file_count=$(echo "$all_changes" | wc -l | tr -d ' ')

      local display_source
      display_source=$(get_hub_source_display)

      if $dry_run; then
        echo "DRY-RUN: would commit $file_count files"
        echo "DRY-RUN: commit message: chore(sync): pull from hub @ $new_version"
        while IFS= read -r f; do
          echo "DRY-RUN:   - $f"
        done <<< "$all_changes"
      else
        local commit_body=""
        commit_body+="Hub source: $display_source @ $new_version"$'\n'
        commit_body+=""$'\n'
        commit_body+="Files synced ($file_count):"$'\n'
        while IFS= read -r f; do
          commit_body+="  - $f"$'\n'
        done <<< "$all_changes"

        local head_before
        head_before=$(git rev-parse HEAD)
        git add -A
        git commit -m "chore(sync): pull from hub @ $new_version" -m "$commit_body" \
          || true
        local head_after
        head_after=$(git rev-parse HEAD)
        if [[ "$head_before" != "$head_after" ]]; then
          echo "Committed: $(git rev-parse --short HEAD)"
        else
          echo "WARNING: git commit produced no new commit despite $file_count changed files." >&2
        fi
      fi
    else
      echo "No file changes to commit."
    fi
  fi

  if $dry_run; then
    echo "DRY-RUN: pull-finalize complete. No changes applied."
  else
    echo "Pull finalized. Hub version: $new_version"
  fi
}

# push-candidates: List files eligible for push with current state
# Output: JSON array of {file, status, has_diff, first_lines}
cmd_push_candidates() {
  require_lockfile
  local hub_source
  hub_source=$(get_hub_source)
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
    local hub_file="$hub_source/$file"
    if [[ -f "$hub_file" ]]; then
      if ! diff -q "$hub_file" "$file" >/dev/null 2>&1; then
        has_diff="true"
      fi
    fi

    candidates=$(echo "$candidates" | jq --arg f "$file" --arg s "$status" --arg d "$has_diff" \
      '. + [{"file": $f, "status": $s, "has_diff": ($d == "true")}]')
  done < <(jq -r '.files | keys[]' "$LOCKFILE" | sort)

  echo "$candidates" | jq '.'
}

# push-apply: Push a single file to the hub
# Usage: push-apply <file> [description] [--dry-run]
cmd_push_apply() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh push-apply <file> [description]}"
  local description=""
  local dry_run=false

  # Parse remaining args
  shift
  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
      dry_run=true
    elif [[ -z "$description" ]]; then
      description="$arg"
    fi
  done
  [[ -n "$description" ]] || description="updated $file"

  local hub_source
  hub_source=$(get_hub_source)
  local status
  status=$(jq -r --arg f "$file" '.files[$f].status // "unknown"' "$LOCKFILE")

  [[ -f "$file" ]] || die "File not found: $file"

  if $dry_run; then
    echo "DRY-RUN: would push $file ($status)"
    return 0
  fi

  # Ensure target directory exists in hub
  mkdir -p "$(dirname "$hub_source/$file")"

  # Copy to hub
  cp "$file" "$hub_source/$file"

  # Update lockfile based on current status
  local new_hash
  new_hash=$(file_hash "$file")

  local tmp; tmp=$(mktemp)
  if [[ "$status" == "local-only" ]]; then
    # Promoting: update origin and status
    jq --arg f "$file" --arg h "$new_hash" \
      '.files[$f].origin = "hub" | .files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "promoted"' \
      "$LOCKFILE" > "$tmp" || true
  else
    # Modified → synced: update hashes and status
    jq --arg f "$file" --arg h "$new_hash" \
      '.files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean"' \
      "$LOCKFILE" > "$tmp" || true
  fi
  safe_lock_mv "$tmp" "$LOCKFILE" "push-apply $file"

  echo "PUSHED: $file ($status → pushed)"
}

# push-finalize: Commit in hub repo, update version
# Usage: push-finalize <commit-message> [--dry-run]
cmd_push_finalize() {
  require_lockfile
  local message=""
  local dry_run=false

  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
      dry_run=true
    elif [[ -z "$message" ]]; then
      message="$arg"
    fi
  done
  [[ -n "$message" ]] || die "Usage: ccanvil-sync.sh push-finalize <commit-message>"

  local hub_source
  hub_source=$(get_hub_source)
  local hub_root
  hub_root=$(get_hub_source_raw)

  if $dry_run; then
    echo "DRY-RUN: would commit in hub with message: $message"
    echo "DRY-RUN: push-finalize complete. No changes applied."
    return 0
  fi

  # Stage and commit in hub
  local head_before
  head_before=$(git -C "$hub_root" rev-parse HEAD)
  git -C "$hub_root" add -A
  git -C "$hub_root" commit -m "$message" || true
  local head_after
  head_after=$(git -C "$hub_root" rev-parse HEAD)
  if [[ "$head_before" != "$head_after" ]]; then
    echo "Committed in hub: $(git -C "$hub_root" rev-parse --short HEAD)"
  else
    echo "WARNING: git commit in hub produced no new commit." >&2
  fi

  # Update version
  local new_version
  if git -C "$hub_root" rev-parse HEAD >/dev/null 2>&1; then
    new_version=$(git -C "$hub_root" rev-parse --short HEAD)
  else
    new_version="unknown"
  fi

  cmd_lock_set_version "$new_version"

  echo "Push finalized. Hub version: $new_version"
}

# promote: Full promote workflow for a single file
# Usage: promote <file>
cmd_promote() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh promote <file>}"

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

  local hub_source
  hub_source=$(get_hub_source)
  local hub_root
  hub_root=$(get_hub_source_raw)

  # Copy to hub
  mkdir -p "$(dirname "$hub_source/$file")"
  cp "$file" "$hub_source/$file"

  # Update lockfile
  local new_hash
  new_hash=$(file_hash "$file")
  local tmp; tmp=$(mktemp)
  jq --arg f "$file" --arg h "$new_hash" \
    '.files[$f].origin = "hub" | .files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "promoted"' \
    "$LOCKFILE" > "$tmp" || true
  safe_lock_mv "$tmp" "$LOCKFILE" "promote $file"

  # Commit in hub
  git -C "$hub_root" add -A
  git -C "$hub_root" commit -m "chore(sync): add $(basename "$file") from $(basename "$(pwd)")"

  # Update version
  local new_version
  new_version=$(git -C "$hub_root" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  cmd_lock_set_version "$new_version"

  echo "PROMOTED: $file → hub @ $new_version"
}

# demote: Full demote workflow for a single file
# Usage: demote <file>
cmd_demote() {
  require_lockfile
  local file="${1:?Usage: ccanvil-sync.sh demote <file>}"

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
  jq --arg f "$file" '.files[$f].status = "modified"' "$LOCKFILE" > "$tmp" || true
  safe_lock_mv "$tmp" "$LOCKFILE" "demote $file"

  # Log

  echo "DEMOTED: $file (future pulls will show diff instead of auto-updating)"
}

cmd_scan() {
  echo "Tracked files in project:"
  scan_tracked_files | while IFS= read -r f; do
    echo "  $f"
  done

  if [[ -f "$LOCKFILE" ]]; then
    local hub_source
    hub_source=$(get_hub_source)
    echo ""
    echo "Tracked files in hub ($hub_source):"
    scan_hub_files "$hub_source" | while IFS= read -r f; do
      echo "  $f"
    done
  fi
}

# migrate: Copy all hub-managed files to the current project, handle renames, re-init lockfile.
# Usage: migrate <hub-path> [--dry-run]
cmd_migrate() {
  local hub_path="${1:?Usage: ccanvil-sync.sh migrate <hub-path> [--dry-run]}"
  hub_path="${hub_path/#\~/$HOME}"
  local dry_run=false
  [[ "${2:-}" == "--dry-run" ]] && dry_run=true

  # Warn: migrate is destructive for non-delimited files
  if ! $dry_run; then
    echo "WARNING: migrate overwrites non-delimited files (scripts, JSON, hooks) without conflict check." >&2
    echo "  For routine updates, use: pre-check → pull-plan → pull-auto → pull-finalize" >&2
    echo "  Migrate is intended for first-time setup or major restructuring only." >&2
    echo "" >&2
  fi

  [[ -d "$hub_path" ]] || die "Hub not found at: $hub_path"

  local dist_root
  dist_root="$hub_path"

  # Remove stale-named files from previous structure
  local stale_files=(
    ".ccanvil/guide/scaffold-sync.md"
    ".ccanvil/guide/scaffold-framework.md"
    ".ccanvil/templates/scaffold.json.md"
  )
  for stale in "${stale_files[@]}"; do
    if [[ -f "$stale" ]]; then
      if $dry_run; then
        echo "DRY-RUN: would remove stale file $stale"
      else
        rm "$stale"
        echo "REMOVED: $stale (stale name)"
      fi
    fi
  done

  # Rename scaffold.json → ccanvil.json if present
  if [[ -f ".claude/scaffold.json" ]]; then
    if $dry_run; then
      echo "DRY-RUN: would rename .claude/scaffold.json → .claude/ccanvil.json"
    else
      mv ".claude/scaffold.json" ".claude/ccanvil.json"
      echo "RENAMED: .claude/scaffold.json → .claude/ccanvil.json"
    fi
  fi

  # Copy all hub-managed files
  local count=0
  while IFS= read -r file; do
    local hub_file="$dist_root/$file"
    [[ -f "$hub_file" ]] || continue

    if $dry_run; then
      echo "DRY-RUN: would copy $file"
      count=$((count + 1))
      continue
    fi

    # For delimited markdown files, use section-merge to preserve node content
    if [[ "$file" == *.md ]] && [[ -f "$file" ]] && \
       (grep -qx '<!-- NODE-SPECIFIC-START -->' "$hub_file" 2>/dev/null || \
        grep -qx '<!-- HUB-MANAGED-START -->' "$hub_file" 2>/dev/null); then
      local merged
      merged=$(cmd_section_merge "$hub_file" "$file" 2>/dev/null) && {
        echo "$merged" > "$file"
        echo "MERGED: $file (section-merge)"
        count=$((count + 1))
        continue
      }
    fi

    # Plain copy for non-delimited files or new files
    mkdir -p "$(dirname "$file")"
    cp "$hub_file" "$file"
    echo "COPIED: $file"
    count=$((count + 1))
  done < <(scan_hub_files "$hub_path")

  if $dry_run; then
    echo ""
    echo "DRY-RUN: would copy $count files. No changes made."
    return 0
  fi

  echo ""
  echo "MIGRATE: copied $count files from hub."

  # Re-init lockfile
  cmd_init "$hub_path"
  echo ""
  echo "MIGRATE complete. Run 'git add -A && git commit' to finalize."
}

# register: Add the current project to the hub's registry.
# Run from a downstream project. Reads hub path from lockfile.
cmd_register() {
  require_lockfile
  local hub_root
  hub_root=$(get_hub_source_raw)
  local registry="$hub_root/.ccanvil/registry.json"
  local node_path
  node_path=$(pwd)
  local node_name
  node_name=$(basename "$node_path")
  local ts
  ts=$(timestamp)

  # Ensure node UUID exists
  local node_uuid
  node_uuid=$(get_or_create_node_uuid)
  persist_node_uuid "$node_uuid"

  # Normalize path to ~-form for portability
  local portable_path
  portable_path=$(normalize_path "$node_path")

  # Create registry file if it doesn't exist
  if [[ ! -f "$registry" ]]; then
    mkdir -p "$(dirname "$registry")"
    echo '{"nodes":{}}' > "$registry"
  fi

  # Key by UUID. Update existing entry if present (preserve last_synced fields).
  local tmp; tmp=$(mktemp)
  jq --arg u "$node_uuid" --arg p "$portable_path" --arg n "$node_name" --arg t "$ts" \
    '.nodes[$u] = ((.nodes[$u] // {}) + {"name": $n, "path": $p, "registered_at": $t})' \
    "$registry" > "$tmp" || true
  if [[ -s "$tmp" ]] && jq empty "$tmp" 2>/dev/null; then
    mv "$tmp" "$registry"
  else
    rm -f "$tmp"
    die "Failed to update registry"
  fi

  echo "REGISTERED: $node_name ($portable_path) [$node_uuid]"

  # Auto-commit the registry mutation so the hub stays clean (AC-1, AC-6)
  commit_hub_file "$hub_root" ".ccanvil/registry.json" \
    "chore(registry): register $node_name [$node_uuid]"
}

# registry: List all registered downstream projects.
# Can be run from anywhere with a lockfile.
cmd_registry() {
  require_lockfile
  local hub_root
  hub_root=$(get_hub_source_raw)
  local registry="$hub_root/.ccanvil/registry.json"

  if [[ ! -f "$registry" ]]; then
    echo "No registry found. Run 'ccanvil-sync.sh register' from a downstream project."
    return 0
  fi

  echo "Registered downstream projects:"
  echo ""
  jq -r '.nodes | to_entries[] | "  \(.value.name) [\(.key)]\n    path: \(.value.path // .key)\n    registered: \(.value.registered_at)  |  last_synced: \(.value.last_synced // "never")  |  version: \(.value.last_synced_version // "never")"' "$registry"
}

# broadcast: Push hub updates to all registered downstream nodes.
# Runs deterministic phases only (auto-update, section-merge, finalize).
# Conflicts are collected and reported, not resolved.
# Usage: broadcast [--dry-run]
cmd_broadcast() {
  local dry_run=false
  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
  fi

  # Find hub root: if we have a lockfile, use it; otherwise assume current dir is hub
  local hub_root
  if [[ -f "$LOCKFILE" ]]; then
    hub_root=$(get_hub_source_raw)
  else
    hub_root=$(pwd)
  fi

  local registry="$hub_root/.ccanvil/registry.json"
  if [[ ! -f "$registry" ]]; then
    echo "No registered nodes. Run 'ccanvil-sync.sh register' from a downstream project."
    return 0
  fi

  local node_count
  node_count=$(jq '.nodes | length' "$registry")
  if [[ "$node_count" -eq 0 ]]; then
    echo "No registered nodes."
    return 0
  fi

  local synced=0 skipped=0 unreachable=0
  local skip_reasons=""
  local all_conflicts=""
  local synced_uuids=""
  local hub_version
  hub_version=$(git -C "$hub_root" rev-parse --short HEAD 2>/dev/null || echo "unknown")

  # Migrate legacy path-keyed entries to UUID-keyed (AC-7, AC-8).
  # Idempotent — entries already keyed by UUID are skipped.
  migrate_registry "$registry"

  # Auto-commit any migration changes so the hub stays clean during the loop (AC-3, AC-7)
  if ! $dry_run; then
    commit_hub_file "$hub_root" ".ccanvil/registry.json" \
      "chore(registry): migrate to UUID keys"
  fi

  # Iterate over all registered nodes (keyed by UUID post-migration)
  while IFS= read -r entry_key; do
    local node_uuid node_name portable_path node_path

    if [[ "$entry_key" =~ $UUID_V4_REGEX ]]; then
      # UUID-keyed entry
      node_uuid="$entry_key"
      node_name=$(jq -r --arg u "$node_uuid" '.nodes[$u].name // "unknown"' "$registry")
      portable_path=$(jq -r --arg u "$node_uuid" '.nodes[$u].path // empty' "$registry")
    else
      # Legacy path-keyed entry that migration couldn't handle (node missing)
      node_uuid=""
      node_name=$(jq -r --arg p "$entry_key" '.nodes[$p].name // "unknown"' "$registry")
      portable_path="$entry_key"
    fi
    node_path=$(expand_path "$portable_path")

    echo ""
    echo "=== $node_name ($node_path) ==="

    # AC-6: Detect stale paths
    if [[ -z "$portable_path" ]] || [[ ! -d "$node_path" ]]; then
      if [[ -n "$node_uuid" ]]; then
        echo "  STALE: $node_name ($node_uuid) at $portable_path"
        skip_reasons+="  $node_name: STALE ($node_uuid) — path $portable_path no longer exists"$'\n'
      else
        echo "  SKIP: path does not exist"
        skip_reasons+="  $node_name: path does not exist"$'\n'
      fi
      unreachable=$((unreachable + 1))
      continue
    fi

    # AC-2: run pre-check in node subshell
    local precheck_out
    precheck_out=$(cd "$node_path" && bash "$node_path/.ccanvil/scripts/ccanvil-sync.sh" pre-check 2>&1) || {
      echo "  SKIP: pre-check failed"
      echo "  $precheck_out" | head -5
      skipped=$((skipped + 1))
      skip_reasons+="  $node_name: pre-check failed"$'\n'
      continue
    }

    # Handle bootstrap: if pre-check printed BOOTSTRAPPED, commit the
    # bootstrapped files (sync script + lockfile) so the working tree is
    # clean, then re-run pre-check.
    if echo "$precheck_out" | grep -q "^BOOTSTRAPPED:"; then
      echo "  Bootstrapped sync script — committing..."
      if ! $dry_run; then
        # Only add files that aren't gitignored (AC-5).
        # Some nodes gitignore the lockfile — still sync them, just skip that file.
        local bootstrap_files=()
        if ! (cd "$node_path" && git check-ignore -q .ccanvil/scripts/ccanvil-sync.sh 2>/dev/null); then
          bootstrap_files+=(".ccanvil/scripts/ccanvil-sync.sh")
        fi
        if ! (cd "$node_path" && git check-ignore -q .ccanvil/ccanvil.lock 2>/dev/null); then
          bootstrap_files+=(".ccanvil/ccanvil.lock")
        fi

        if [[ ${#bootstrap_files[@]} -gt 0 ]]; then
          (cd "$node_path" && \
            git add "${bootstrap_files[@]}" && \
            git commit -m "chore(sync): bootstrap sync script from hub @ $hub_version" \
              --no-gpg-sign --quiet 2>&1) | sed 's/^/  /' || true
        else
          echo "  (all bootstrap files gitignored — skipping commit)"
        fi
      fi
      echo "  Re-checking..."
      precheck_out=$(cd "$node_path" && bash "$node_path/.ccanvil/scripts/ccanvil-sync.sh" pre-check 2>&1) || {
        echo "  SKIP: pre-check failed after bootstrap"
        skipped=$((skipped + 1))
        skip_reasons+="  $node_name: pre-check failed after bootstrap"$'\n'
        continue
      }
    fi

    # Run pull-plan to classify changes
    local plan
    plan=$(cd "$node_path" && bash "$node_path/.ccanvil/scripts/ccanvil-sync.sh" pull-plan 2>/dev/null) || {
      echo "  SKIP: pull-plan failed"
      skipped=$((skipped + 1))
      skip_reasons+="  $node_name: pull-plan failed"$'\n'
      continue
    }

    local plan_count
    plan_count=$(echo "$plan" | jq 'length')

    if [[ "$plan_count" -eq 0 ]]; then
      echo "  Already up to date."
      synced=$((synced + 1))
      synced_uuids+="$node_uuid"$'\n'
      continue
    fi

    # Collect conflicts for reporting (AC-3)
    local conflicts
    conflicts=$(echo "$plan" | jq -r '.[] | select(.action == "conflict" or .action == "adopt-conflict" or .action == "new" or .action == "removed") | .file')
    if [[ -n "$conflicts" ]]; then
      all_conflicts+="  $node_name:"$'\n'
      while IFS= read -r cfile; do
        local caction
        caction=$(echo "$plan" | jq -r --arg f "$cfile" '.[] | select(.file == $f) | .action')
        all_conflicts+="    - $cfile ($caction)"$'\n'
      done <<< "$conflicts"
    fi

    # Run deterministic phases: pull-auto (handles auto-update + adopt-clean)
    local dry_flag=""
    if $dry_run; then
      dry_flag="--dry-run"
    fi

    local auto_count
    auto_count=$(echo "$plan" | jq '[.[] | select(.action == "auto-update" or .action == "adopt-clean")] | length')
    if [[ "$auto_count" -gt 0 ]]; then
      echo "  Auto-updating $auto_count files..."
      (cd "$node_path" && bash "$node_path/.ccanvil/scripts/ccanvil-sync.sh" pull-auto $dry_flag 2>&1) | sed 's/^/  /'
    fi

    # Run section-merges
    local merge_files
    merge_files=$(echo "$plan" | jq -r '.[] | select(.action == "section-merge") | .file')
    if [[ -n "$merge_files" ]]; then
      while IFS= read -r mfile; do
        echo "  Section-merging: $mfile"
        (cd "$node_path" && bash "$node_path/.ccanvil/scripts/ccanvil-sync.sh" pull-apply "$mfile" section-merge $dry_flag 2>&1) | sed 's/^/  /'
      done <<< "$merge_files"
    fi

    # Finalize (commit changes, update version)
    # In dry-run, pull-finalize may exit non-zero when no files changed (grep -v returns 1).
    # Use || true to prevent pipefail from killing broadcast.
    (cd "$node_path" && bash "$node_path/.ccanvil/scripts/ccanvil-sync.sh" pull-finalize $dry_flag 2>&1) | sed 's/^/  /' || true

    synced=$((synced + 1))
    synced_uuids+="$node_uuid"$'\n'

  done < <(jq -r '.nodes | keys[]' "$registry")

  # Batch-update registry after all nodes are processed.
  # Doing this after the loop prevents registry.json modifications from
  # dirtying the hub mid-broadcast (which would fail pre-check for later nodes).
  if ! $dry_run && [[ -n "$synced_uuids" ]]; then
    local sync_ts
    sync_ts=$(timestamp)
    while IFS= read -r su; do
      [[ -z "$su" ]] && continue
      local tmp; tmp=$(mktemp)
      jq --arg u "$su" --arg t "$sync_ts" --arg v "$hub_version" \
        '.nodes[$u].last_synced = $t | .nodes[$u].last_synced_version = $v' \
        "$registry" > "$tmp" || true
      if [[ -s "$tmp" ]] && jq empty "$tmp" 2>/dev/null; then
        mv "$tmp" "$registry"
      else
        rm -f "$tmp"
      fi
    done <<< "$synced_uuids"

    # Auto-commit the last_synced updates (AC-4, AC-7)
    commit_hub_file "$hub_root" ".ccanvil/registry.json" \
      "chore(registry): record broadcast sync @ $hub_version"
  fi

  # AC-9: Summary
  echo ""
  echo "=== Broadcast Summary ==="
  echo "  Synced: $synced"
  echo "  Skipped: $skipped"
  echo "  Unreachable: $unreachable"

  if [[ -n "$skip_reasons" ]]; then
    echo ""
    echo "Skip reasons:"
    echo "$skip_reasons"
  fi

  if [[ -n "$all_conflicts" ]]; then
    echo ""
    echo "Conflicts pending (manual resolution needed):"
    echo "$all_conflicts"
  fi

  if $dry_run; then
    echo ""
    echo "DRY-RUN: No files were modified in any node."
  fi
}

# ---------------------------------------------------------------------------
# Stack commands
# ---------------------------------------------------------------------------

cmd_pull_globals() {
  local force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      *) shift ;;
    esac
  done

  [[ -n "${HOME:-}" ]] || die "\$HOME is not set"

  require_lockfile
  local hub_path
  hub_path=$(get_hub_source)
  local src_dir="$hub_path/global-commands"
  local dst_dir="$HOME/.claude/commands"

  mkdir -p "$dst_dir"

  local copied=0 skipped=0 conflicts=0

  # Iterate only ccanvil-*.md — user namespace is sacrosanct (AC-6)
  shopt -s nullglob
  local src
  for src in "$src_dir"/ccanvil-*.md; do
    [[ -f "$src" ]] || continue
    local name dst
    name=$(basename "$src")
    dst="$dst_dir/$name"

    if [[ ! -f "$dst" ]]; then
      cp "$src" "$dst"
      copied=$((copied + 1))
      continue
    fi

    local hub_h local_h
    hub_h=$(file_hash "$src")
    local_h=$(file_hash "$dst")

    if [[ "$hub_h" == "$local_h" ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    # Hashes differ — conflict
    if $force; then
      cp "$src" "$dst"
      copied=$((copied + 1))
    else
      echo "CONFLICT: $name (local differs from hub)" >&2
      diff -u "$dst" "$src" >&2 || true
      conflicts=$((conflicts + 1))
    fi
  done
  shopt -u nullglob

  jq -n --argjson c "$copied" --argjson s "$skipped" --argjson x "$conflicts" \
    '{copied: $c, skipped: $s, conflicts: $x}'
}

cmd_stack_list() {
  require_lockfile
  local hub_path
  hub_path=$(get_hub_source)
  local stacks_dir="$hub_path/hub/stacks"

  if [[ ! -d "$stacks_dir" ]]; then
    echo "[]"
    return 0
  fi

  local result="[]"
  for manifest in "$stacks_dir"/*/manifest.json; do
    [[ -f "$manifest" ]] || continue
    local entry
    entry=$(jq '{id: .id, description: .description, files: [.files[].target]}' "$manifest")
    result=$(echo "$result" | jq --argjson e "$entry" '. + [$e]')
  done
  echo "$result"
}

cmd_stack_apply() {
  local stack_id="${1:?Usage: ccanvil-sync.sh stack-apply <stack-id>}"
  require_lockfile
  local hub_path
  hub_path=$(get_hub_source)
  local stack_dir="$hub_path/hub/stacks/$stack_id"
  local manifest="$stack_dir/manifest.json"

  [[ -f "$manifest" ]] || die "Stack not found: $stack_id (no manifest at $manifest)"

  local copied=0 skipped=0 errors=0

  # --- File copy flow (AC-3) ---
  local file_count
  file_count=$(jq '.files | length' "$manifest")
  for i in $(seq 0 $((file_count - 1))); do
    local source target action
    source=$(jq -r ".files[$i].source" "$manifest")
    target=$(jq -r ".files[$i].target" "$manifest")
    action=$(jq -r ".files[$i].action" "$manifest")

    local source_path="$stack_dir/$source"
    [[ -f "$source_path" ]] || { echo "WARNING: Missing source: $source" >&2; errors=$((errors + 1)); continue; }

    case "$action" in
      copy)
        if [[ -f "$target" ]]; then
          # Patch flow (AC-4): skip if local file was customized
          local hub_h local_h
          hub_h=$(file_hash "$source_path")
          local_h=$(file_hash "$target")
          local lock_hub_h
          lock_hub_h=$(jq -r --arg f "$target" '.files[$f].hub_hash // empty' "$LOCKFILE" 2>/dev/null || true)
          if [[ -n "$lock_hub_h" && "$local_h" != "$lock_hub_h" && "$hub_h" == "$lock_hub_h" ]]; then
            # Local was customized and hub hasn't changed — skip
            skipped=$((skipped + 1))
            continue
          elif [[ "$hub_h" == "$local_h" ]]; then
            skipped=$((skipped + 1))
            continue
          fi
        fi
        mkdir -p "$(dirname "$target")"
        cp "$source_path" "$target"
        # Preserve executable bit
        [[ -x "$source_path" ]] && chmod +x "$target"
        copied=$((copied + 1))
        ;;
      *)
        echo "WARNING: Unknown action '$action' for $source" >&2
        errors=$((errors + 1))
        continue
        ;;
    esac

    # Update lockfile entry (AC-7)
    local hub_h local_h
    hub_h=$(file_hash "$source_path")
    local_h=$(file_hash "$target")
    bash "$0" lock-add "$target" "stack:$stack_id" "$hub_h" "$local_h" "clean"
  done

  # --- CLAUDE.md section merge (AC-3, AC-4) ---
  local section_file
  section_file=$(jq -r '.claudemd_section // empty' "$manifest")
  if [[ -n "$section_file" && -f "$stack_dir/$section_file" ]]; then
    local section_content
    section_content=$(cat "$stack_dir/$section_file")
    local start_marker="<!-- STACK:${stack_id}-START -->"
    local end_marker="<!-- STACK:${stack_id}-END -->"

    if [[ -f "CLAUDE.md" ]]; then
      local section_tmp
      section_tmp=$(mktemp)
      echo "$section_content" > "$section_tmp"

      if grep -q "$start_marker" "CLAUDE.md"; then
        # Update existing section (idempotent)
        local tmp
        tmp=$(mktemp)
        awk -v start="$start_marker" -v end="$end_marker" -v sfile="$section_tmp" '
          $0 == start { while ((getline line < sfile) > 0) print line; close(sfile); skip=1; next }
          $0 == end { skip=0; next }
          !skip { print }
        ' "CLAUDE.md" > "$tmp"
        mv "$tmp" "CLAUDE.md"
      elif grep -q '<!-- HUB-MANAGED-START -->' "CLAUDE.md"; then
        # Insert above HUB-MANAGED-START
        local tmp
        tmp=$(mktemp)
        awk -v marker="<!-- HUB-MANAGED-START -->" -v sfile="$section_tmp" '
          $0 == marker { while ((getline line < sfile) > 0) print line; close(sfile); print ""; print $0; next }
          { print }
        ' "CLAUDE.md" > "$tmp"
        mv "$tmp" "CLAUDE.md"
      else
        # Append to end
        printf '\n' >> "CLAUDE.md"
        cat "$section_tmp" >> "CLAUDE.md"
      fi
      rm -f "$section_tmp"
    fi
  fi

  # --- settings.json hook merge (AC-3) ---
  local hooks_file
  hooks_file=$(jq -r '.settings_hooks // empty' "$manifest")
  if [[ -n "$hooks_file" && -f "$stack_dir/$hooks_file" ]]; then
    local settings_path=".claude/settings.json"
    if [[ -f "$settings_path" ]]; then
      local new_hook
      new_hook=$(cat "$stack_dir/$hooks_file")
      local new_matcher
      new_matcher=$(echo "$new_hook" | jq -r '.matcher')
      local new_commands
      new_commands=$(echo "$new_hook" | jq '[.hooks[].command]')

      # Check if matcher group exists
      local tmp
      tmp=$(mktemp)
      local has_matcher
      has_matcher=$(jq --arg m "$new_matcher" '[.hooks.PreToolUse[] | select(.matcher == $m)] | length' "$settings_path" 2>/dev/null || echo "0")

      if [[ "$has_matcher" -gt 0 ]]; then
        # Merge new hooks into existing matcher, dedup by command string
        jq --arg m "$new_matcher" --argjson cmds "$new_commands" '
          .hooks.PreToolUse = [.hooks.PreToolUse[] |
            if .matcher == $m then
              .hooks = (.hooks + [($cmds[] as $c | {"type":"command","command":$c})] | unique_by(.command))
            else . end
          ]
        ' "$settings_path" > "$tmp"
      else
        # Add new matcher group
        jq --argjson entry "$new_hook" '
          .hooks.PreToolUse = (.hooks.PreToolUse // []) + [$entry]
        ' "$settings_path" > "$tmp"
      fi
      if [[ -s "$tmp" ]] && jq empty "$tmp" 2>/dev/null; then
        mv "$tmp" "$settings_path"
      else
        rm -f "$tmp"
        echo "WARNING: settings.json merge produced invalid JSON" >&2
        errors=$((errors + 1))
      fi
    fi
  fi

  # --- Update ccanvil.json (AC-3) ---
  local ccanvil_json=".claude/ccanvil.json"
  if [[ ! -f "$ccanvil_json" ]]; then
    mkdir -p "$(dirname "$ccanvil_json")"
    echo '{}' > "$ccanvil_json"
  fi
  local tmp
  tmp=$(mktemp)
  jq --arg s "$stack_id" '
    .stacks = ((.stacks // []) | if index($s) then . else . + [$s] end)
  ' "$ccanvil_json" > "$tmp"
  if [[ -s "$tmp" ]] && jq empty "$tmp" 2>/dev/null; then
    mv "$tmp" "$ccanvil_json"
  else
    rm -f "$tmp"
    echo "WARNING: ccanvil.json update failed" >&2
    errors=$((errors + 1))
  fi

  jq -n --argjson copied "$copied" --argjson skipped "$skipped" --argjson errors "$errors" \
    '{"copied": $copied, "skipped": $skipped, "errors": $errors}'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

require_jq

# Allow sourcing for tests: `source ccanvil-sync.sh --source-only`
if [[ "${1:-}" == "--source-only" ]]; then
  return 0 2>/dev/null || exit 0
fi

case "${1:-}" in
  # --- Atomic commands (building blocks) ---
  init)             shift; cmd_init "$@" ;;
  status)           shift; cmd_status "$@" ;;
  changelog)        cmd_changelog ;;
  diff)             shift; cmd_diff "${1:-}" ;;
  hash)             shift; cmd_hash "$@" ;;
  lock-get)         shift; cmd_lock_get "$@" ;;
  lock-update)      shift; cmd_lock_update "$@" ;;
  lock-add)         shift; cmd_lock_add "$@" ;;
  lock-remove)      shift; cmd_lock_remove "$@" ;;
  lock-set-version) shift; cmd_lock_set_version "$@" ;;
  section-merge)    shift; cmd_section_merge "$@" ;;
  scan)             cmd_scan ;;

  # --- Classification commands ---
  node-only)        shift; cmd_node_only "$@" ;;
  track)            shift; cmd_track "$@" ;;
  classify)         cmd_classify ;;

  # --- Init preflight/apply ---
  init-preflight)   shift; cmd_init_preflight "$@" ;;
  init-apply)       shift; cmd_init_apply "$@" ;;

  # --- Compound commands (replace manual orchestration) ---
  pre-check)        cmd_pre_check ;;
  pull-plan)        cmd_pull_plan ;;
  pull-auto)        shift; cmd_pull_auto "${1:-}" ;;
  pull-apply)       shift; cmd_pull_apply "$@" ;;
  pull-finalize)    shift; cmd_pull_finalize "${1:-}" ;;
  push-candidates)  shift; cmd_push_candidates "${1:-}" ;;
  push-apply)       shift; cmd_push_apply "$@" ;;
  push-finalize)    shift; cmd_push_finalize "$@" ;;
  promote)          shift; cmd_promote "$@" ;;
  demote)           shift; cmd_demote "$@" ;;
  migrate)          shift; cmd_migrate "$@" ;;
  register)         cmd_register ;;
  registry)         cmd_registry ;;
  broadcast)        shift; cmd_broadcast "$@" ;;

  # --- Stack commands ---
  stack-list)       cmd_stack_list ;;
  stack-apply)      shift; cmd_stack_apply "$@" ;;

  # --- Global commands sync ---
  pull-globals)     shift; cmd_pull_globals "$@" ;;

  *)
    echo "Usage: ccanvil-sync.sh <command> [args]"
    echo ""
    echo "Classification commands:"
    echo "  node-only <file>                      Mark file as node-only (exclude from sync)"
    echo "  track <file>                          Mark file as tracked (re-include in sync)"
    echo "  classify                              List unclassified modified/local files as JSON"
    echo ""
    echo "Compound commands (use these — they handle copy + lockfile + commit in one call):"
    echo "  pre-check                             Verify both repos clean, bootstrap script"
    echo "  pull-plan                             Compute pull plan as JSON"
    echo "  pull-auto                             Execute all auto-updates in one pass"
    echo "  pull-apply <file> <action> [merged]   Apply a conflict resolution"
    echo "  pull-finalize                         Commit all changes, update version"
    echo "  push-candidates [file]                List push-eligible files as JSON"
    echo "  push-apply <file> [description]       Push a file to hub"
    echo "  push-finalize <commit-message>        Commit in hub and update version"
    echo "  promote <file>                        Full promote workflow"
    echo "  demote <file>                         Full demote workflow"
    echo "  broadcast [--dry-run]                 Push hub updates to all registered nodes"
    echo ""
    echo "Stack commands (distribute tech stack profiles):"
    echo "  stack-list                            List available stack profiles as JSON"
    echo "  stack-apply <stack-id>                Apply a stack profile to the current project"
    echo ""
    echo "Global commands sync:"
    echo "  pull-globals [--force]                Pull hub's ccanvil-* global commands to ~/.claude/commands/"
    echo ""
    echo "Init commands (use for project initialization):"
    echo "  init-preflight <hub-path> [--stack id] Scan for conflicts, output merge plan as JSON"
    echo "  init-apply <hub-path> <plan-file>     Execute an approved merge plan"
    echo ""
    echo "Atomic commands (building blocks — prefer compound commands):"
    echo "  init [hub-path]                  Generate lockfile from current state"
    echo "  status                                Show file provenance and sync state"
    echo "  changelog                             List hub commits since last sync (JSON)"
    echo "  diff [file]                           Show diff between local and hub"
    echo "  hash <file>                           Compute sha256 of a file"
    echo "  lock-get <file>                       Read a lockfile entry"
    echo "  lock-update <file> <field> <value>    Update a lockfile field"
    echo "  lock-add <file> <origin> <sh> <lh> <status>  Add a lockfile entry"
    echo "  lock-remove <file>                    Remove a lockfile entry"
    echo "  lock-set-version <version>            Update hub version in lockfile"
    echo "  section-merge <hub> <local>       Merge hub/node sections of delimited file"
    echo "  scan                                  List all trackable files"
    exit 1
    ;;
esac
