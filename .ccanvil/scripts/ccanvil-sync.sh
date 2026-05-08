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
#   ccanvil-sync.sh broadcast-resolve-auto [--dry-run]
#                                          BTS-116: algorithmic resolution of
#                                          .claude/ccanvil.json conflicts on
#                                          the current node. Emits JSON; auto-
#                                          applies content-identical (take-hub)
#                                          and local-superset (keep-local)
#                                          cases; exits 3 for value-divergence
#                                          or local-removed-keys.

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

# append_event: Append a JSON event to the hub's events log.
# Registry and broadcast events are machine-local operational state, not code —
# so they go to an append-only log instead of polluting main's commit history.
# Usage: append_event <hub_path> <json-object-string>
# On failure: WARNING + return 0 (never abort the caller).
append_event() {
  local hub_path="$1"
  local event_json="$2"
  local log_file="$hub_path/.ccanvil/events.log"
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
  # Stamp with ts if caller didn't
  local stamped
  stamped=$(echo "$event_json" | jq -c --arg ts "$(date +%s)" '. + {ts: (.ts // ($ts | tonumber))}' 2>/dev/null) || {
    echo "WARNING: append_event: malformed JSON, dropping: $event_json" >&2
    return 0
  }
  echo "$stamped" >> "$log_file" || {
    echo "WARNING: append_event: write failed for $log_file" >&2
    return 0
  }
  return 0
}

# commit_node_file: auto-commit a single file in the current node repo.
# Used by register to commit .claude/ccanvil.local.json so the node tree is
# clean before the next broadcast pre-check. Operates on $(pwd).
# No-op if: cwd isn't a git repo, file unchanged, commit fails.
# Usage: commit_node_file <rel_file> <commit_message>
commit_node_file() {
  local rel_file="$1"
  local message="$2"

  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  if git diff --quiet -- "$rel_file" 2>/dev/null && \
     git diff --cached --quiet -- "$rel_file" 2>/dev/null; then
    if ! git ls-files --others --exclude-standard -- "$rel_file" 2>/dev/null | grep -q .; then
      return 0
    fi
  fi

  ALLOW_MAIN=1 git add -- "$rel_file" && \
    ALLOW_MAIN=1 git commit -m "$message" --quiet --only -- "$rel_file" 2>&1 || \
    echo "WARNING: auto-commit of $rel_file failed (node left dirty)" >&2
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

# is_distributable_path — Test if a path matches any TRACKED_PATTERN or
# INIT_EXTRA_FILES entry. Returns 0 (true) on match, 1 otherwise. BTS-382.
# Used by cmd_changelog to filter hub-internal commits/files that would
# never land on a downstream node out of pre-pull preview output.
is_distributable_path() {
  local path="$1"
  local pattern
  for pattern in "${TRACKED_PATTERNS[@]}"; do
    # shellcheck disable=SC2254
    case "$path" in
      $pattern) return 0 ;;
    esac
  done
  local extra
  for extra in "${INIT_EXTRA_FILES[@]}"; do
    [[ "$path" == "$extra" ]] && return 0
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

# @manifest
# purpose: Initialize a ccanvil downstream node by classifying tracked files against the hub, computing per-file hashes, and writing the canonical lockfile that all subsequent sync verbs read
# input: positional <hub-path> (defaults to $HOME/projects/ccanvil)
# output: stdout human-readable summary (total + clean/modified/local-only/hub-only counts)
# output: writes .ccanvil/ccanvil.lock (JSON: hub_source, hub_version, synced_at, files{})
# output: exit-codes 0 ok, 1 hub-not-found
# caller: global-commands/ccanvil-init.md
# depends-on: jq
# depends-on: file_hash
# depends-on: scan_tracked_files
# depends-on: scan_hub_files
# depends-on: get_or_create_node_uuid
# depends-on: persist_node_uuid
# depends-on: cmd_register
# depends-on: timestamp
# depends-on: die
# side-effect: writes-lockfile
# side-effect: registers-with-hub
# failure-mode: hub-not-found | exit=1 | visible=stderr-die-Hub-not-found-at | mitigation=pass-correct-hub-path
# contract: idempotent-on-rerun
# contract: never-modifies-tracked-files
# anchor: BTS-243 (manifest seed)
cmd_init() {
  local hub_path="${1:-$HOME/projects/ccanvil}"
  hub_path="${hub_path/#\~/$HOME}"

  # @failure-mode: hub-not-found
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
  # @side-effect: writes-lockfile
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
  # @side-effect: registers-with-hub
  cmd_register 2>/dev/null || echo "WARNING: Hub registration failed (non-fatal)"
}

# detect_project_mode
# Classifies the current working directory into one of five project modes
# so /ccanvil-init can pick mode-aware defaults. Pure — reads filesystem
# (and .git/ via `git rev-parse`) only, never writes.
#
# Classification order (most specific first):
#   1. already-initialized — .ccanvil/ccanvil.lock + bootstrap script both exist
#   2. partial-ccanvil     — has .claude/, CLAUDE.md, or non-bootstrap .ccanvil/ content; no lockfile
#   3. mature-repo         — .git/ + HEAD reachable, no partial-ccanvil markers
#   4. source-no-git       — source files present but no .git/ (or .git/ with no commits)
#   5. fresh               — nothing else matches
detect_project_mode() {
  # 1. already-initialized
  if [[ -f ".ccanvil/ccanvil.lock" && -f ".ccanvil/scripts/ccanvil-sync.sh" ]]; then
    echo "already-initialized"
    return
  fi

  # 2. partial-ccanvil — any ccanvil-meaningful marker beyond the bootstrap script
  local has_partial=false
  if [[ -d ".claude" ]]; then
    has_partial=true
  elif [[ -f "CLAUDE.md" ]]; then
    has_partial=true
  elif [[ -d ".ccanvil" ]]; then
    # .ccanvil/ counts only if it contains something beyond the bootstrap script
    while IFS= read -r f; do
      case "$f" in
        .ccanvil/scripts|.ccanvil/scripts/ccanvil-sync.sh) continue ;;
        *) has_partial=true; break ;;
      esac
    done < <(find .ccanvil -mindepth 1 2>/dev/null)
  fi
  if $has_partial; then
    echo "partial-ccanvil"
    return
  fi

  # 3. mature-repo — .git/ + HEAD; AC-24 tiebreaker: .git/ without HEAD → source-no-git
  if [[ -d ".git" ]]; then
    if git rev-parse HEAD >/dev/null 2>&1; then
      echo "mature-repo"
      return
    fi
    echo "source-no-git"
    return
  fi

  # 4. source-no-git — at least one file that isn't .DS_Store, .gitignore,
  #    README.md, CLAUDE.md, or inside .git/.claude/.ccanvil/
  while IFS= read -r f; do
    f="${f#./}"
    case "$f" in
      .DS_Store|.gitignore|README.md|CLAUDE.md) continue ;;
      .git/*|.claude/*|.ccanvil/*) continue ;;
      *)
        echo "source-no-git"
        return
        ;;
    esac
  done < <(find . -type f 2>/dev/null)

  # 5. fresh
  echo "fresh"
}

# @manifest
# purpose: Classify every hub-tracked, init-extra, GitHub-template, local, and stack file into a recommended-action plan (copy / skip / section-merge / section-merge-create-delimiters / review) so /ccanvil-init can preview changes before applying them
# input: positional <hub-path>
# input: --stack <id> (repeatable; also reads stacks[] from .claude/ccanvil.json)
# output: stdout JSON {project_mode, summary{conflicts, auto, total}, plan[]}
# output: exit-codes 0 ok, 1 hub-not-found
# caller: cmd_retrofit_check
# caller: global-commands/ccanvil-init.md
# depends-on: jq
# depends-on: scan_hub_files
# depends-on: file_hash
# depends-on: detect_project_mode
# depends-on: classify_file
# depends-on: die
# side-effect: pure-no-mutations
# failure-mode: hub-not-found | exit=1 | visible=stderr-die-Hub-not-found-at | mitigation=pass-correct-hub-path
# failure-mode: missing-positional-hub | exit=1 | visible=stderr-Usage | mitigation=supply-hub-path
# contract: read-only-classification
# contract: emits-stable-json-shape-on-empty-plan
# anchor: BTS-243 (manifest seed)
cmd_init_preflight() {
  # @failure-mode: missing-positional-hub
  # @side-effect: pure-no-mutations
  local hub_path="${1:?Usage: ccanvil-sync.sh init-preflight <hub-path>}"
  hub_path="${hub_path/#\~/$HOME}"
  shift

  # @failure-mode: hub-not-found
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

  # Detect project mode before classifying files so /ccanvil-init can
  # branch on it (mature-repo vs fresh vs already-initialized, etc.).
  local project_mode
  project_mode=$(detect_project_mode)

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
        # AC-4: Mode-aware overrides for mature-repo / partial-ccanvil.
        # These run before the standard delimiter check so retrofit defaults
        # don't clobber node-specific content by accident.
        local mature_applied=false
        if [[ "$project_mode" == "mature-repo" || "$project_mode" == "partial-ccanvil" ]]; then
          case "$local_file" in
            CLAUDE.md)
              # If local CLAUDE.md lacks an exact-line delimiter (AC-25),
              # flag as section-merge-create-delimiters so init-apply can
              # wrap existing content as the node section.
              if ! grep -qx '<!-- HUB-MANAGED-START -->' "$local_file" 2>/dev/null && \
                 ! grep -qx '<!-- NODE-SPECIFIC-START -->' "$local_file" 2>/dev/null; then
                plan=$(echo "$plan" | jq --arg f "$local_file" \
                  '. + [{"file": $f, "source": "both", "recommended_action": "section-merge-create-delimiters", "reason": "Mature-repo CLAUDE.md has no delimiter; will wrap existing content as node section"}]')
                mature_applied=true
              fi
              ;;
            README.md|CONTRIBUTING.md)
              plan=$(echo "$plan" | jq --arg f "$local_file" \
                '. + [{"file": $f, "source": "both", "recommended_action": "skip", "reason": "Mature-repo mode: keep local node-specific content"}]')
              mature_applied=true
              ;;
          esac
        fi

        if [[ "$mature_applied" == "false" ]]; then
          # Different — check for section-merge delimiter (default path)
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

  jq -n --argjson conflicts "$conflicts" --argjson auto "$auto" --argjson total "$total" \
        --argjson plan "$plan" --arg mode "$project_mode" \
    '{"project_mode": $mode, "summary": {"conflicts": $conflicts, "auto": $auto, "total": $total}, "plan": $plan}'
}

# @manifest
# purpose: Execute an init-preflight plan by copying, skipping, section-merging, or wrapping-then-merging files according to each entry's recommended_action so /ccanvil-init can move from preview to applied scaffolding
# input: positional <hub-path> <plan-file>
# output: stdout one log line per entry (COPIED/MERGED/SKIP/ERROR) and a final JSON summary {copied, skipped, merged, errors}
# output: exit-codes 0 ok, 1 hub-not-found-or-plan-missing-or-invalid
# caller: global-commands/ccanvil-init.md
# depends-on: jq
# depends-on: cmd_section_merge
# depends-on: cp
# depends-on: mkdir
# depends-on: sed
# depends-on: mktemp
# depends-on: mv
# depends-on: grep
# depends-on: tail
# depends-on: cat
# depends-on: wc
# depends-on: die
# side-effect: writes-target-files
# side-effect: creates-target-directories
# side-effect: appends-hub-managed-section
# failure-mode: hub-not-found | exit=1 | visible=stderr-die-Hub-not-found-at | mitigation=pass-correct-hub-path
# failure-mode: plan-file-missing | exit=1 | visible=stderr-die-Plan-file-not-found | mitigation=run-init-preflight-first
# failure-mode: plan-shape-invalid | exit=1 | visible=stderr-die-Invalid-plan-file | mitigation=regenerate-plan-via-preflight
# failure-mode: hub-source-missing-per-entry | exit=0 | visible=stderr-ERROR-Hub-source-not-found | mitigation=increments-errors-counter-and-continues
# failure-mode: section-merge-failure-per-entry | exit=0 | visible=stderr-ERROR-Section-merge-failed | mitigation=increments-errors-counter-and-continues
# contract: applies-recommended-action-verbatim
# contract: continues-past-per-entry-errors
# contract: emits-summary-on-completion
# anchor: BTS-243 (manifest seed)
cmd_init_apply() {
  # @failure-mode: hub-source-missing-per-entry
  # @failure-mode: section-merge-failure-per-entry
  local hub_path="${1:?Usage: ccanvil-sync.sh init-apply <hub-path> <plan-file>}"
  local plan_file="${2:?Usage: ccanvil-sync.sh init-apply <hub-path> <plan-file>}"
  hub_path="${hub_path/#\~/$HOME}"

  # @failure-mode: hub-not-found
  [[ -d "$hub_path" ]] || die "Hub not found at: $hub_path"
  # @failure-mode: plan-file-missing
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
    # @failure-mode: plan-shape-invalid
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
        # @side-effect: creates-target-directories
        mkdir -p "$(dirname "$file")"
        # @side-effect: writes-target-files
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
      section-merge-create-delimiters)
        # AC-6: wrap local content as node section and append hub's hub-managed
        # section below an inserted <!-- HUB-MANAGED-START --> delimiter.
        # AC-7: if delimiters are already present, dispatch to standard
        # section-merge (no double-wrapping).
        # AC-25: detect delimiters by exact-line match only (grep -qx).
        if [[ -z "$hub_file" || ! -f "$hub_file" ]]; then
          echo "ERROR: Hub source not found for $file" >&2
          errors=$((errors + 1))
          i=$((i + 1)); continue
        fi
        if [[ ! -f "$file" ]]; then
          mkdir -p "$(dirname "$file")"
          cp "$hub_file" "$file"
          copied=$((copied + 1))
          echo "COPIED: $file (no local to merge)"
        elif grep -qx '<!-- HUB-MANAGED-START -->' "$file" 2>/dev/null || \
             grep -qx '<!-- NODE-SPECIFIC-START -->' "$file" 2>/dev/null; then
          # Delimiters already present — fall through to standard section-merge
          local merge_result
          merge_result=$(cmd_section_merge "$hub_file" "$file" 2>/dev/null) && {
            echo "$merge_result" > "$file"
            merged=$((merged + 1))
            echo "MERGED: $file (delimiters already present)"
          } || {
            echo "ERROR: Section-merge failed for $file" >&2
            errors=$((errors + 1))
          }
        else
          # AC-6: wrap local as node section, append hub's delimiter-onwards.
          # @side-effect: appends-hub-managed-section
          local tmp
          tmp=$(mktemp)
          cat "$file" > "$tmp"
          # Guarantee a trailing newline between node content and the delimiter.
          if [[ -s "$tmp" && $(tail -c 1 "$tmp" | wc -l) -eq 0 ]]; then
            echo "" >> "$tmp"
          fi
          # Append hub's HUB-MANAGED-START line through EOF. Exact-line anchor.
          sed -n '/^<!-- HUB-MANAGED-START -->$/,$p' "$hub_file" >> "$tmp"
          mv "$tmp" "$file"
          merged=$((merged + 1))
          echo "MERGED: $file (delimiters inserted)"
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

# format_preflight_table
# Renders init-preflight JSON output as a human-readable table.
# Reads JSON from stdin, writes table to stdout.
# Shared between cmd_retrofit_check and /ccanvil-init's in-skill rendering.
format_preflight_table() {
  local json
  json=$(cat)

  local mode
  mode=$(echo "$json" | jq -r '.project_mode // "unknown"')
  echo "Detected mode: $mode"
  echo ""

  printf "%-50s %-5s %-7s %-34s %s\n" "File" "Hub" "Local" "Action" "Reason"
  printf "%-50s %-5s %-7s %-34s %s\n" "----" "---" "-----" "------" "------"

  echo "$json" | jq -r '.plan[] | [.file, .source, .recommended_action, .reason] | @tsv' | \
    while IFS=$'\t' read -r file source action reason; do
      local hub="-" lcl="-"
      case "$source" in
        hub-only)    hub="Y"; lcl="-" ;;
        both)        hub="Y"; lcl="Y" ;;
        local-only)  hub="-"; lcl="Y" ;;
        stack:*)     hub="Y"; lcl="-" ;;
      esac
      printf "%-50s %-5s %-7s %-34s %s\n" "$file" "$hub" "$lcl" "$action" "$reason"
    done
}

# cmd_retrofit_check — AC-15
# Thin wrapper around init-preflight that emits a human-readable table
# instead of JSON. Read-only: no files created, no lockfile touched.
# @manifest
# purpose: Render init-preflight classification as a human-readable table for operators previewing scaffold-changes before committing to apply
# input: positional <hub-path>
# output: stdout formatted table (Detected mode + per-file rows: File, Hub, Local, Action, Reason)
# output: exit-codes 0 ok, 1 hub-not-found-or-missing-positional
# caller: global-commands/ccanvil-init.md
# depends-on: cmd_init_preflight
# depends-on: format_preflight_table
# side-effect: pure-no-mutations
# failure-mode: missing-positional-hub | exit=1 | visible=stderr-Usage | mitigation=supply-hub-path
# failure-mode: preflight-failure-bubble | exit=1 | visible=stderr-from-cmd_init_preflight | mitigation=fix-hub-path-then-rerun
# contract: read-only-passthrough
# anchor: BTS-243 (manifest seed)
cmd_retrofit_check() {
  # @failure-mode: missing-positional-hub
  # @side-effect: pure-no-mutations
  local hub_path="${1:?Usage: ccanvil-sync.sh retrofit-check <hub-path>}"
  # @failure-mode: preflight-failure-bubble
  cmd_init_preflight "$hub_path" | format_preflight_table
  return 0
}

# @manifest
# purpose: Read the ccanvil lockfile and emit per-file sync status (CLEAN / MODIFIED / LOCAL / PROMOTED / HUB-ONLY / NODE-ONLY) plus hub-version drift indicator so operators can see what's diverged at a glance
# input: --json (machine-readable output)
# input: --filter <status> (one of clean / modified / local-only / promoted / hub-only / non-clean)
# output: stdout human-readable table (default) OR JSON {hub_source, hub_version, synced_at, files[]}
# output: exit-codes 0 ok, 1 missing-lockfile-via-require_lockfile
# caller: skill:/ccanvil-status
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: get_hub_source_raw
# depends-on: get_hub_source_display
# depends-on: get_sync_field
# depends-on: git
# side-effect: reads-lockfile
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-ccanvil-sync-init-first
# contract: emits-empty-table-when-no-tracked-files
# contract: surfaces-hub-version-drift-when-detectable
# anchor: BTS-243 (manifest seed)
cmd_status() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-lockfile
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

# @manifest
# purpose: Compute the hub-side commit window between the lockfile's last_version and current HEAD; emit commits + files-changed envelope so /ccanvil-pull can preview what new hub work would land
# input: (none)
# output: stdout JSON {status: up-to-date|behind, from, to, commit_count, commits[], files_changed[]}
# output: exit-codes 0 ok, 1 missing-lockfile-or-hub-not-found-or-version-not-in-hub
# caller: skill:/ccanvil-pull
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source_raw
# depends-on: git
# depends-on: die
# side-effect: reads-lockfile-and-hub-git
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: hub-not-found | exit=1 | visible=stderr-die-Hub-not-found-at | mitigation=verify-hub-source-path
# failure-mode: rewritten-history | exit=1 | visible=stderr-die-not-found-in-hub | mitigation=re-init-against-current-hub
# contract: emits-up-to-date-envelope-when-versions-match
# contract: read-only-git-inspection
# anchor: BTS-243 (manifest seed)
cmd_changelog() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-lockfile-and-hub-git
  require_lockfile
  local hub_root
  hub_root=$(get_hub_source_raw)

  # @failure-mode: hub-not-found
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
    # @failure-mode: rewritten-history
    die "Last synced version $last_version not found in hub repo. History may have been rewritten."
  fi

  # BTS-382: filter to distributable paths only. Hub-internal commits that
  # only touch docs/, hub/, etc. (paths NOT in TRACKED_PATTERNS or
  # INIT_EXTRA_FILES) leak into downstream pre-pull previews as noise. The
  # downstream operator parses extra rows that won't land. Filter both
  # `files_changed` and `commits` so the envelope only shows what would
  # actually affect the downstream node.
  local files_changed_filtered_json="[]"
  while IFS=$'\t' read -r change_type filepath; do
    if is_distributable_path "$filepath"; then
      files_changed_filtered_json=$(echo "$files_changed_filtered_json" \
        | jq --arg t "$change_type" --arg f "$filepath" \
          '. + [{"type": $t, "file": $f}]')
    fi
  done < <(git -C "$hub_root" diff --name-status "$last_version".."$current_version")

  # Commit log — keep only commits whose diff intersects distributable paths.
  local commits_json="[]"
  while IFS=$'\t' read -r hash subject; do
    local commit_files
    commit_files=$(git -C "$hub_root" show --name-only --format= "$hash" 2>/dev/null)
    local commit_touches_distributable=false
    while IFS= read -r commit_file; do
      [[ -z "$commit_file" ]] && continue
      if is_distributable_path "$commit_file"; then
        commit_touches_distributable=true
        break
      fi
    done <<< "$commit_files"
    if [[ "$commit_touches_distributable" == "true" ]]; then
      commits_json=$(echo "$commits_json" | jq --arg h "$hash" --arg s "$subject" \
        '. + [{"hash": $h, "subject": $s}]')
    fi
  done < <(git -C "$hub_root" log --format="%h%x09%s" "$last_version".."$current_version")

  local commit_count
  commit_count=$(echo "$commits_json" | jq 'length')

  jq -n --arg from "$last_version" --arg to "$current_version" \
    --argjson count "$commit_count" \
    --argjson commits "$commits_json" --argjson files "$files_changed_filtered_json" \
    '{"status":"behind","from":$from,"to":$to,"commit_count":$count,"commits":$commits,"files_changed":$files}'
}

# @manifest
# purpose: Compute and render unified-diff between hub and local for one file or every modified file in the lockfile so operators can review pre-pull/push deltas
# input: positional <file> (optional — when omitted, diffs all modified entries)
# output: stdout unified-diff blocks (one per file, with === <file> === banner when iterating)
# output: exit-codes 0 ok (diffs always pass-through), 1 missing-lockfile
# caller: skill:/ccanvil-pull
# caller: skill:/ccanvil-push
# caller: .claude/agents/ccanvil-differ.md
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: file_hash
# depends-on: diff
# side-effect: reads-lockfile-and-hub-files
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: hub-file-missing | exit=0 | visible=stdout-File-not-in-hub | mitigation=informational-only
# failure-mode: local-file-missing | exit=0 | visible=stdout-File-not-in-project | mitigation=informational-only
# contract: read-only-diff-rendering
# contract: skips-clean-and-unchanged-files-when-iterating
# anchor: BTS-243 (manifest seed)
cmd_diff() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-lockfile-and-hub-files
  require_lockfile
  local file="${1:-}"
  local hub_source
  hub_source=$(get_hub_source)

  if [[ -n "$file" ]]; then
    # Diff a specific file
    local hub_file="$hub_source/$file"
    if [[ ! -f "$hub_file" ]]; then
      # @failure-mode: hub-file-missing
      echo "File not in hub: $file"
      [[ -f "$file" ]] && echo "(exists locally as local-only file)"
      return 0
    fi
    if [[ ! -f "$file" ]]; then
      # @failure-mode: local-file-missing
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

# @manifest
# purpose: Emit the canonical sha256-prefix hash for a single file using file_hash so operators and substrate can compare local content against lockfile entries deterministically
# input: positional <file>
# output: stdout "<hash>  <file>" (sha256-prefix format from file_hash)
# output: exit-codes 0 ok, 1 missing-positional-file
# depends-on: file_hash
# side-effect: pure-no-mutations
# failure-mode: missing-positional-file | exit=1 | visible=stderr-Usage | mitigation=supply-file-arg
# contract: pure-hash-emission
# anchor: BTS-243 (manifest seed)
cmd_hash() {
  # @failure-mode: missing-positional-file
  # @side-effect: pure-no-mutations
  local file="${1:?Usage: ccanvil-sync.sh hash <file>}"
  echo "$(file_hash "$file")  $file"
}

# @manifest
# purpose: Read a single lockfile entry by file-path key and emit its full descriptor (origin, hub_hash, local_hash, status, sync) or the literal "not found" so substrate consumers can probe per-file state without parsing the lockfile themselves
# input: positional <file>
# output: stdout JSON object (entry descriptor) or "not found" string
# output: exit-codes 0 ok, 1 missing-lockfile-or-missing-positional
# depends-on: jq
# depends-on: require_lockfile
# side-effect: reads-lockfile
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-arg
# contract: never-mutates-state
# anchor: BTS-244 (manifest seed)
cmd_lock_get() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-lockfile
  require_lockfile
  # @failure-mode: missing-positional
  local file="${1:?Usage: ccanvil-sync.sh lock-get <file>}"
  jq --arg f "$file" '.files[$f] // "not found"' "$LOCKFILE"
}

# @manifest
# purpose: Set a single field on a single lockfile entry to either null (when value is the literal "null") or a string value, then write atomically via safe_lock_mv so partial-write torn-state never reaches consumers
# input: positional <file> <field> <value>
# output: writes lockfile entry field
# output: exit-codes 0 ok, 1 missing-lockfile-or-missing-positional
# depends-on: jq
# depends-on: require_lockfile
# depends-on: safe_lock_mv
# depends-on: mktemp
# side-effect: writes-lockfile-field
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-field-value
# contract: atomic-write-via-safe_lock_mv
# contract: null-literal-stores-json-null-not-string-null
# anchor: BTS-244 (manifest seed)
cmd_lock_update() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
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
  # @side-effect: writes-lockfile-field
  safe_lock_mv "$tmp" "$LOCKFILE" "lock-update $file $field"
}

# @manifest
# purpose: Insert or replace a lockfile entry with a fully-formed descriptor (origin + hub_hash + local_hash + status); branches on null hub_hash vs null local_hash so callers can express hub-only or local-only entries explicitly
# input: positional <file> <origin> <hub_hash> <local_hash> <status>
# output: writes lockfile entry
# output: exit-codes 0 ok, 1 missing-lockfile-or-missing-positional
# caller: cmd_pull_apply
# depends-on: jq
# depends-on: require_lockfile
# depends-on: safe_lock_mv
# depends-on: mktemp
# side-effect: writes-lockfile-entry
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-all-positional-args
# contract: replaces-existing-entry-on-collision
# contract: atomic-write-via-safe_lock_mv
# anchor: BTS-244 (manifest seed)
cmd_lock_add() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
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
  # @side-effect: writes-lockfile-entry
  safe_lock_mv "$tmp" "$LOCKFILE" "lock-add $file"
}

# @manifest
# purpose: Delete a lockfile entry by file-path key so cmd_pull_apply's delete action can remove tracked entries that have been removed from the hub
# input: positional <file>
# output: writes lockfile (entry removed)
# output: exit-codes 0 ok, 1 missing-lockfile-or-missing-positional
# caller: cmd_pull_apply
# depends-on: jq
# depends-on: require_lockfile
# depends-on: safe_lock_mv
# depends-on: mktemp
# side-effect: removes-lockfile-entry
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-arg
# contract: idempotent-on-already-missing
# contract: atomic-write-via-safe_lock_mv
# anchor: BTS-244 (manifest seed)
cmd_lock_remove() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
  local file="${1:?Usage: ccanvil-sync.sh lock-remove <file>}"

  local tmp
  tmp=$(mktemp)
  jq --arg f "$file" 'del(.files[$f])' "$LOCKFILE" > "$tmp" || true
  # @side-effect: removes-lockfile-entry
  safe_lock_mv "$tmp" "$LOCKFILE" "lock-remove $file"
}

# @manifest
# purpose: Stamp the lockfile's hub_version + synced_at with the supplied version + current timestamp so cmd_pull_finalize and cmd_push_finalize can record a coherent post-sync version pin
# input: positional <version>
# output: writes lockfile hub_version + synced_at
# output: exit-codes 0 ok, 1 missing-lockfile-or-missing-positional
# caller: cmd_pull_finalize
# caller: cmd_push_finalize
# caller: cmd_promote
# depends-on: jq
# depends-on: require_lockfile
# depends-on: safe_lock_mv
# depends-on: timestamp
# depends-on: mktemp
# side-effect: writes-lockfile-version
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-version-arg
# contract: atomic-write-via-safe_lock_mv
# anchor: BTS-244 (manifest seed)
cmd_lock_set_version() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
  local version="${1:?Usage: ccanvil-sync.sh lock-set-version <version>}"

  local tmp
  tmp=$(mktemp)
  jq --arg v "$version" --arg ts "$(timestamp)" '.hub_version = $v | .synced_at = $ts' "$LOCKFILE" > "$tmp" || true
  # @side-effect: writes-lockfile-version
  safe_lock_mv "$tmp" "$LOCKFILE" "lock-set-version"
}

# @manifest
# purpose: Compose a merged markdown file by taking the hub-managed section from the hub source and the node-specific section from the local file using exact-line delimiters (NODE-SPECIFIC-START or HUB-MANAGED-START) so /ccanvil-pull and init-apply can preserve project content while updating hub-owned content
# input: positional <hub-file> <local-file>
# output: stdout merged-file content (hub-section + delimiter + node-section, or vice-versa depending on delimiter shape)
# output: exit-codes 0 ok, 1 missing-positional-or-files-or-no-delimiter
# caller: cmd_init_apply
# caller: cmd_pull_apply
# depends-on: sed
# depends-on: grep
# depends-on: cat
# depends-on: die
# side-effect: pure-no-mutations
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-both-args
# failure-mode: hub-file-missing | exit=1 | visible=stderr-die-Hub-file-not-found | mitigation=verify-hub-path
# failure-mode: local-file-missing | exit=1 | visible=stderr-die-Local-file-not-found | mitigation=verify-local-path
# failure-mode: no-section-delimiter | exit=1 | visible=stderr-ERROR-No-section-delimiter | mitigation=add-NODE-SPECIFIC-START-or-HUB-MANAGED-START-to-hub-source
# contract: stdout-merged-content-never-mutates-input-files
# contract: handles-local-without-delimiter-by-wrapping-as-node-section
# anchor: BTS-243 (manifest seed)
cmd_section_merge() {
  # @failure-mode: missing-positional
  # @side-effect: pure-no-mutations
  local hub_file="${1:?Usage: ccanvil-sync.sh section-merge <hub-file> <local-file>}"
  local local_file="${2:?Usage: ccanvil-sync.sh section-merge <hub-file> <local-file>}"

  # @failure-mode: hub-file-missing
  [[ -f "$hub_file" ]] || die "Hub file not found: $hub_file"
  # @failure-mode: local-file-missing
  [[ -f "$local_file" ]] || die "Local file not found: $local_file"

  # Detect which delimiter the hub file uses
  local delimiter=""
  if grep -q '<!-- NODE-SPECIFIC-START -->' "$hub_file"; then
    delimiter="<!-- NODE-SPECIFIC-START -->"
  elif grep -q '<!-- HUB-MANAGED-START -->' "$hub_file"; then
    delimiter="<!-- HUB-MANAGED-START -->"
  else
    # No delimiter in hub file — not a section-merge file
    # @failure-mode: no-section-delimiter
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
# @manifest
# purpose: Mark a tracked lockfile entry as node-only so subsequent pull/push/promote operations skip it; idempotent on already-classified entries
# input: positional <file>
# output: stdout NODE-ONLY status line (or SKIP when already node-only)
# output: writes lockfile sync field for the entry
# output: exit-codes 0 ok, 1 missing-lockfile-or-file-not-tracked-or-missing-positional
# caller: skill:/ccanvil-ignore
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_sync_field
# depends-on: safe_lock_mv
# depends-on: mktemp
# depends-on: die
# side-effect: writes-lockfile-sync-field
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-arg
# failure-mode: file-not-tracked | exit=1 | visible=stderr-die-File-not-tracked | mitigation=run-pull-or-init-to-track-first
# contract: idempotent-on-already-node-only
# anchor: BTS-243 (manifest seed)
cmd_node_only() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
  local file="${1:?Usage: ccanvil-sync.sh node-only <file>}"

  # Verify file exists in lockfile
  local exists
  exists=$(jq -r --arg f "$file" '.files[$f] // "null"' "$LOCKFILE")
  # @failure-mode: file-not-tracked
  [[ "$exists" != "null" ]] || die "File not tracked in lockfile: $file"

  local current_sync
  current_sync=$(get_sync_field "$file")
  if [[ "$current_sync" == "node-only" ]]; then
    echo "SKIP: $file is already node-only."
    return 0
  fi

  local tmp; tmp=$(mktemp)
  jq --arg f "$file" '.files[$f].sync = "node-only"' "$LOCKFILE" > "$tmp" || true
  # @side-effect: writes-lockfile-sync-field
  safe_lock_mv "$tmp" "$LOCKFILE" "node-only $file"

  echo "NODE-ONLY: $file (excluded from future pull/push)"
}

# @manifest
# purpose: Restore a previously node-only lockfile entry to tracked sync so subsequent pull/push operations include it again; idempotent on already-tracked entries
# input: positional <file>
# output: stdout TRACKED status line (or SKIP when already tracked)
# output: writes lockfile sync field for the entry
# output: exit-codes 0 ok, 1 missing-lockfile-or-file-not-tracked-or-missing-positional
# caller: skill:/ccanvil-ignore
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_sync_field
# depends-on: safe_lock_mv
# depends-on: mktemp
# depends-on: die
# side-effect: writes-lockfile-sync-field
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-arg
# failure-mode: file-not-tracked | exit=1 | visible=stderr-die-File-not-tracked | mitigation=verify-file-was-pulled-or-init
# contract: idempotent-on-already-tracked
# anchor: BTS-243 (manifest seed)
cmd_track() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
  local file="${1:?Usage: ccanvil-sync.sh track <file>}"

  local exists
  exists=$(jq -r --arg f "$file" '.files[$f] // "null"' "$LOCKFILE")
  # @failure-mode: file-not-tracked
  [[ "$exists" != "null" ]] || die "File not tracked in lockfile: $file"

  local current_sync
  current_sync=$(get_sync_field "$file")
  if [[ "$current_sync" == "tracked" ]]; then
    echo "SKIP: $file is already tracked."
    return 0
  fi

  local tmp; tmp=$(mktemp)
  jq --arg f "$file" '.files[$f].sync = "tracked"' "$LOCKFILE" > "$tmp" || true
  # @side-effect: writes-lockfile-sync-field
  safe_lock_mv "$tmp" "$LOCKFILE" "track $file"

  echo "TRACKED: $file (re-included in future pull/push)"
}

# classify: list all modified/local files that need classification
# Output: JSON array of {file, status, origin, sync} for unclassified files
# @manifest
# purpose: Walk every lockfile entry and emit the subset that's modified or local-only AND not yet node-only so /ccanvil-push can present an actionable classification queue
# input: (none)
# output: stdout JSON array [{file, status, origin}] (empty array when nothing pending)
# output: exit-codes 0 ok, 1 missing-lockfile
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_sync_field
# side-effect: reads-lockfile
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# contract: emits-empty-array-when-no-candidates
# contract: filters-out-node-only-and-clean-entries
# anchor: BTS-243 (manifest seed)
cmd_classify() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-lockfile
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
# @manifest
# purpose: Gate sync verbs on a clean hub working tree, a clean node working tree, and an up-to-date local sync script (auto-bootstrapping the script when the hub copy differs) so pull/push never operate over dirty state
# input: (none)
# output: stdout OK on clean state, BOOTSTRAPPED on script update, ERROR-prefixed lines on dirty state
# output: writes .ccanvil/scripts/ccanvil-sync.sh + lockfile when bootstrap fires
# output: exit-codes 0 ok-or-bootstrapped, 1 dirty-hub-or-dirty-node-or-missing-lockfile-or-hub-not-found
# caller: skill:/ccanvil-pull
# caller: skill:/ccanvil-push
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: get_hub_source_raw
# depends-on: file_hash
# depends-on: safe_lock_mv
# depends-on: mktemp
# depends-on: cp
# depends-on: git
# depends-on: die
# side-effect: reads-hub-and-node-git-status
# side-effect: bootstraps-sync-script
# side-effect: writes-lockfile-on-bootstrap
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: hub-not-found | exit=1 | visible=stderr-die-Hub-not-found-at | mitigation=verify-hub-source-path
# failure-mode: dirty-hub | exit=1 | visible=stderr-ERROR-Hub-repo-has-uncommitted-changes | mitigation=commit-or-stash-in-hub
# failure-mode: dirty-node | exit=1 | visible=stderr-ERROR-This-project-has-uncommitted-changes | mitigation=commit-or-stash-in-node
# contract: bootstrap-exits-0-and-asks-rerun
# contract: emits-OK-only-when-fully-clean
# anchor: BTS-243 (manifest seed)
cmd_pre_check() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-hub-and-node-git-status
  require_lockfile
  local hub_source
  hub_source=$(get_hub_source)
  local hub_root
  hub_root=$(get_hub_source_raw)

  # @failure-mode: hub-not-found
  [[ -d "$hub_source" ]] || die "Hub not found at: $hub_source"

  # Check hub repo is clean
  if git -C "$hub_root" rev-parse HEAD >/dev/null 2>&1; then
    local dirty
    dirty=$(git -C "$hub_root" status --porcelain 2>/dev/null)
    if [[ -n "$dirty" ]]; then
      # @failure-mode: dirty-hub
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
      # @failure-mode: dirty-node
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
      # @side-effect: bootstraps-sync-script
      cp "$hub_script" "$local_script"
      # Update lockfile hashes so status shows clean after bootstrap
      local new_hash
      new_hash=$(file_hash "$local_script")
      local tmp; tmp=$(mktemp)
      jq --arg f "$local_script" --arg h "$new_hash" \
        '.files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean"' \
        "$LOCKFILE" > "$tmp" || true
      # @side-effect: writes-lockfile-on-bootstrap
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
# @manifest
# purpose: Walk every tracked lockfile entry plus every hub-tracked file not yet in the lockfile and classify each into a pull action (auto-update, section-merge, conflict, new, removed, adopt-clean, adopt-conflict) so /ccanvil-pull can preview every change before applying
# input: (none)
# output: stdout JSON array [{file, action, reason, local_hash}]
# output: exit-codes 0 ok, 1 missing-lockfile
# caller: skill:/ccanvil-pull
# caller: cmd_pull_auto
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: file_hash
# depends-on: is_node_only
# depends-on: scan_hub_files
# depends-on: grep
# side-effect: reads-lockfile-and-hub-files
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# contract: read-only-classification
# contract: skips-node-only-and-local-only-and-non-hub-origins
# anchor: BTS-243 (manifest seed)
cmd_pull_plan() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-lockfile-and-hub-files
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

    # Skip non-hub origins (stack files are owned by stack-apply, not broadcast)
    if [[ "$origin" != "hub" ]]; then
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
# @manifest
# purpose: Apply every auto-update and adopt-clean action from a fresh pull-plan in one batch — copy hub files into the node tree and refresh lockfile hashes — so /ccanvil-pull's safe path completes without per-file operator interaction
# input: --dry-run (optional; describe-only mode)
# output: stdout one AUTO-UPDATED log line per applied file plus a final summary banner
# output: writes target files + lockfile entries
# output: exit-codes 0 ok, 1 missing-lockfile
# caller: skill:/ccanvil-pull
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: cmd_pull_plan
# depends-on: file_hash
# depends-on: safe_lock_mv
# depends-on: mktemp
# depends-on: mkdir
# depends-on: cp
# side-effect: writes-target-files
# side-effect: writes-lockfile-entries
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# contract: dry-run-makes-no-mutations
# contract: skips-non-auto-actions
# anchor: BTS-243 (manifest seed)
cmd_pull_auto() {
  local dry_run=false
  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
  fi

  # @failure-mode: missing-lockfile
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
    # @side-effect: writes-target-files
    cp "$hub_file" "$file"

    # Update lockfile in one pass (works for both existing and new entries)
    local tmp
    tmp=$(mktemp)
    jq --arg f "$file" --arg h "$new_hash" \
      '.files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean" | .files[$f].origin = "hub" | .files[$f].sync = "tracked"' \
      "$LOCKFILE" > "$tmp" || true
    # @side-effect: writes-lockfile-entries
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
# @manifest
# purpose: Execute the operator-chosen resolution action for a single file in a pull-plan (take-hub, keep-local, section-merge, accept-new, adopt-conflict, delete, write-merged) so /ccanvil-pull can drive per-file conflict handling without re-deriving plan logic
# input: positional <file> <action> [merged-content-file]
# input: --dry-run (optional; describe-only mode)
# input: env PLAN_LOCAL_HASH (optional; gates against post-plan local mutation)
# input: env PLAN_LOCAL_STATUS (optional; gates against post-plan lockfile mutation for delete)
# output: stdout APPLIED log line per applied action; DRY-RUN line in dry-run mode
# output: writes target files + lockfile entries (or rm + lock-remove for delete)
# output: exit-codes 0 ok, 1 missing-args-or-hub-file-or-unknown-action-or-stale-plan-hash
# caller: skill:/ccanvil-pull
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: cmd_section_merge
# depends-on: cmd_lock_add
# depends-on: cmd_lock_remove
# depends-on: cmd_stack_apply
# depends-on: file_hash
# depends-on: safe_lock_mv
# depends-on: guard_fail
# depends-on: mktemp
# depends-on: mkdir
# depends-on: cp
# depends-on: rm
# depends-on: die
# side-effect: writes-target-files
# side-effect: writes-lockfile-entries
# side-effect: removes-target-files-on-delete
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-and-action
# failure-mode: hub-file-missing | exit=1 | visible=stderr-die-Hub-file-not-found | mitigation=verify-hub-source
# failure-mode: stale-plan-local-hash | exit=1 | visible=stderr-from-guard_fail | mitigation=re-run-pull-plan
# failure-mode: stale-plan-local-status | exit=1 | visible=stderr-from-guard_fail | mitigation=re-run-pull-plan
# failure-mode: accept-new-on-existing-file | exit=1 | visible=stderr-die-Refusing-to-overwrite | mitigation=use-take-hub-or-section-merge
# failure-mode: missing-merged-file | exit=1 | visible=stderr-die-Merged-content-file-not-found | mitigation=supply-valid-merged-path
# failure-mode: unknown-action | exit=1 | visible=stderr-die-Unknown-action | mitigation=use-documented-action-name
# contract: dry-run-makes-no-mutations
# contract: stack-reapply-runs-after-take-hub-on-settings-json
# anchor: BTS-243 (manifest seed)
cmd_pull_apply() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
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
      # @failure-mode: stale-plan-local-hash
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
      # @failure-mode: hub-file-missing
      [[ -f "$hub_file" ]] || die "Hub file not found: $hub_file"
      mkdir -p "$(dirname "$file")"
      # @side-effect: writes-target-files
      cp "$hub_file" "$file"
      local new_hash
      new_hash=$(file_hash "$file")
      local tmp; tmp=$(mktemp)
      jq --arg f "$file" --arg h "$new_hash" \
        '.files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "clean"' \
        "$LOCKFILE" > "$tmp" || true
      # @side-effect: writes-lockfile-entries
      safe_lock_mv "$tmp" "$LOCKFILE" "pull-apply take-hub $file"
      echo "APPLIED: $file (took hub)"

      # After take-hub on settings.json, re-apply each active stack so
      # stack hook entries wiped by hub's settings.json are restored.
      if [[ "$file" == ".claude/settings.json" && -f ".claude/ccanvil.json" ]]; then
        local active_stacks
        active_stacks=$(jq -r '.stacks[]? // empty' .claude/ccanvil.json 2>/dev/null || true)
        if [[ -n "$active_stacks" ]]; then
          while IFS= read -r sid; do
            [[ -z "$sid" ]] && continue
            if ( cmd_stack_apply "$sid" ) >/dev/null 2>&1; then
              echo "REAPPLIED STACK: $sid (settings.json was overwritten)"
            else
              echo "WARNING: stack-apply $sid failed during auto-reapply" >&2
            fi
          done <<< "$active_stacks"
        fi
      fi
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
        # @failure-mode: accept-new-on-existing-file
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
          # @failure-mode: stale-plan-local-status
          guard_fail "rm" "$file" "lockfile status changed after plan (expected $PLAN_LOCAL_STATUS, got $current_status)"
        fi
      fi
      if [[ -f "$file" ]]; then
        # @side-effect: removes-target-files-on-delete
        rm "$file"
      fi
      cmd_lock_remove "$file"
      echo "APPLIED: $file (deleted)"
      ;;

    write-merged)
      [[ -n "$merged_file" ]] || die "Usage: pull-apply <file> write-merged <merged-content-file>"
      # @failure-mode: missing-merged-file
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
      # @failure-mode: unknown-action
      die "Unknown action: $action. Use: take-hub, keep-local, section-merge, accept-new, delete, write-merged"
      ;;
  esac
}

# pull-finalize: Update version, commit all changes, output summary
# Usage: pull-finalize [--dry-run]
# @manifest
# purpose: Stamp the lockfile with the current hub HEAD version, stage every node-side change from the pull, and create a single chore(sync) commit summarizing the file delta so /ccanvil-pull leaves the node tree in a committed, audit-friendly state
# input: --dry-run (optional; describe-only mode)
# output: stdout DRY-RUN preview lines OR a Committed status with the new short-sha and a final summary
# output: writes lockfile hub_version + synced_at; creates one git commit on the current branch
# output: exit-codes 0 ok, 1 missing-lockfile
# caller: skill:/ccanvil-pull
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: get_hub_source_raw
# depends-on: get_hub_source_display
# depends-on: cmd_lock_set_version
# depends-on: git
# depends-on: wc
# depends-on: tr
# depends-on: sort
# depends-on: grep
# side-effect: writes-lockfile-version
# side-effect: stages-and-commits-pull
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# contract: dry-run-makes-no-mutations
# contract: skips-commit-when-no-file-changes
# anchor: BTS-243 (manifest seed)
cmd_pull_finalize() {
  local dry_run=false
  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
  fi

  # @failure-mode: missing-lockfile
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
    # @side-effect: writes-lockfile-version
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
        # @side-effect: stages-and-commits-pull
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
# @manifest
# purpose: List every modified, local-only, or already-promoted lockfile entry that's eligible for hub-side promotion (with hub-vs-local has_diff flag) so /ccanvil-push can present an actionable classification queue
# input: positional <file> (optional; restrict listing to one entry)
# output: stdout JSON array [{file, status, has_diff}]
# output: exit-codes 0 ok, 1 missing-lockfile
# caller: skill:/ccanvil-push
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: is_node_only
# depends-on: diff
# side-effect: reads-lockfile-and-hub-files
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# contract: emits-empty-array-when-no-candidates
# contract: skips-node-only-and-clean-entries
# anchor: BTS-243 (manifest seed)
cmd_push_candidates() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-lockfile-and-hub-files
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
# @manifest
# purpose: Copy one node-side file into the hub tree and update the lockfile (status promoted for local-only origin, clean for modified) so /ccanvil-push can stage promotion-candidate files in batches before the hub-side commit
# input: positional <file> [description]
# input: --dry-run (optional; describe-only mode)
# output: stdout PUSHED log line per applied push; DRY-RUN line in dry-run mode
# output: writes hub-side file + lockfile entry
# output: exit-codes 0 ok, 1 missing-lockfile-or-file-not-found-or-missing-positional
# caller: skill:/ccanvil-push
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: file_hash
# depends-on: safe_lock_mv
# depends-on: mktemp
# depends-on: mkdir
# depends-on: cp
# depends-on: die
# side-effect: writes-hub-files
# side-effect: writes-lockfile-entries
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-arg
# failure-mode: file-not-found | exit=1 | visible=stderr-die-File-not-found | mitigation=verify-local-path
# contract: dry-run-makes-no-mutations
# contract: status-transition-depends-on-prior-origin
# anchor: BTS-243 (manifest seed)
cmd_push_apply() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
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

  # @failure-mode: file-not-found
  [[ -f "$file" ]] || die "File not found: $file"

  if $dry_run; then
    echo "DRY-RUN: would push $file ($status)"
    return 0
  fi

  # Ensure target directory exists in hub
  mkdir -p "$(dirname "$hub_source/$file")"

  # Copy to hub
  # @side-effect: writes-hub-files
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
  # @side-effect: writes-lockfile-entries
  safe_lock_mv "$tmp" "$LOCKFILE" "push-apply $file"

  echo "PUSHED: $file ($status → pushed)"
}

# push-finalize: Commit in hub repo, update version
# Usage: push-finalize <commit-message> [--dry-run]
# @manifest
# purpose: Stage and commit every staged push in the hub working tree with the operator-supplied message, then stamp the lockfile with the new hub HEAD so /ccanvil-push leaves both sides on a matching version
# input: positional <commit-message>
# input: --dry-run (optional; describe-only mode)
# output: stdout Committed-in-hub status line + Push finalized banner with new version
# output: writes hub git commit + lockfile hub_version + synced_at
# output: exit-codes 0 ok, 1 missing-lockfile-or-missing-message
# caller: skill:/ccanvil-push
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: get_hub_source_raw
# depends-on: cmd_lock_set_version
# depends-on: git
# depends-on: die
# side-effect: writes-hub-commit
# side-effect: writes-lockfile-version
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-message | exit=1 | visible=stderr-die-Usage | mitigation=supply-commit-message
# contract: dry-run-makes-no-mutations
# contract: warns-when-no-new-commit-produced
# anchor: BTS-243 (manifest seed)
cmd_push_finalize() {
  # @failure-mode: missing-lockfile
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
  # @failure-mode: missing-message
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
  # @side-effect: writes-hub-commit
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

  # @side-effect: writes-lockfile-version
  cmd_lock_set_version "$new_version"

  echo "Push finalized. Hub version: $new_version"
}

# promote: Full promote workflow for a single file
# Usage: promote <file>
# @manifest
# purpose: Run the end-to-end promote-a-local-only-file workflow — copy the file into the hub tree, flip the lockfile entry to origin=hub status=promoted, commit in the hub repo, then stamp the lockfile version — so operators can promote in one verb without orchestrating push-apply + push-finalize manually
# input: positional <file>
# output: stdout PROMOTED log line with new hub version (or SKIP when already clean/promoted)
# output: writes hub-side file + lockfile entry + hub commit + lockfile hub_version
# output: exit-codes 0 ok-or-skip, 1 missing-lockfile-or-missing-positional-or-non-local-only-status-or-file-not-found
# caller: skill:/ccanvil-promote
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: get_hub_source_raw
# depends-on: file_hash
# depends-on: safe_lock_mv
# depends-on: cmd_lock_set_version
# depends-on: mktemp
# depends-on: mkdir
# depends-on: cp
# depends-on: basename
# depends-on: pwd
# depends-on: git
# depends-on: die
# side-effect: writes-hub-files
# side-effect: writes-lockfile-entries
# side-effect: writes-hub-commit
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-arg
# failure-mode: status-not-local-only | exit=1 | visible=stderr-die-Cannot-promote | mitigation=use-push-apply-for-modified-files
# failure-mode: file-not-found | exit=1 | visible=stderr-die-File-not-found | mitigation=verify-local-path
# contract: idempotent-on-already-promoted-or-clean
# contract: end-to-end-promote-in-one-call
# anchor: BTS-243 (manifest seed)
cmd_promote() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
  local file="${1:?Usage: ccanvil-sync.sh promote <file>}"

  local status
  status=$(jq -r --arg f "$file" '.files[$f].status // "unknown"' "$LOCKFILE")

  if [[ "$status" == "clean" || "$status" == "promoted" ]]; then
    echo "SKIP: $file is already $status — nothing to promote."
    exit 0
  fi

  if [[ "$status" != "local-only" ]]; then
    # @failure-mode: status-not-local-only
    die "Cannot promote: $file has status '$status'. Only local-only files can be promoted."
  fi

  # @failure-mode: file-not-found
  [[ -f "$file" ]] || die "File not found: $file"

  local hub_source
  hub_source=$(get_hub_source)
  local hub_root
  hub_root=$(get_hub_source_raw)

  # Copy to hub
  mkdir -p "$(dirname "$hub_source/$file")"
  # @side-effect: writes-hub-files
  cp "$file" "$hub_source/$file"

  # Update lockfile
  local new_hash
  new_hash=$(file_hash "$file")
  local tmp; tmp=$(mktemp)
  jq --arg f "$file" --arg h "$new_hash" \
    '.files[$f].origin = "hub" | .files[$f].hub_hash = $h | .files[$f].local_hash = $h | .files[$f].status = "promoted"' \
    "$LOCKFILE" > "$tmp" || true
  # @side-effect: writes-lockfile-entries
  safe_lock_mv "$tmp" "$LOCKFILE" "promote $file"

  # Commit in hub
  # @side-effect: writes-hub-commit
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
# @manifest
# purpose: Flip a clean lockfile entry to status=modified so the next /ccanvil-pull surfaces a diff instead of auto-updating — operators use this to take ownership of a hub-tracked file without immediately diverging the content
# input: positional <file>
# output: stdout DEMOTED log line (or SKIP when already modified/local-only)
# output: writes lockfile status field for the entry
# output: exit-codes 0 ok-or-skip, 1 missing-lockfile-or-missing-positional-or-non-clean-status
# caller: skill:/ccanvil-demote
# depends-on: jq
# depends-on: require_lockfile
# depends-on: safe_lock_mv
# depends-on: mktemp
# depends-on: die
# side-effect: writes-lockfile-status
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-file-arg
# failure-mode: status-not-clean | exit=1 | visible=stderr-die-Cannot-demote | mitigation=only-clean-files-can-be-demoted
# contract: idempotent-on-already-modified-or-local-only
# anchor: BTS-243 (manifest seed)
cmd_demote() {
  # @failure-mode: missing-lockfile
  require_lockfile
  # @failure-mode: missing-positional
  local file="${1:?Usage: ccanvil-sync.sh demote <file>}"

  local status
  status=$(jq -r --arg f "$file" '.files[$f].status // "unknown"' "$LOCKFILE")

  if [[ "$status" == "modified" || "$status" == "local-only" ]]; then
    echo "SKIP: $file is already $status — effectively demoted."
    exit 0
  fi

  if [[ "$status" != "clean" ]]; then
    # @failure-mode: status-not-clean
    die "Cannot demote: $file has status '$status'. Only clean files can be demoted."
  fi

  # Mark as modified (prevents auto-update on future pulls)
  local tmp; tmp=$(mktemp)
  jq --arg f "$file" '.files[$f].status = "modified"' "$LOCKFILE" > "$tmp" || true
  # @side-effect: writes-lockfile-status
  safe_lock_mv "$tmp" "$LOCKFILE" "demote $file"

  # Log

  echo "DEMOTED: $file (future pulls will show diff instead of auto-updating)"
}

# @manifest
# purpose: List every tracked file in the current project plus (if a lockfile is present) every tracked file in the hub source — diagnostic verb operators run when the lockfile classification is unclear or when verifying a scan_*-helper change
# input: (none)
# output: stdout two indented sections (Tracked files in project / Tracked files in hub) with one path per line
# output: exit-codes 0 ok
# depends-on: scan_tracked_files
# depends-on: scan_hub_files
# depends-on: get_hub_source
# side-effect: pure-no-mutations
# failure-mode: hub-section-omitted | exit=0 | visible=stdout-section-absent | mitigation=run-init-first-to-create-lockfile
# contract: project-section-always-emitted
# contract: hub-section-conditional-on-lockfile-presence
# anchor: BTS-244 (manifest seed)
cmd_scan() {
  # @side-effect: pure-no-mutations
  # @failure-mode: hub-section-omitted
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
# @manifest
# purpose: First-time-setup or major-restructuring verb that copies every hub-tracked file into the current project (section-merging delimited markdown, plain-copying everything else), removes legacy stale-named files, renames pre-ccanvil scaffold.json → ccanvil.json, and re-runs cmd_init to rebuild the lockfile in one shot
# input: positional <hub-path>
# input: --dry-run (optional; describe-only mode)
# output: stdout per-file COPIED/MERGED/REMOVED/RENAMED lines plus a final MIGRATE banner
# output: writes target files + lockfile (rebuilt by cmd_init)
# output: exit-codes 0 ok, 1 hub-not-found-or-missing-positional
# depends-on: cmd_init
# depends-on: cmd_section_merge
# depends-on: scan_hub_files
# depends-on: grep
# depends-on: rm
# depends-on: mv
# depends-on: mkdir
# depends-on: cp
# depends-on: die
# side-effect: writes-target-files
# side-effect: removes-stale-files
# side-effect: renames-scaffold-json
# side-effect: rebuilds-lockfile
# failure-mode: hub-not-found | exit=1 | visible=stderr-die-Hub-not-found-at | mitigation=verify-hub-path
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-hub-path
# contract: dry-run-makes-no-mutations
# contract: destructive-warning-emitted-before-execution
# anchor: BTS-244 (manifest seed)
cmd_migrate() {
  # @failure-mode: missing-positional
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

  # @failure-mode: hub-not-found
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
        # @side-effect: removes-stale-files
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
      # @side-effect: renames-scaffold-json
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
    # @side-effect: writes-target-files
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
  # @side-effect: rebuilds-lockfile
  cmd_init "$hub_path"
  echo ""
  echo "MIGRATE complete. Run 'git add -A && git commit' to finalize."
}

# register: Add the current project to the hub's registry.
# Run from a downstream project. Reads hub path from lockfile.
# @manifest
# purpose: Register the current downstream project with the hub by upserting an entry keyed by node UUID into hub's .ccanvil/registry.json (preserving last_synced fields), auto-committing the local UUID file so broadcast's dirty-tree pre-check passes, and appending a register event to the hub's events log
# input: (none)
# output: stdout REGISTERED status line with name + portable path + node UUID
# output: writes hub registry.json + hub events log + commits local node UUID file
# output: exit-codes 0 ok, 1 missing-lockfile-or-registry-write-failure
# caller: cmd_init
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source_raw
# depends-on: get_or_create_node_uuid
# depends-on: persist_node_uuid
# depends-on: normalize_path
# depends-on: timestamp
# depends-on: commit_node_file
# depends-on: append_event
# depends-on: basename
# depends-on: pwd
# depends-on: mktemp
# depends-on: mkdir
# depends-on: mv
# depends-on: rm
# depends-on: die
# side-effect: writes-hub-registry
# side-effect: appends-hub-events-log
# side-effect: commits-local-node-uuid
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: registry-write-failure | exit=1 | visible=stderr-die-Failed-to-update-registry | mitigation=verify-hub-write-permissions
# contract: idempotent-by-node-uuid-key
# contract: preserves-existing-last_synced-fields
# anchor: BTS-244 (manifest seed)
cmd_register() {
  # @failure-mode: missing-lockfile
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
    # @side-effect: writes-hub-registry
    mv "$tmp" "$registry"
  else
    rm -f "$tmp"
    # @failure-mode: registry-write-failure
    die "Failed to update registry"
  fi

  echo "REGISTERED: $node_name ($portable_path) [$node_uuid]"

  # Auto-commit the node UUID file so broadcast's dirty-tree pre-check passes
  # @side-effect: commits-local-node-uuid
  commit_node_file ".claude/ccanvil.local.json" \
    "chore(ccanvil): register node $node_name [$node_uuid]"

  # Record a register event in the hub's local events log
  # @side-effect: appends-hub-events-log
  append_event "$hub_root" "$(jq -nc \
    --arg u "$node_uuid" --arg n "$node_name" --arg p "$portable_path" \
    '{event:"register",node_uuid:$u,node_name:$n,path:$p}')"
}

# relocate: Re-associate Claude Code conversation history after `mv`.
# Renames ~/.claude/projects/<old-encoded> → <new-encoded> (new = $(pwd))
# and rewrites embedded "cwd":"<old-path>" fields in every .jsonl session file.
# Usage: ccanvil-sync.sh relocate <old-absolute-path>
# @manifest
# purpose: After an operator runs `mv` to relocate a project directory, re-associate Claude Code's per-project conversation history by renaming ~/.claude/projects/<old-encoded>/ → <new-encoded>/ and rewriting embedded `cwd:` fields inside every captured session jsonl so /recall and /stasis continue to find prior history
# input: positional <old-absolute-path>
# output: stdout RELOCATED log line; "No history dir found" line when already relocated
# output: writes ~/.claude/projects/<new-encoded>/ directory rename + sed rewrites of cwd fields in jsonl files
# output: exit-codes 0 ok-or-already-relocated, 1 destination-exists-or-rename-failure, 2 missing-or-non-absolute-old-path
# depends-on: sed
# depends-on: find
# depends-on: pwd
# depends-on: mv
# side-effect: renames-history-dir
# side-effect: rewrites-cwd-fields-in-jsonl
# failure-mode: missing-or-non-absolute-arg | exit=2 | visible=stderr-ERROR-relocate-requires | mitigation=supply-absolute-path
# failure-mode: destination-exists | exit=1 | visible=stderr-ERROR-destination-history-dir-already-exists | mitigation=resolve-collision-manually
# failure-mode: rename-failed | exit=1 | visible=stderr-ERROR-rename-failed | mitigation=verify-permissions
# failure-mode: cwd-rewrite-warning | exit=1 | visible=stderr-WARNING-cwd-rewrite-failed | mitigation=inspect-jsonl-permissions
# contract: idempotent-on-already-relocated
# contract: cowardly-refuses-merge
# anchor: BTS-244 (manifest seed)
cmd_relocate() {
  local old_path="${1:-}"
  if [[ -z "$old_path" || "$old_path" != /* ]]; then
    # @failure-mode: missing-or-non-absolute-arg
    echo "ERROR: relocate requires an absolute <old-path>" >&2
    echo "Usage: ccanvil-sync.sh relocate <old-absolute-path>" >&2
    return 2
  fi

  local new_path
  new_path=$(pwd)

  local old_encoded new_encoded
  old_encoded="${old_path//\//-}"
  new_encoded="${new_path//\//-}"

  local projects_dir="$HOME/.claude/projects"
  local old_dir="$projects_dir/$old_encoded"
  local new_dir="$projects_dir/$new_encoded"

  if [[ ! -d "$old_dir" ]]; then
    echo "No history dir found at $old_dir (already relocated?)"
    return 0
  fi

  if [[ -d "$new_dir" ]]; then
    # @failure-mode: destination-exists
    echo "ERROR: destination history dir already exists: $new_dir" >&2
    echo "       Cowardly refusing to merge. Resolve manually." >&2
    return 1
  fi

  # @side-effect: renames-history-dir
  # @failure-mode: rename-failed
  mv "$old_dir" "$new_dir" || { echo "ERROR: rename failed" >&2; return 1; }

  local rc=0
  local old_field="\"cwd\":\"${old_path}\""
  local new_field="\"cwd\":\"${new_path}\""
  while IFS= read -r -d '' jsonl; do
    # @side-effect: rewrites-cwd-fields-in-jsonl
    # @failure-mode: cwd-rewrite-warning
    sed -i '' "s|${old_field}|${new_field}|g" "$jsonl" 2>/dev/null || \
      sed -i "s|${old_field}|${new_field}|g" "$jsonl" || \
      { echo "WARNING: cwd rewrite failed for $jsonl" >&2; rc=1; }
  done < <(find "$new_dir" -name '*.jsonl' -print0)

  echo "RELOCATED: $old_dir -> $new_dir"
  return $rc
}

# migrate-stasis-artifact: One-time migration from legacy checkpoint/catchup
# naming to stasis/recall. Idempotent. Intended to run inside a node's project
# dir, either standalone or via broadcast's per-node hook.
#
# Actions (each conditional, each idempotent):
#   1. If docs/checkpoint.md exists AND docs/stasis.md does NOT → git mv +
#      commit the rename so history follows.
#   2. If both docs/checkpoint.md AND docs/stasis.md exist → abort with
#      status 1; user must resolve manually (ambiguous state).
#   3. If .claude/commands/catchup.md exists → git rm + commit (hub-owned
#      file, now removed).
#
# Exit: 0 on success or no-op; 1 on ambiguous both-exist state.
# @manifest
# purpose: One-time idempotent migration that renames the prior-vocabulary stasis artifact to the current name and removes the prior-vocabulary recall command file (using git mv when paths are tracked so history follows); intended for downstream nodes upgrading past the BTS-22 vocabulary rollover
# input: (none)
# output: stdout MIGRATED + REMOVED log lines per applied action
# output: writes file rename + file removal + single commit when either action fires
# output: exit-codes 0 ok-or-no-op, 1 ambiguous-both-old-and-new-exist
# depends-on: git
# depends-on: mv
# depends-on: rm
# depends-on: pwd
# side-effect: renames-stasis-artifact
# side-effect: removes-retired-command-file
# side-effect: writes-migration-commit
# failure-mode: ambiguous-both-exist | exit=1 | visible=stderr-ERROR-both-files-exist | mitigation=remove-one-manually-then-rerun
# contract: idempotent-on-already-migrated
# contract: single-commit-captures-both-actions
# anchor: BTS-244 (manifest seed)
cmd_migrate_stasis_artifact() {
  local project_dir
  project_dir=$(pwd)

  local did_work=false

  local old_artifact="$project_dir/docs/checkpoint.md"
  local new_artifact="$project_dir/docs/stasis.md"
  local old_catchup="$project_dir/.claude/commands/catchup.md"

  # Step 1/2: artifact rename (or conflict detection)
  if [[ -f "$old_artifact" && -f "$new_artifact" ]]; then
    # @failure-mode: ambiguous-both-exist
    echo "ERROR: both docs/checkpoint.md and docs/stasis.md exist." >&2
    echo "       Migration can't choose between them. Resolve manually:" >&2
    echo "       1. Decide which content to keep." >&2
    echo "       2. Remove the other file and commit." >&2
    echo "       3. Re-run migrate-stasis-artifact." >&2
    return 1
  fi

  if [[ -f "$old_artifact" && ! -f "$new_artifact" ]]; then
    # Prefer git mv for history preservation; fall back to plain mv if git fails
    # (e.g., file not tracked).
    # @side-effect: renames-stasis-artifact
    if git -C "$project_dir" ls-files --error-unmatch "docs/checkpoint.md" >/dev/null 2>&1; then
      (cd "$project_dir" && git mv "docs/checkpoint.md" "docs/stasis.md") || {
        mv "$old_artifact" "$new_artifact"
      }
    else
      mv "$old_artifact" "$new_artifact"
      (cd "$project_dir" && git add "docs/stasis.md" 2>/dev/null || true)
    fi
    did_work=true
    echo "MIGRATED: docs/checkpoint.md → docs/stasis.md"
  fi

  # Step 3: remove legacy catchup command
  if [[ -f "$old_catchup" ]]; then
    # @side-effect: removes-retired-command-file
    if git -C "$project_dir" ls-files --error-unmatch ".claude/commands/catchup.md" >/dev/null 2>&1; then
      (cd "$project_dir" && git rm -q ".claude/commands/catchup.md") || {
        rm -f "$old_catchup"
      }
    else
      rm -f "$old_catchup"
    fi
    did_work=true
    echo "REMOVED: .claude/commands/catchup.md (superseded by /recall skill)"
  fi

  # Single commit captures both actions if either occurred.
  if $did_work; then
    # @side-effect: writes-migration-commit
    (cd "$project_dir" && \
      ALLOW_MAIN=1 git -c commit.gpgsign=false commit -q \
        -m "chore(stasis-migration): rename checkpoint/catchup artifacts" \
        2>/dev/null || true)
  fi

  return 0
}

# registry: List all registered downstream projects.
# Can be run from anywhere with a lockfile.
# @manifest
# purpose: Read the hub-side .ccanvil/registry.json and render every registered downstream node (name, UUID, portable path, registered_at, last_synced, version) so operators can audit the live downstream-node fleet
# input: (none)
# output: stdout formatted human-readable listing
# output: exit-codes 0 ok-or-no-registry, 1 missing-lockfile
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source_raw
# side-effect: reads-hub-registry
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: no-registry-yet | exit=0 | visible=stdout-No-registry-found | mitigation=register-first-downstream-node
# contract: read-only
# anchor: BTS-244 (manifest seed)
cmd_registry() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-hub-registry
  require_lockfile
  local hub_root
  hub_root=$(get_hub_source_raw)
  local registry="$hub_root/.ccanvil/registry.json"

  if [[ ! -f "$registry" ]]; then
    # @failure-mode: no-registry-yet
    echo "No registry found. Run 'ccanvil-sync.sh register' from a downstream project."
    return 0
  fi

  echo "Registered downstream projects:"
  echo ""
  jq -r '.nodes | to_entries[] | "  \(.value.name) [\(.key)]\n    path: \(.value.path // .key)\n    registered: \(.value.registered_at)  |  last_synced: \(.value.last_synced // "never")  |  version: \(.value.last_synced_version // "never")"' "$registry"
}

# events: Print the hub's local events log as newline-delimited JSON.
# Filters: --event <type>, --node <uuid-or-name>, --since <epoch>.
# The events log is machine-local audit state (gitignored) — previously,
# these events were git commits on main; now they live in .ccanvil/events.log.
# Usage: ccanvil-sync.sh events [--event TYPE] [--node UUID|NAME] [--since EPOCH]
# @manifest
# purpose: Read the hub's machine-local events log (gitignored audit trail of register/broadcast/etc. operations) and emit filtered JSONL — supports filtering by event type, node UUID/name, and minimum timestamp so operators can audit hub history without parsing the file directly
# input: --event <type>
# input: --node <uuid-or-name>
# input: --since <epoch>
# output: stdout newline-delimited JSON (one object per matching event)
# output: exit-codes 0 ok-or-no-events-log, 2 unknown-flag
# depends-on: jq
# depends-on: get_hub_source_raw
# depends-on: pwd
# side-effect: reads-hub-events-log
# failure-mode: unknown-flag | exit=2 | visible=stderr-Unknown-events-flag | mitigation=use-documented-flag-name
# failure-mode: no-events-log | exit=0 | visible=empty-stdout | mitigation=register-or-broadcast-first
# contract: read-only
# contract: emits-empty-when-log-missing
# anchor: BTS-244 (manifest seed)
cmd_events() {
  local filter_event="" filter_node="" filter_since=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --event) filter_event="$2"; shift 2 ;;
      --node)  filter_node="$2";  shift 2 ;;
      --since) filter_since="$2"; shift 2 ;;
      # @failure-mode: unknown-flag
      *) echo "Unknown events flag: $1" >&2; return 2 ;;
    esac
  done

  local hub_root
  if [[ -f "$LOCKFILE" ]]; then
    hub_root=$(get_hub_source_raw)
  else
    hub_root=$(pwd)
  fi
  local log_file="$hub_root/.ccanvil/events.log"
  # @failure-mode: no-events-log
  # @side-effect: reads-hub-events-log
  [[ -f "$log_file" ]] || return 0

  local jq_filter='.'
  [[ -n "$filter_event" ]] && jq_filter="${jq_filter} | select(.event == \"$filter_event\")"
  [[ -n "$filter_node"  ]] && jq_filter="${jq_filter} | select(.node_uuid == \"$filter_node\" or .node_name == \"$filter_node\")"
  [[ -n "$filter_since" ]] && jq_filter="${jq_filter} | select(.ts >= $filter_since)"

  jq -c "$jq_filter" "$log_file" 2>/dev/null
}

# broadcast: Push hub updates to all registered downstream nodes.
# Runs deterministic phases only (auto-update, section-merge, finalize).
# Conflicts are collected and reported, not resolved.
# Usage: broadcast [--dry-run]
# @manifest
# purpose: Push hub updates to every registered downstream node by iterating registry.json — for each node runs pre-check, stasis-rename migration, pull-plan classification, then deterministic auto-update + section-merge phases — collects conflicts and skip reasons for reporting and stamps registry's last_synced + last_synced_version per synced node so the operator can audit fleet-wide hub broadcast in one verb
# input: --dry-run (optional; describe-only mode)
# output: stdout per-node section banner + per-action log lines + final Broadcast Summary (Synced / Skipped / Unreachable + skip reasons + pending conflicts)
# output: writes registry.json (per-node last_synced fields) + appends hub events log
# output: exit-codes 0 ok-or-no-registered-nodes
# depends-on: jq
# depends-on: get_hub_source_raw
# depends-on: migrate_registry
# depends-on: append_event
# depends-on: expand_path
# depends-on: timestamp
# depends-on: git
# depends-on: bash
# depends-on: pwd
# depends-on: head
# depends-on: sed
# depends-on: grep
# depends-on: mktemp
# depends-on: mv
# depends-on: rm
# side-effect: writes-per-node-pull-output
# side-effect: writes-registry-last-synced
# side-effect: appends-hub-events-log
# failure-mode: no-registry | exit=0 | visible=stdout-No-registered-nodes | mitigation=register-first-downstream-node
# failure-mode: empty-registry | exit=0 | visible=stdout-No-registered-nodes | mitigation=register-first-downstream-node
# failure-mode: per-node-pre-check-failure | exit=0 | visible=stdout-SKIP-pre-check-failed | mitigation=clean-the-failing-node-tree-and-retry
# failure-mode: per-node-stasis-rename-ambiguous | exit=0 | visible=stdout-SKIP-stasis-migration | mitigation=resolve-the-ambiguous-stasis-state-on-the-node
# contract: dry-run-makes-no-mutations
# contract: registry-update-batched-after-loop-to-avoid-mid-broadcast-dirty-tree
# anchor: BTS-244 (manifest seed)
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
    # @failure-mode: no-registry
    echo "No registered nodes. Run 'ccanvil-sync.sh register' from a downstream project."
    return 0
  fi

  local node_count
  node_count=$(jq '.nodes | length' "$registry")
  if [[ "$node_count" -eq 0 ]]; then
    # @failure-mode: empty-registry
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
  local legacy_count_before
  legacy_count_before=$(jq -r '[.nodes | keys[] | select(test("^[0-9a-f]{8}-[0-9a-f]{4}") | not)] | length' \
    "$registry" 2>/dev/null || echo "0")
  migrate_registry "$registry"

  # Record migration event only if legacy entries were actually rewritten
  if ! $dry_run && [[ "$legacy_count_before" -gt 0 ]]; then
    append_event "$hub_root" "$(jq -nc \
      --argjson c "$legacy_count_before" \
      '{event:"migrate_legacy_keys",count:$c}')"
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
      # @failure-mode: per-node-pre-check-failure
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

    # Stasis-rename migration. Runs once per node; idempotent afterward.
    # Exit 1 from the migration means ambiguous state (both files exist) —
    # skip the node so the user can resolve manually.
    local migration_out
    migration_out=$(cd "$node_path" && bash "$node_path/.ccanvil/scripts/ccanvil-sync.sh" migrate-stasis-artifact 2>&1) || {
      # @failure-mode: per-node-stasis-rename-ambiguous
      echo "  SKIP: stasis-migration refused (both docs/checkpoint.md and docs/stasis.md exist)"
      echo "  $migration_out" | head -6
      skipped=$((skipped + 1))
      skip_reasons+="  $node_name: stasis-migration ambiguous state"$'\n'
      continue
    }
    if echo "$migration_out" | grep -qE "^(MIGRATED|REMOVED):"; then
      echo "$migration_out" | sed 's/^/  /'
      if ! $dry_run; then
        # @side-effect: appends-hub-events-log
        append_event "$hub_root" "$(jq -nc \
          --arg u "$node_uuid" \
          --arg n "$node_name" \
          '{event:"migrate_stasis_rename",node_uuid:$u,node_name:$n}')"
      fi
    fi

    # ideas-to-linear migration hint (AC-28). Broadcast detects legacy
    # docs/ideas.md per node and prints a one-line nudge — never auto-
    # migrates (each node's Linear auth + project scope is different;
    # migration stays per-node by design).
    if (cd "$node_path" && git ls-files --error-unmatch docs/ideas.md >/dev/null 2>&1); then
      echo "  HINT: $node_name: docs/ideas.md still tracked — run 'docs-check.sh idea-migrate' on that node"
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
      # @side-effect: writes-per-node-pull-output
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
      local prior_version
      prior_version=$(jq -r --arg u "$su" '.nodes[$u].last_synced_version // "unknown"' "$registry")
      local su_name
      su_name=$(jq -r --arg u "$su" '.nodes[$u].name // "unknown"' "$registry")

      local tmp; tmp=$(mktemp)
      jq --arg u "$su" --arg t "$sync_ts" --arg v "$hub_version" \
        '.nodes[$u].last_synced = $t | .nodes[$u].last_synced_version = $v' \
        "$registry" > "$tmp" || true
      if [[ -s "$tmp" ]] && jq empty "$tmp" 2>/dev/null; then
        # @side-effect: writes-registry-last-synced
        mv "$tmp" "$registry"
      else
        rm -f "$tmp"
      fi

      # Record per-node sync event in the hub's local audit log
      append_event "$hub_root" "$(jq -nc \
        --arg u "$su" --arg n "$su_name" --arg fv "$prior_version" --arg tv "$hub_version" \
        '{event:"broadcast_sync",node_uuid:$u,node_name:$n,from_version:$fv,to_version:$tv}')"
    done <<< "$synced_uuids"
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
# BTS-116: broadcast-resolve-auto — algorithmic resolution of
# .claude/ccanvil.json conflicts. Classifies the divergence between local
# and hub copies into four states: take-hub (content-identical), keep-local
# (local strictly extends hub), requires-review (value-divergence or
# local-removed-keys), no-conflict (both files match or both missing).
# Auto-applies the deterministic resolutions via the existing pull-apply
# primitives; surfaces the rest as JSON for manual review.
#
# Out of scope: other file types, hub-side --all iteration, auto-commit.
# Per spec (BTS-116). Reuses file_hash + cmd_pull_apply; no new primitives.
# ---------------------------------------------------------------------------

# @manifest
# purpose: Algorithmically classify divergence between local and hub copies of .claude/ccanvil.json into one of four resolution states (take-hub when content-identical, keep-local when local strictly extends hub, requires-review on value-divergence or local-removed-keys, no-conflict when both sides match or both missing) and auto-apply deterministic resolutions via cmd_pull_apply so /ccanvil-broadcast can resolve config conflicts without operator interaction
# input: --dry-run (optional; describe-only mode)
# output: stdout single JSON envelope {file, resolution, applied, reason, hub_hash, local_hash, +optional removed_keys/divergent_keys}
# output: writes target ccanvil.json + lockfile entry on take-hub or keep-local
# output: exit-codes 0 ok-or-no-conflict, 2 not-a-ccanvil-node, 3 requires-review-or-one-side-missing
# depends-on: jq
# depends-on: get_hub_source
# depends-on: file_hash
# depends-on: cmd_pull_apply
# side-effect: writes-target-files-on-resolve
# side-effect: writes-lockfile-entries-on-resolve
# failure-mode: not-a-ccanvil-node | exit=2 | visible=stderr-broadcast-resolve-auto-not-a-ccanvil-node | mitigation=run-init-first
# failure-mode: one-side-missing | exit=3 | visible=stdout-resolution-requires-review | mitigation=manually-decide-which-side-to-keep
# failure-mode: requires-review-divergence | exit=3 | visible=stdout-resolution-requires-review | mitigation=manually-merge-divergent-or-removed-keys
# contract: dry-run-makes-no-mutations
# contract: emits-stable-json-envelope-shape
# anchor: BTS-244 (manifest seed)
cmd_broadcast_resolve_auto() {
  local dry_run=false
  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
  fi

  if [[ ! -f "$LOCKFILE" ]]; then
    # @failure-mode: not-a-ccanvil-node
    echo "broadcast-resolve-auto: not a ccanvil node (no .ccanvil/ccanvil.lock)" >&2
    exit 2
  fi

  local file=".claude/ccanvil.json"
  local hub_root
  hub_root=$(get_hub_source)
  local hub_file="$hub_root/$file"
  local local_file="$file"

  local local_hash hub_hash
  local_hash=$(file_hash "$local_file")
  hub_hash=$(file_hash "$hub_file")

  # No-conflict: both files missing.
  if [[ "$local_hash" == "MISSING" && "$hub_hash" == "MISSING" ]]; then
    jq -n --arg f "$file" --arg lh "$local_hash" --arg hh "$hub_hash" '{
      file: $f,
      resolution: "no-conflict",
      applied: false,
      reason: "no-conflict",
      hub_hash: $hh,
      local_hash: $lh
    }'
    return 0
  fi

  # Take-hub: byte-identical content (also covers the no-conflict case
  # where the file is identical on both sides — same outcome from the
  # operator's perspective: nothing to merge).
  if [[ "$local_hash" == "$hub_hash" ]]; then
    local applied_val=false
    if ! $dry_run; then
      # @side-effect: writes-target-files-on-resolve
      # @side-effect: writes-lockfile-entries-on-resolve
      if cmd_pull_apply "$file" take-hub >/dev/null 2>&1; then
        applied_val=true
      fi
    fi
    jq -n --arg f "$file" --arg lh "$local_hash" --arg hh "$hub_hash" --argjson applied "$applied_val" '{
      file: $f,
      resolution: "take-hub",
      applied: $applied,
      reason: "content-identical",
      hub_hash: $hh,
      local_hash: $lh
    }'
    return 0
  fi

  # Both files must exist for the structural superset / divergence checks.
  if [[ "$local_hash" == "MISSING" || "$hub_hash" == "MISSING" ]]; then
    # @failure-mode: one-side-missing
    jq -n --arg f "$file" --arg lh "$local_hash" --arg hh "$hub_hash" '{
      file: $f,
      resolution: "requires-review",
      applied: false,
      reason: "one-side-missing",
      hub_hash: $hh,
      local_hash: $lh
    }'
    exit 3
  fi

  # Compute structural diff between hub and local objects.
  # removed_keys: in hub but not in local (top-level key set difference).
  # divergent_keys: in both, but values are not deep-equal.
  local removed_keys divergent_keys
  removed_keys=$(jq -n --slurpfile h "$hub_file" --slurpfile l "$local_file" \
    '($h[0] | keys_unsorted) - ($l[0] | keys_unsorted)')
  divergent_keys=$(jq -n --slurpfile h "$hub_file" --slurpfile l "$local_file" '
    [($h[0] | keys_unsorted)[] as $k | select(($l[0] | has($k)) and ($h[0][$k] != $l[0][$k])) | $k]
  ')

  local removed_count divergent_count
  removed_count=$(echo "$removed_keys" | jq 'length')
  divergent_count=$(echo "$divergent_keys" | jq 'length')

  # Keep-local: hub keys are all present in local with deep-equal values
  # (no removed keys, no divergent keys). Local-superset is the case
  # where local additions sit alongside hub-canonical content.
  if [[ "$removed_count" -eq 0 && "$divergent_count" -eq 0 ]]; then
    local applied_val=false
    if ! $dry_run; then
      if cmd_pull_apply "$file" keep-local >/dev/null 2>&1; then
        applied_val=true
      fi
    fi
    jq -n --arg f "$file" --arg lh "$local_hash" --arg hh "$hub_hash" --argjson applied "$applied_val" '{
      file: $f,
      resolution: "keep-local",
      applied: $applied,
      reason: "local-superset-of-hub",
      hub_hash: $hh,
      local_hash: $lh
    }'
    return 0
  fi

  # Requires-review: prefer the most-specific reason (removed > divergent).
  # @failure-mode: requires-review-divergence
  if [[ "$removed_count" -gt 0 ]]; then
    jq -n --arg f "$file" --arg lh "$local_hash" --arg hh "$hub_hash" --argjson removed "$removed_keys" '{
      file: $f,
      resolution: "requires-review",
      applied: false,
      reason: "local-removed-keys",
      hub_hash: $hh,
      local_hash: $lh,
      removed_keys: $removed
    }'
  else
    jq -n --arg f "$file" --arg lh "$local_hash" --arg hh "$hub_hash" --argjson divergent "$divergent_keys" '{
      file: $f,
      resolution: "requires-review",
      applied: false,
      reason: "value-divergence",
      hub_hash: $hh,
      local_hash: $lh,
      divergent_keys: $divergent
    }'
  fi
  exit 3
}

# ---------------------------------------------------------------------------
# Stack commands
# ---------------------------------------------------------------------------

# @manifest
# purpose: Sync hub's global-commands/ccanvil-*.md files into the operator's user-level ~/.claude/commands/ directory — copies new files, skips byte-identical, surfaces conflicts (or overwrites with --force) so global slash commands stay aligned with the hub without polluting the user namespace
# input: --force (optional; overwrite conflicts instead of reporting)
# output: stdout per-conflict diff lines + final JSON {copied, skipped, conflicts}
# output: writes ~/.claude/commands/ccanvil-*.md files
# output: exit-codes 0 ok, 1 missing-lockfile-or-no-HOME
# caller: skill:/ccanvil-pull-globals
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: file_hash
# depends-on: basename
# depends-on: mkdir
# depends-on: cp
# depends-on: diff
# depends-on: die
# side-effect: writes-user-global-commands
# failure-mode: missing-HOME | exit=1 | visible=stderr-die-HOME-is-not-set | mitigation=ensure-HOME-is-exported
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# contract: only-touches-ccanvil-prefixed-files
# contract: skips-byte-identical-without-warning
# anchor: BTS-244 (manifest seed)
cmd_pull_globals() {
  local force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      *) shift ;;
    esac
  done

  # @failure-mode: missing-HOME
  [[ -n "${HOME:-}" ]] || die "\$HOME is not set"

  # @failure-mode: missing-lockfile
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
      # @side-effect: writes-user-global-commands
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

# @manifest
# purpose: Walk every stack profile under hub/stacks/ and emit a JSON array of {id, description, files} envelopes so /ccanvil-init and operators can preview available tech-stack overlays before applying one
# input: (none)
# output: stdout JSON array (empty array when no stacks dir or no manifests)
# output: exit-codes 0 ok, 1 missing-lockfile
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# side-effect: reads-stack-manifests
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# contract: read-only
# contract: emits-empty-array-when-no-stacks-dir
# anchor: BTS-244 (manifest seed)
cmd_stack_list() {
  # @failure-mode: missing-lockfile
  # @side-effect: reads-stack-manifests
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

# @manifest
# purpose: Apply a tech-stack overlay to the current node — copies stack-owned files (skipping locally-customized targets per the patch-flow rule), section-merges a CLAUDE.md block bracketed by STACK:<id>-START/END markers, merges PreToolUse hooks into settings.json (deduping by command), and registers the stack in ccanvil.json's stacks[] so /ccanvil-init and re-pull workflows preserve the overlay
# input: positional <stack-id>
# output: stdout per-warning lines + final JSON {copied, skipped, errors}
# output: writes target files + lockfile entries + CLAUDE.md section + settings.json hooks + ccanvil.json stacks[]
# output: exit-codes 0 ok, 1 missing-lockfile-or-stack-not-found-or-missing-positional
# caller: cmd_pull_apply
# depends-on: jq
# depends-on: require_lockfile
# depends-on: get_hub_source
# depends-on: file_hash
# depends-on: bash
# depends-on: awk
# depends-on: grep
# depends-on: cat
# depends-on: cp
# depends-on: chmod
# depends-on: mkdir
# depends-on: mv
# depends-on: rm
# depends-on: mktemp
# depends-on: die
# side-effect: writes-target-files
# side-effect: writes-lockfile-entries
# side-effect: writes-claude-md-section
# side-effect: writes-settings-json-hooks
# side-effect: writes-ccanvil-json-stacks
# failure-mode: missing-lockfile | exit=1 | visible=stderr-die-from-require_lockfile | mitigation=run-init-first
# failure-mode: missing-positional | exit=1 | visible=stderr-Usage | mitigation=supply-stack-id
# failure-mode: stack-not-found | exit=1 | visible=stderr-die-Stack-not-found | mitigation=run-stack-list-first
# failure-mode: missing-stack-source-per-entry | exit=0 | visible=stderr-WARNING-Missing-source | mitigation=increments-errors-counter-and-continues
# failure-mode: invalid-settings-merge | exit=0 | visible=stderr-WARNING-settings-json-merge-produced-invalid-JSON | mitigation=increments-errors-counter
# failure-mode: invalid-ccanvil-update | exit=0 | visible=stderr-WARNING-ccanvil-json-update-failed | mitigation=increments-errors-counter
# contract: idempotent-on-already-applied-stack
# contract: skips-locally-customized-files
# anchor: BTS-244 (manifest seed)
cmd_stack_apply() {
  # @failure-mode: missing-positional
  local stack_id="${1:?Usage: ccanvil-sync.sh stack-apply <stack-id>}"
  # @failure-mode: missing-lockfile
  require_lockfile
  local hub_path
  hub_path=$(get_hub_source)
  local stack_dir="$hub_path/hub/stacks/$stack_id"
  local manifest="$stack_dir/manifest.json"

  # @failure-mode: stack-not-found
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
    # @failure-mode: missing-stack-source-per-entry
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
        # @side-effect: writes-target-files
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
    # @side-effect: writes-lockfile-entries
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
        # @side-effect: writes-claude-md-section
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
        # @side-effect: writes-settings-json-hooks
        mv "$tmp" "$settings_path"
      else
        rm -f "$tmp"
        # @failure-mode: invalid-settings-merge
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
    # @side-effect: writes-ccanvil-json-stacks
    mv "$tmp" "$ccanvil_json"
  else
    rm -f "$tmp"
    # @failure-mode: invalid-ccanvil-update
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

# ---------------------------------------------------------------------------
# BTS-21: drift-watchdog substrate primitives.
# Read-only — never mutates the registry, never visits downstream filesystems,
# never commits. Drift detection is purely commit-graph-based: compare each
# registered node's last_synced_version against the current hub HEAD.
# ---------------------------------------------------------------------------

# @manifest
# purpose: Compute per-node drift envelopes by walking the hub's registry.json — for each registered node compares last_synced_version to current HEAD, intersects touched paths with hub's distributable file set, and emits a drift record (node UUID, name, drift_key, paths_drifted, commits_behind, summary) so /drift-watchdog can present a fleet-wide drift view without firing per-node Linear writes
# input: env CCANVIL_REGISTRY (optional path override; defaults to .ccanvil/registry.json)
# output: stdout JSON array of drift records (empty array when registry missing or no drift)
# output: exit-codes 0 ok-or-no-registry-or-no-head
# caller: skill:/drift-watchdog
# depends-on: jq
# depends-on: git
# depends-on: scan_hub_files
# depends-on: comm
# depends-on: grep
# depends-on: sort
# depends-on: shasum
# depends-on: cut
# depends-on: pwd
# side-effect: reads-registry-and-git-history
# failure-mode: missing-registry | exit=0 | visible=stdout-empty-array | mitigation=register-first-downstream-node
# failure-mode: missing-head | exit=0 | visible=stdout-empty-array | mitigation=run-from-git-repo
# contract: filters-out-hub-private-paths-via-tracked_set-intersection
# contract: skips-up-to-date-nodes
# anchor: BTS-244 (manifest seed)
cmd_drift_watchdog_list() {
  # @side-effect: reads-registry-and-git-history
  local registry="${CCANVIL_REGISTRY:-.ccanvil/registry.json}"
  if [[ ! -f "$registry" ]]; then
    # @failure-mode: missing-registry
    echo "[]"
    return 0
  fi
  local head_hash
  head_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
  if [[ -z "$head_hash" ]]; then
    # @failure-mode: missing-head
    echo "[]"
    return 0
  fi

  # Build the canonical set of distributable paths (currently in hub +
  # matching TRACKED_PATTERNS). Used to filter touched paths so the watchdog
  # surfaces only paths that downstream nodes actually receive — hub-private
  # paths (hub/, docs/specs/, docs/sessions/, etc.) are noise here.
  local hub_root
  hub_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local tracked_set
  tracked_set=$(scan_hub_files "$hub_root" 2>/dev/null | sort -u || true)

  # Iterate nodes; for each drifted node, build a record.
  local records="[]"
  local uuid name last_v all_touched filtered paths_json count drift_key summary
  while IFS= read -r uuid; do
    name=$(jq -r --arg u "$uuid" '.nodes[$u].name // ""' "$registry")
    last_v=$(jq -r --arg u "$uuid" '.nodes[$u].last_synced_version // ""' "$registry")
    if [[ -z "$last_v" || "$last_v" == "$head_hash" ]]; then
      continue
    fi
    # Touched paths between last_v..HEAD, deduplicated.
    all_touched=$(git log --name-only --pretty=format: "${last_v}..HEAD" 2>/dev/null \
      | grep -v '^$' | sort -u || true)
    # Intersect with tracked_set so noise from hub-private files is removed.
    if [[ -n "$tracked_set" && -n "$all_touched" ]]; then
      filtered=$(comm -12 <(echo "$all_touched") <(echo "$tracked_set") || true)
    else
      filtered="$all_touched"
    fi
    if [[ -z "$filtered" ]]; then
      continue
    fi
    paths_json=$(echo "$filtered" | jq -R . | jq -s . 2>/dev/null || echo "[]")
    count=$(git rev-list --count "${last_v}..HEAD" 2>/dev/null || echo 0)
    drift_key=$(printf '%s:%s' "$name" "$(echo "$paths_json" | jq -r '. | join("\n")')" \
      | shasum -a 256 | cut -c1-16)
    summary="$count commits behind, $(echo "$paths_json" | jq 'length') tracked paths touched"
    records=$(echo "$records" | jq --arg uuid "$uuid" --arg name "$name" \
      --arg dk "$drift_key" --argjson paths "$paths_json" \
      --argjson cb "$count" --arg summary "$summary" \
      '. + [{node_uuid: $uuid, node_name: $name, drift_key: $dk,
             paths_drifted: $paths, commits_behind: $cb, summary: $summary}]')
  done < <(jq -r '.nodes | keys[]' "$registry" 2>/dev/null)

  echo "$records"
}

# @manifest
# purpose: Probe the runtime preconditions /drift-watchdog needs (Claude CLI in $PATH for headless invocation, and a working linear-query.sh viewer call) so the launchd-scheduled run can fail fast with a clear cause when either dependency is missing
# input: env CCANVIL_LINEAR_QUERY (optional path override)
# output: stdout JSON {claude_p_available, linear_query_works}
# output: exit-codes 0 ok
# caller: skill:/drift-watchdog
# depends-on: jq
# depends-on: bash
# depends-on: command
# side-effect: pure-no-mutations
# failure-mode: never-fails | exit=0 | visible=stdout-bool-flags | mitigation=consumer-checks-flags
# contract: emits-stable-shape-regardless-of-availability
# anchor: BTS-244 (manifest seed)
cmd_drift_watchdog_preflight() {
  # @failure-mode: never-fails
  # @side-effect: pure-no-mutations
  local linear_query="${CCANVIL_LINEAR_QUERY:-.ccanvil/scripts/linear-query.sh}"
  local claude_ok="false" linear_ok="false"
  if command -v claude >/dev/null 2>&1; then
    claude_ok="true"
  fi
  if [[ -x "$linear_query" ]] || [[ -f "$linear_query" ]]; then
    if output=$(bash "$linear_query" viewer 2>/dev/null) && echo "$output" | jq -e '.' >/dev/null 2>&1; then
      linear_ok="true"
    fi
  elif command -v linear-query.sh >/dev/null 2>&1; then
    if output=$(linear-query.sh viewer 2>/dev/null) && echo "$output" | jq -e '.' >/dev/null 2>&1; then
      linear_ok="true"
    fi
  fi
  jq -n --argjson cp "$claude_ok" --argjson lq "$linear_ok" \
    '{claude_p_available: $cp, linear_query_works: $lq}'
}

# @manifest
# purpose: Idempotently install or reload the drift-watchdog launchd LaunchAgent — generates the plist via cmd_drift_watchdog_launchd_print, lints with plutil, optionally unloads the prior entry, copies into ~/Library/LaunchAgents/, loads with launchctl, and verifies via launchctl print so /drift-watchdog's weekly schedule survives operator reboots
# input: --reload (optional; unload the prior entry before installing)
# output: stdout JSON {installed, reloaded, plist_path, verified, +optional error}
# output: writes ~/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist + launchctl state
# output: exit-codes 0 installed-and-verified, 2 plist-generation-or-lint-failed, 3 verify-failed
# caller: skill:/drift-watchdog
# depends-on: jq
# depends-on: cmd_drift_watchdog_launchd_print
# depends-on: launchctl
# depends-on: plutil
# depends-on: command
# depends-on: cp
# depends-on: rm
# depends-on: mkdir
# depends-on: mktemp
# depends-on: id
# depends-on: grep
# side-effect: writes-launchd-plist
# side-effect: loads-launchd-job
# failure-mode: plist-generation-failed | exit=2 | visible=stdout-error-plist-generation-failed | mitigation=verify-print-substrate
# failure-mode: plist-lint-failed | exit=2 | visible=stdout-error-plist-lint-failed | mitigation=inspect-printed-plist
# failure-mode: verify-failed-launchctl-print-rc | exit=3 | visible=stdout-error-verify-failed | mitigation=inspect-launchctl-output
# failure-mode: no-state-in-print-output | exit=3 | visible=stdout-error-no-state-in-print-output | mitigation=manual-launchctl-load
# contract: idempotent-on-already-installed
# contract: workspace-fence-bypass-required
# anchor: BTS-244 (manifest seed)
cmd_drift_watchdog_launchd_install() {
  # BTS-199: idempotent install/reload of the drift-watchdog launchd entry.
  # Wraps the four-step recipe (generate + lint + optional unload + cp + load
  # + verify) into one atomic call. Replaces operator prose that was
  # reformulated by hand 4 separate times during BTS-21 activation.
  #
  # NOTE: writes to ~/Library/LaunchAgents/ which is OUTSIDE the workspace.
  # Operators must invoke with ALLOW_OUTSIDE_WORKSPACE=1 so the workspace-
  # fence hook (guard-workspace.sh) does not block the cp + launchctl steps.
  #
  # Exit codes:
  #   0 — installed + verified
  #   2 — plist-generation-failed | plist-lint-failed (refuses launchctl ops)
  #   3 — verify-failed (entry not loaded after launchctl load)
  local reload=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reload) reload=1; shift ;;
      *) shift ;;
    esac
  done

  local plist_path="$HOME/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist"
  local tmp_plist
  tmp_plist=$(mktemp -t drift-watchdog-plist.XXXXXX)

  # 1. Generate plist
  if [[ "${DRIFT_WATCHDOG_PLIST_FORCE_EMPTY:-0}" == "1" ]]; then
    : > "$tmp_plist"
  else
    cmd_drift_watchdog_launchd_print > "$tmp_plist" 2>/dev/null || true
  fi

  if [[ ! -s "$tmp_plist" ]]; then
    rm -f "$tmp_plist"
    # @failure-mode: plist-generation-failed
    jq -n '{installed:false, reloaded:false, error:"plist-generation-failed"}'
    return 2
  fi

  # 2. Lint with plutil (skip if not available)
  if command -v plutil >/dev/null 2>&1; then
    if ! plutil -lint "$tmp_plist" >/dev/null 2>&1; then
      rm -f "$tmp_plist"
      # @failure-mode: plist-lint-failed
      jq -n '{installed:false, reloaded:false, error:"plist-lint-failed"}'
      return 2
    fi
  else
    echo "WARN: plutil not available, skipping lint" >&2
  fi

  # 3. Optional unload
  local reloaded=false
  if (( reload )); then
    launchctl unload "$plist_path" 2>/dev/null || true
    reloaded=true
  fi

  # 4. Copy plist into place
  mkdir -p "$(dirname "$plist_path")"
  # @side-effect: writes-launchd-plist
  cp "$tmp_plist" "$plist_path"
  rm -f "$tmp_plist"

  # 5. Load (load -w; second invocation may exit non-zero but verify is authoritative)
  # @side-effect: loads-launchd-job
  launchctl load -w "$plist_path" >/dev/null 2>&1 || true

  # 6. Verify via launchctl print. `set -e` is active at script-level — wrap
  # the call in `if !` so a non-zero rc does not abort before we can emit JSON.
  local print_out
  if ! print_out=$(launchctl print "gui/$(id -u)/com.ccanvil.drift-watchdog" 2>&1); then
    # @failure-mode: verify-failed-launchctl-print-rc
    jq -n --arg p "$plist_path" --argjson r "$reloaded" \
      '{installed:true, reloaded:$r, plist_path:$p, verified:false, error:"verify-failed-launchctl-print-rc"}'
    return 3
  fi

  if ! echo "$print_out" | grep -q 'state'; then
    # @failure-mode: no-state-in-print-output
    jq -n --arg p "$plist_path" --argjson r "$reloaded" \
      '{installed:true, reloaded:$r, plist_path:$p, verified:false, error:"no-state-in-print-output"}'
    return 3
  fi

  jq -n --arg p "$plist_path" --argjson r "$reloaded" \
    '{installed:true, reloaded:$r, plist_path:$p, verified:true}'
}

# @manifest
# purpose: Render the drift-watchdog launchd LaunchAgent plist on stdout — bakes in the operator's current $PATH (so claude resolves under launchd's sparse environment), the hub's working dir, and a Mondays-9:13 schedule — so cmd_drift_watchdog_launchd_install has a deterministic plist source
# input: env PATH (embedded into the rendered plist)
# output: stdout XML plist content
# output: exit-codes 0 ok
# caller: cmd_drift_watchdog_launchd_install
# depends-on: git
# depends-on: pwd
# depends-on: sed
# depends-on: cat
# side-effect: pure-no-mutations
# failure-mode: never-fails | exit=0 | visible=stdout-plist | mitigation=consumer-checks-plist-not-empty
# contract: stable-shape-across-invocations
# contract: escapes-XML-special-chars-in-PATH
# anchor: BTS-244 (manifest seed)
cmd_drift_watchdog_launchd_print() {
  # @side-effect: pure-no-mutations
  # @failure-mode: never-fails
  local hub_dir
  hub_dir=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  # launchd's default PATH excludes Homebrew (and most user-installed bins) —
  # `bash -lc` doesn't reliably pick up the operator's profile under launchd.
  # Embed the operator's current PATH at print time so `claude` and friends
  # resolve. The .plist is per-machine anyway; baking in PATH is correct.
  local launchd_path="${PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
  # Escape XML special chars (& < >) — PATH typically has none of these but
  # be defensive.
  local launchd_path_xml
  launchd_path_xml=$(printf '%s' "$launchd_path" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ccanvil.drift-watchdog</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${launchd_path_xml}</string>
  </dict>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>cd "${hub_dir}" &amp;&amp; claude --model claude-opus-4-7 -p "/drift-watchdog" --max-budget-usd 5.00</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${hub_dir}</string>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>1</integer>
    <key>Hour</key>
    <integer>9</integer>
    <key>Minute</key>
    <integer>13</integer>
  </dict>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>${hub_dir}/.ccanvil/drift-watchdog.log</string>
  <key>StandardErrorPath</key>
  <string>${hub_dir}/.ccanvil/drift-watchdog.err</string>
</dict>
</plist>
PLIST
}

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
  retrofit-check)   shift; cmd_retrofit_check "$@" ;;

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
  migrate-stasis-artifact) cmd_migrate_stasis_artifact ;;
  register)         cmd_register ;;
  registry)         cmd_registry ;;
  events)           shift; cmd_events "$@" ;;
  broadcast)        shift; cmd_broadcast "$@" ;;
  broadcast-resolve-auto) shift; cmd_broadcast_resolve_auto "$@" ;;

  # --- Drift watchdog (BTS-21) ---
  drift-watchdog-list)          cmd_drift_watchdog_list ;;
  drift-watchdog-preflight)     cmd_drift_watchdog_preflight ;;
  drift-watchdog-launchd-print) cmd_drift_watchdog_launchd_print ;;
  drift-watchdog-launchd-install) shift; cmd_drift_watchdog_launchd_install "$@" ;;

  # --- Stack commands ---
  stack-list)       cmd_stack_list ;;
  stack-apply)      shift; cmd_stack_apply "$@" ;;

  # --- Global commands sync ---
  pull-globals)     shift; cmd_pull_globals "$@" ;;

  # --- Claude Code history relocation ---
  relocate)         shift; cmd_relocate "$@" ;;

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
