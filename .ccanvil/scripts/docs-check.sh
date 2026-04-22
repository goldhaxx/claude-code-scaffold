#!/usr/bin/env bash
# docs-check.sh — Deterministic docs lifecycle validation.
#
# Usage:
#   docs-check.sh status [docs-dir]      Extract metadata + compute hashes → JSON
#   docs-check.sh validate [docs-dir]    Check alignment between spec, plan, stasis
#   docs-check.sh recommend [docs-dir]   Suggest next action based on document state

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_DOCS_DIR="docs"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# content_hash <file>
# Compute sha256 of content below the metadata blockquote, truncated to 8 chars.
# Metadata = consecutive `>` lines after the first `#` heading.
content_hash() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi

  # Strategy: skip heading line, skip consecutive blockquote lines, hash the rest.
  # 1. Find the first line that is a heading (^# )
  # 2. Skip it, then skip all consecutive > lines
  # 3. Hash everything after that
  local in_header=true
  local past_heading=false
  local body=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if $in_header; then
      # Skip blank lines before heading
      if [[ -z "$line" ]]; then
        continue
      fi
      # Skip the heading line
      if [[ "$line" =~ ^#\  ]] && ! $past_heading; then
        past_heading=true
        continue
      fi
      # After heading, skip blank lines and blockquote metadata
      if $past_heading; then
        if [[ -z "$line" ]]; then
          continue
        elif [[ "$line" =~ ^\> ]]; then
          continue
        else
          in_header=false
        fi
      fi
    fi

    if ! $in_header; then
      body+="$line"$'\n'
    fi
  done < "$file"

  if [[ -z "$body" ]]; then
    echo ""
    return
  fi

  # Strip trailing whitespace per line and ensure final newline for stability
  local normalized
  normalized=$(echo "$body" | sed 's/[[:space:]]*$//')
  echo -n "$normalized" | shasum -a 256 | cut -c1-8
}

# parse_metadata <file>
# Extract blockquote metadata fields from a doc file.
# Returns JSON object with extracted fields, or empty object if no metadata.
parse_metadata() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo '{}'
    return
  fi

  local feature_id=""
  local created=""
  local last_updated=""
  local status_field=""
  local spec_hash=""
  local plan_hash=""

  # Detect YAML frontmatter: first non-empty line is ---
  local first_line
  first_line=$(head -1 "$file")
  if [[ "$first_line" == "---" ]]; then
    # YAML frontmatter mode: parse key: value lines until closing ---
    local in_frontmatter=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "---" ]]; then
        if $in_frontmatter; then
          break  # closing delimiter
        fi
        in_frontmatter=true
        continue
      fi
      if $in_frontmatter; then
        local key="${line%%:*}"
        local val="${line#*: }"
        case "$key" in
          [Ff]eature)        feature_id="$val" ;;
          [Cc]reated)        created="$val" ;;
          [Ss]tatus)         status_field="$val" ;;
          "Last updated"|"last_updated") last_updated="$val" ;;
          "Spec hash"|"spec_hash")       spec_hash="$val" ;;
          "Plan hash"|"plan_hash")       plan_hash="$val" ;;
        esac
      fi
    done < "$file"
  else
    # Blockquote mode: original parser
    local past_heading=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Skip blank lines before heading
      if [[ -z "$line" ]] && ! $past_heading; then
        continue
      fi
      # Skip heading
      if [[ "$line" =~ ^#\  ]] && ! $past_heading; then
        past_heading=true
        continue
      fi
      # After heading, skip blanks before blockquote
      if $past_heading && [[ -z "$line" ]]; then
        continue
      fi
      # Parse blockquote lines
      if $past_heading && [[ "$line" =~ ^\> ]]; then
        local value="${line#> }"
        case "$value" in
          Feature:*)    feature_id="${value#Feature: }" ;;
          Created:*)    created="${value#Created: }" ;;
          "Last updated:"*) last_updated="${value#Last updated: }" ;;
          Status:*)     status_field="${value#Status: }" ;;
          "Spec hash:"*) spec_hash="${value#Spec hash: }" ;;
          "Plan hash:"*) plan_hash="${value#Plan hash: }" ;;
        esac
        continue
      fi
      # First non-blockquote line after heading = end of metadata
      if $past_heading; then
        break
      fi
    done < "$file"
  fi

  # Build JSON
  local json="{"
  local first=true

  add_field() {
    local key="$1" val="$2"
    if [[ -n "$val" ]]; then
      $first || json+=","
      json+="\"$key\":\"$val\""
      first=false
    fi
  }

  add_field "feature_id" "$feature_id"
  add_field "created" "$created"
  add_field "last_updated" "$last_updated"
  add_field "status" "$status_field"
  add_field "spec_hash" "$spec_hash"
  add_field "plan_hash" "$plan_hash"

  json+="}"
  echo "$json"
}

# Update the Status field in a metadata file (handles both blockquote and YAML frontmatter)
update_metadata_status() {
  local file="$1"
  local new_status="$2"
  local first_line
  first_line=$(head -1 "$file")
  if [[ "$first_line" == "---" ]]; then
    # YAML frontmatter: replace Status line between --- delimiters
    sed -i '' "s/^[Ss]tatus: .*/Status: $new_status/" "$file" 2>/dev/null || \
      sed -i "s/^[Ss]tatus: .*/Status: $new_status/" "$file"
  else
    # Blockquote format
    sed -i '' "s/^> Status: .*/> Status: $new_status/" "$file" 2>/dev/null || \
      sed -i "s/^> Status: .*/> Status: $new_status/" "$file"
  fi
}

# doc_entry <file> <doc-name>
# Build a complete JSON entry for one document.
doc_entry() {
  local file="$1"
  local name="$2"

  if [[ ! -f "$file" ]]; then
    echo "{\"exists\":false}"
    return
  fi

  local meta
  meta=$(parse_metadata "$file")

  local hash
  hash=$(content_hash "$file")

  # Merge exists + content_hash into metadata
  if [[ "$meta" == "{}" ]]; then
    # No metadata — unlinked doc
    if [[ -n "$hash" ]]; then
      echo "{\"exists\":true,\"content_hash\":\"$hash\"}"
    else
      echo "{\"exists\":true}"
    fi
  else
    # Has metadata — inject exists and content_hash
    local result
    result=$(echo "$meta" | jq --arg exists "true" --arg hash "$hash" \
      '. + {exists: ($exists == "true")} + (if $hash != "" then {content_hash: $hash} else {} end)')
    echo "$result"
  fi
}

# ---------------------------------------------------------------------------
# cmd_status — Extract metadata + compute content hashes for all docs.
#
# Output: JSON object with spec, plan, stasis entries.
# ---------------------------------------------------------------------------
cmd_status() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"

  local spec_entry plan_entry stasis_entry
  spec_entry=$(doc_entry "$docs_dir/spec.md" "spec")
  plan_entry=$(doc_entry "$docs_dir/plan.md" "plan")
  stasis_entry=$(doc_entry "$docs_dir/stasis.md" "stasis")

  jq -n \
    --argjson spec "$spec_entry" \
    --argjson plan "$plan_entry" \
    --argjson stasis "$stasis_entry" \
    '{spec: $spec, plan: $plan, stasis: $stasis}'
}

# ---------------------------------------------------------------------------
# cmd_validate — Check alignment between spec, plan, and stasis.
#
# Priority order: mismatched > stale-plan > stale-stasis > aligned
#
# Output: JSON with result, details array, and per-doc status.
# ---------------------------------------------------------------------------
cmd_validate() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  local status_json
  status_json=$(cmd_status "$docs_dir")

  local spec_exists plan_exists stasis_exists
  spec_exists=$(echo "$status_json" | jq -r '.spec.exists')
  plan_exists=$(echo "$status_json" | jq -r '.plan.exists')
  stasis_exists=$(echo "$status_json" | jq -r '.stasis.exists')

  local details="[]"
  local result="aligned"

  # Extract feature_ids
  local spec_fid plan_fid stasis_fid
  spec_fid=$(echo "$status_json" | jq -r '.spec.feature_id // empty')
  plan_fid=$(echo "$status_json" | jq -r '.plan.feature_id // empty')
  stasis_fid=$(echo "$status_json" | jq -r '.stasis.feature_id // empty')

  # Collect present feature_ids for mismatch check
  local fids=()
  [[ -n "$spec_fid" ]] && fids+=("$spec_fid")
  [[ -n "$plan_fid" ]] && fids+=("$plan_fid")
  [[ -n "$stasis_fid" ]] && fids+=("$stasis_fid")

  # Multi-spec: if no spec.md exists, check if specs/ has any specs
  # If so, this is "no-active-spec" (not an error — just no feature activated)
  if [[ "$spec_exists" != "true" && "$plan_exists" != "true" && "$stasis_exists" != "true" ]]; then
    local specs_dir="$docs_dir/specs"
    if [[ -d "$specs_dir" ]] && ls "$specs_dir"/*.md >/dev/null 2>&1; then
      jq -n \
        --arg result "no-active-spec" \
        --argjson details '["no docs/spec.md — activate a spec from docs/specs/"]' \
        --argjson status "$status_json" \
        '{result: $result, details: $details, status: $status}'
      return 0
    fi
  fi

  # Check for missing docs
  if [[ "$spec_exists" != "true" ]]; then
    details=$(echo "$details" | jq '. + ["spec.md missing"]')
  fi
  if [[ "$plan_exists" != "true" ]]; then
    details=$(echo "$details" | jq '. + ["plan.md missing"]')
  fi
  if [[ "$stasis_exists" != "true" ]]; then
    details=$(echo "$details" | jq '. + ["stasis.md missing"]')
  fi

  # Check for unlinked docs (exist but have no feature_id metadata)
  local has_unlinked=false
  if [[ "$spec_exists" == "true" && -z "$spec_fid" ]]; then
    details=$(echo "$details" | jq '. + ["spec.md unlinked (no metadata)"]')
    has_unlinked=true
  fi
  if [[ "$plan_exists" == "true" && -z "$plan_fid" ]]; then
    details=$(echo "$details" | jq '. + ["plan.md unlinked (no metadata)"]')
    has_unlinked=true
  fi
  if [[ "$stasis_exists" == "true" && -z "$stasis_fid" ]]; then
    details=$(echo "$details" | jq '. + ["stasis.md unlinked (no metadata)"]')
    has_unlinked=true
  fi

  # If any present docs are unlinked and no other result takes priority, report it
  if $has_unlinked && [[ ${#fids[@]} -eq 0 ]]; then
    result="unlinked"
  fi

  # Check feature_id mismatch (only among docs that have feature_ids)
  if [[ ${#fids[@]} -ge 2 ]]; then
    local first="${fids[0]}"
    local mismatch=false
    for fid in "${fids[@]}"; do
      if [[ "$fid" != "$first" ]]; then
        mismatch=true
        break
      fi
    done
    if $mismatch; then
      result="mismatched"
      details=$(echo "$details" | jq '. + ["feature_ids do not match across documents"]')
    fi
  fi

  # Check stale-plan: spec's current hash vs plan's stored spec_hash
  if [[ "$result" != "mismatched" && "$spec_exists" == "true" && "$plan_exists" == "true" ]]; then
    local spec_current_hash plan_stored_spec_hash
    spec_current_hash=$(echo "$status_json" | jq -r '.spec.content_hash // empty')
    plan_stored_spec_hash=$(echo "$status_json" | jq -r '.plan.spec_hash // empty')

    if [[ -n "$plan_stored_spec_hash" && -n "$spec_current_hash" && "$spec_current_hash" != "$plan_stored_spec_hash" ]]; then
      result="stale-plan"
      details=$(echo "$details" | jq '. + ["spec content changed since plan was written"]')
    fi
  fi

  # Check stale-stasis: plan's current hash vs stasis's stored plan_hash
  if [[ "$result" != "mismatched" && "$result" != "stale-plan" && "$plan_exists" == "true" && "$stasis_exists" == "true" ]]; then
    local plan_current_hash stasis_stored_plan_hash
    plan_current_hash=$(echo "$status_json" | jq -r '.plan.content_hash // empty')
    stasis_stored_plan_hash=$(echo "$status_json" | jq -r '.stasis.plan_hash // empty')

    if [[ -n "$stasis_stored_plan_hash" && -n "$plan_current_hash" && "$plan_current_hash" != "$stasis_stored_plan_hash" ]]; then
      result="stale-stasis"
      details=$(echo "$details" | jq '. + ["plan content changed since stasis was written"]')
    fi
  fi

  # Check missing-determinism-review: stasis exists but lacks the required section
  if [[ "$result" == "aligned" && "$stasis_exists" == "true" ]]; then
    local has_review=false
    local review_has_content=false
    local in_review=false

    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^##[[:space:]]+Determinism[[:space:]]+Review ]]; then
        has_review=true
        in_review=true
        continue
      fi
      # Next heading ends the review section
      if $in_review && [[ "$line" =~ ^## ]]; then
        break
      fi
      # Any non-blank line in the review section counts as content
      if $in_review && [[ -n "$line" && ! "$line" =~ ^[[:space:]]*$ ]]; then
        review_has_content=true
      fi
    done < "$docs_dir/stasis.md"

    if ! $has_review || ! $review_has_content; then
      result="missing-determinism-review"
      details=$(echo "$details" | jq '. + ["stasis.md missing Determinism Review section or section is empty"]')
    fi
  fi

  jq -n \
    --arg result "$result" \
    --argjson details "$details" \
    --argjson status "$status_json" \
    '{result: $result, details: $details, status: $status}'
}

# ---------------------------------------------------------------------------
# cmd_recommend — Suggest next action based on document state machine.
#
# State machine:
#   no docs           → "Describe a feature"
#   unlinked          → "Add lifecycle metadata"
#   spec only         → "Run /plan"
#   mismatched        → "Reconcile feature IDs"
#   stale-plan        → "Re-run /plan"
#   stale-stasis      → "Update stasis"
#   aligned (no stasis)   → "Ready to build"
#   aligned (with stasis) → "/compact to wrap session"
#
# Output: JSON with next_action and reason.
# ---------------------------------------------------------------------------
cmd_recommend() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  local validate_json
  validate_json=$(cmd_validate "$docs_dir")

  local result
  result=$(echo "$validate_json" | jq -r '.result')

  local spec_exists plan_exists stasis_exists
  spec_exists=$(echo "$validate_json" | jq -r '.status.spec.exists')
  plan_exists=$(echo "$validate_json" | jq -r '.status.plan.exists')
  stasis_exists=$(echo "$validate_json" | jq -r '.status.stasis.exists')

  local next_action reason

  # No active spec — specs exist in backlog but none activated
  if [[ "$result" == "no-active-spec" ]]; then
    # Find a Ready spec to suggest
    local ready_spec
    ready_spec=$(cmd_list_specs "$docs_dir" | jq -r '[.[] | select(.status == "Ready")] | first | .feature_id // empty')
    if [[ -n "$ready_spec" ]]; then
      next_action="Activate a spec: docs-check.sh activate $ready_spec"
      reason="No active spec. Ready specs available in docs/specs/."
    else
      next_action="Activate a spec: docs-check.sh activate <id>"
      reason="Specs exist in docs/specs/ but none are activated."
    fi

  # No docs at all
  elif [[ "$spec_exists" != "true" && "$plan_exists" != "true" && "$stasis_exists" != "true" ]]; then
    next_action="Describe a feature"
    reason="No spec, plan, or stasis found. Start by describing what you want to build."

  elif [[ "$result" == "unlinked" ]]; then
    next_action="Add lifecycle metadata to docs"
    reason="Documents exist but lack lifecycle metadata (Feature ID). Add metadata to enable validation."

  elif [[ "$result" == "mismatched" ]]; then
    next_action="Reconcile feature IDs"
    reason="Documents reference different features. Ensure all docs share the same feature_id."

  elif [[ "$result" == "stale-plan" ]]; then
    next_action="Re-run /plan"
    reason="Spec has changed since the plan was written. The plan is out of date."

  elif [[ "$result" == "stale-stasis" ]]; then
    next_action="Update stasis"
    reason="Plan has changed since the stasis was written. The stasis is out of date."

  elif [[ "$result" == "missing-determinism-review" ]]; then
    next_action="Add Determinism Review to stasis"
    reason="Stasis exists but is missing the required Determinism Review section. Add the section before clearing context."

  elif [[ "$spec_exists" == "true" && "$plan_exists" != "true" ]]; then
    next_action="Run /plan"
    reason="Spec exists but no plan. Create an implementation plan from the spec."

  elif [[ "$result" == "aligned" && "$stasis_exists" == "true" ]]; then
    next_action="/compact to wrap session"
    reason="All docs aligned with stasis. Run /compact to preserve context, then start the next feature."

  elif [[ "$result" == "aligned" && "$stasis_exists" != "true" ]]; then
    next_action="Ready to build"
    reason="Spec and plan are aligned. Start implementing via TDD."

  else
    next_action="Review docs state"
    reason="Unexpected state. Run docs-check.sh validate for details."
  fi

  jq -n \
    --arg next_action "$next_action" \
    --arg reason "$reason" \
    '{next_action: $next_action, reason: $reason}'
}

# ---------------------------------------------------------------------------
# cmd_audit_session — Scan git diffs for stochastic operation patterns.
#
# Usage:
#   docs-check.sh audit-session [--since <commit>] [repo-dir]
#
# Scans git diff for patterns indicating stochastic operations:
#   cp, jq, shasum/sha256sum, git -C, curl, wget
#
# Output: JSON with patterns_found array and summary object.
# ---------------------------------------------------------------------------

# Stochastic pattern definitions: name|regex
AUDIT_PATTERNS=(
  "cp|^\\+([[:space:]]*)cp[[:space:]]"
  "jq|^\\+([[:space:]]*)jq[[:space:]]"
  "shasum|^\\+.*(shasum|sha256sum)"
  "git-C|^\\+.*git[[:space:]]+-C[[:space:]]"
  "curl|^\\+([[:space:]]*)curl[[:space:]]"
  "wget|^\\+([[:space:]]*)wget[[:space:]]"
)

cmd_audit_session() {
  local since_commit=""
  local repo_dir="."

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)
        since_commit="$2"
        shift 2
        ;;
      *)
        repo_dir="$1"
        shift
        ;;
    esac
  done

  # Default: last 10 commits
  if [[ -z "$since_commit" ]]; then
    since_commit=$(git -C "$repo_dir" log --format=%H -10 | tail -1 2>/dev/null || echo "HEAD~10")
  fi

  # Get diff (unified=0 for changed lines only)
  local diff_output
  diff_output=$(git -C "$repo_dir" diff --unified=0 "${since_commit}..HEAD" 2>/dev/null || echo "")

  local patterns_json="[]"
  local categories="{}"
  local current_file=""

  # Process diff line by line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Track current file from diff headers
    if [[ "$line" =~ ^diff\ --git\ a/(.+)\ b/ ]]; then
      current_file="${BASH_REMATCH[1]}"
      continue
    fi
    # Also capture from +++ header
    if [[ "$line" =~ ^\+\+\+\ b/(.+) ]]; then
      current_file="${BASH_REMATCH[1]}"
      continue
    fi

    # Get line number from @@ hunk header
    local line_num=""
    if [[ "$line" =~ ^@@.*\+([0-9]+) ]]; then
      line_num="${BASH_REMATCH[1]}"
      continue
    fi

    # Check each pattern against added lines (skip allowlisted files)
    if [[ "$line" =~ ^\+ && ! "$current_file" =~ ^\.ccanvil/scripts/.*\.sh$ ]]; then
      for pattern_def in "${AUDIT_PATTERNS[@]}"; do
        local pname="${pattern_def%%|*}"
        local pregex="${pattern_def#*|}"

        if echo "$line" | grep -qE "$pregex"; then
          local context="${line#+}"
          # Escape for JSON
          context=$(echo "$context" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')

          patterns_json=$(echo "$patterns_json" | jq \
            --arg pattern "$pname" \
            --arg file "$current_file" \
            --arg line_num "${line_num:-0}" \
            --arg context "$context" \
            '. + [{pattern: $pattern, file: $file, line: ($line_num | tonumber), context: $context}]')

          # Update category count
          categories=$(echo "$categories" | jq \
            --arg cat "$pname" \
            '.[$cat] = ((.[$cat] // 0) + 1)')
        fi
      done
    fi
  done <<< "$diff_output"

  # Scan commit messages for indicator phrases
  local commit_phrases=("manually ran" "had to" "workaround")
  local commit_messages
  commit_messages=$(git -C "$repo_dir" log --format="%H %s" "${since_commit}..HEAD" 2>/dev/null || echo "")

  while IFS= read -r msg_line || [[ -n "$msg_line" ]]; do
    [[ -z "$msg_line" ]] && continue
    local commit_hash="${msg_line%% *}"
    local commit_msg="${msg_line#* }"

    for phrase in "${commit_phrases[@]}"; do
      if echo "$commit_msg" | grep -qi "$phrase"; then
        local escaped_msg
        escaped_msg=$(echo "$commit_msg" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')

        patterns_json=$(echo "$patterns_json" | jq \
          --arg pattern "commit-message" \
          --arg file "$commit_hash" \
          --arg context "$escaped_msg" \
          '. + [{pattern: $pattern, file: $file, line: 0, context: $context}]')

        categories=$(echo "$categories" | jq \
          --arg cat "commit-message" \
          '.[$cat] = ((.[$cat] // 0) + 1)')
        break  # One finding per commit, even if multiple phrases match
      fi
    done
  done <<< "$commit_messages"

  local total
  total=$(echo "$patterns_json" | jq 'length')

  jq -n \
    --argjson patterns_found "$patterns_json" \
    --argjson total "$total" \
    --argjson by_category "$categories" \
    '{patterns_found: $patterns_found, summary: {total: $total, by_category: $by_category}}'
}

# ---------------------------------------------------------------------------
# cmd_list_specs — List all specs in docs/specs/ with metadata.
#
# Usage:
#   docs-check.sh list-specs [docs-dir]
#
# Output: JSON array of {feature_id, status, created} for each spec file.
# Returns [] if docs/specs/ is empty or doesn't exist.
# ---------------------------------------------------------------------------
cmd_list_specs() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  local specs_dir="$docs_dir/specs"

  if [[ ! -d "$specs_dir" ]]; then
    echo "[]"
    return 0
  fi

  local result="[]"
  local found=false

  for spec_file in "$specs_dir"/*.md; do
    # Handle glob returning literal *.md when no files exist
    [[ -f "$spec_file" ]] || continue
    found=true

    local meta
    meta=$(parse_metadata "$spec_file")

    local feature_id status created
    feature_id=$(echo "$meta" | jq -r '.feature_id // empty')
    status=$(echo "$meta" | jq -r '.status // empty')
    created=$(echo "$meta" | jq -r '.created // empty')

    result=$(echo "$result" | jq \
      --arg fid "$feature_id" \
      --arg status "$status" \
      --arg created "$created" \
      '. + [{feature_id: $fid, status: $status, created: $created}]')
  done

  echo "$result"
}

# ---------------------------------------------------------------------------
# cmd_activate — Activate a spec from the backlog.
#
# Usage:
#   docs-check.sh activate <feature-id> [docs-dir]
#
# Creates branch claude/<type>/<feature-id>, copies spec to docs/spec.md,
# updates spec status to "In Progress".
# Fails if: feature-id not found, another spec is In Progress, worktree dirty.
# ---------------------------------------------------------------------------
cmd_activate() {
  # Parse args: <feature-id> [--force-local-ahead] [docs-dir]
  # Flag can appear in any position among the positionals.
  local feature_id=""
  local docs_dir=""
  local force_local_ahead=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force-local-ahead) force_local_ahead=true; shift ;;
      *)
        if [[ -z "$feature_id" ]]; then feature_id="$1"
        elif [[ -z "$docs_dir" ]]; then docs_dir="$1"
        fi
        shift
        ;;
    esac
  done
  [[ -n "$feature_id" ]] || { echo "Usage: activate <feature-id> [--force-local-ahead] [docs-dir]" >&2; exit 1; }
  [[ -n "$docs_dir" ]] || docs_dir="$DEFAULT_DOCS_DIR"
  local specs_dir="$docs_dir/specs"
  local repo_root
  repo_root=$(cd "$docs_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || {
    repo_root=$(cd "$docs_dir/.." 2>/dev/null && pwd)
  }

  # Pre-activate push-guard (AC-17/18/19): halt if local main is ahead of
  # origin/main. Unpushed commits on main become part of the feature branch's
  # history on push and cause divergence at squash-merge time. If origin/main
  # doesn't exist (no remote, or unpushed remote), this check is a no-op.
  if ! $force_local_ahead; then
    if git -C "$repo_root" rev-parse --verify origin/main >/dev/null 2>&1; then
      local ahead_hashes
      ahead_hashes=$(git -C "$repo_root" rev-list --reverse --format="%h %s" --no-commit-header origin/main..main 2>/dev/null || true)
      if [[ -n "$ahead_hashes" ]]; then
        echo "ERROR: local main is ahead of origin/main — unpushed commits would leak into the feature branch." >&2
        echo "" >&2
        echo "Unpushed commits:" >&2
        echo "$ahead_hashes" | sed 's/^/  /' >&2
        echo "" >&2
        echo "Resolve by pushing main first:" >&2
        echo "  git push origin main" >&2
        echo "" >&2
        echo "Or, if these commits are session-boundary artifacts that you know you want on the branch:" >&2
        echo "  bash .ccanvil/scripts/docs-check.sh activate $feature_id --force-local-ahead" >&2
        exit 1
      fi
    fi
  fi

  # Find the spec file
  local spec_file=""
  for f in "$specs_dir"/*.md; do
    [[ -f "$f" ]] || continue
    local fid
    fid=$(parse_metadata "$f" | jq -r '.feature_id // empty')
    if [[ "$fid" == "$feature_id" ]]; then
      spec_file="$f"
      break
    fi
  done

  if [[ -z "$spec_file" ]]; then
    echo "ERROR: spec with feature_id '$feature_id' not found in $specs_dir" >&2
    exit 1
  fi

  # Check no other spec is In Progress
  for f in "$specs_dir"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$f" == "$spec_file" ]] && continue
    local st
    st=$(parse_metadata "$f" | jq -r '.status // empty')
    if [[ "$st" == "In Progress" ]]; then
      local blocking_fid
      blocking_fid=$(parse_metadata "$f" | jq -r '.feature_id // empty')
      echo "ERROR: spec '$blocking_fid' is already In Progress. Complete it first." >&2
      exit 1
    fi
  done

  # Check worktree is clean (allow uncommitted spec-related files)
  local dirty_non_spec=""
  local docs_rel
  docs_rel=$(cd "$docs_dir" 2>/dev/null && git rev-parse --show-prefix 2>/dev/null)
  docs_rel="${docs_rel%/}"  # strip trailing slash → e.g. "docs"
  # Build prefix: "docs/" when docs_dir is a subdirectory, "" when it's repo root
  local docs_prefix="${docs_rel:+${docs_rel}/}"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # porcelain format: XY <path> or XY <path> -> <path>
    # Note: only the source path is checked; rename destinations are not evaluated
    local fpath="${line:3}"
    fpath="${fpath%% -> *}"  # strip rename target
    case "$fpath" in
      "${docs_prefix}specs/"*|"${docs_prefix}spec.md") ;;                       # allowed: spec files
      "${docs_prefix}roadmap.md") ;;                                            # allowed: triage artifact
      *) dirty_non_spec="$fpath"; break ;;
    esac
  done < <(git -C "$repo_root" status --porcelain --untracked-files=all 2>/dev/null)
  if [[ -n "$dirty_non_spec" ]]; then
    echo "ERROR: worktree has uncommitted changes. Commit or stash before activating." >&2
    exit 1
  fi

  # Extract type from spec (default to feat)
  local spec_type="feat"
  # Look for a Type: field in metadata, or default
  local type_field
  type_field=$(grep -m1 '^> Type:' "$spec_file" 2>/dev/null | sed 's/^> Type: *//' || true)
  if [[ -n "$type_field" ]]; then
    spec_type="$type_field"
  fi

  local branch_name="claude/${spec_type}/${feature_id}"

  # Create branch
  git -C "$repo_root" checkout -b "$branch_name" 2>/dev/null || {
    echo "ERROR: failed to create branch '$branch_name'" >&2
    exit 1
  }

  # Update status in specs/ to "In Progress"
  update_metadata_status "$spec_file" "In Progress"

  # Copy spec to docs/spec.md (after status update so it gets the new status)
  cp "$spec_file" "$docs_dir/spec.md"

  # Auto-commit spec changes on the branch
  git -C "$repo_root" add "$spec_file" "$docs_dir/spec.md"
  git -C "$repo_root" commit -q -m "docs(lifecycle): activate $feature_id" || {
    echo "ERROR: failed to commit spec changes on branch '$branch_name'" >&2
    exit 1
  }

  echo "Activated spec '$feature_id' on branch '$branch_name'"

  # Push branch and create draft PR (if remote exists and gh available)
  if git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo_root" push -u origin "$branch_name" 2>/dev/null || true
    if command -v gh >/dev/null 2>&1; then
      local first_line
      first_line=$(sed -n '/^## Summary$/,/^## /{ /^## /d; /^$/d; p; }' "$spec_file" | head -1 | sed 's/^[[:space:]]*//')
      local pr_title="${spec_type}(${feature_id}): ${first_line:-activate feature}"
      local spec_body
      spec_body=$(cat "$spec_file")
      gh pr create --draft \
        --title "$pr_title" \
        --body "$(printf '## Spec\n\n%s\n\n---\n🤖 Generated with [Claude Code](https://claude.com/claude-code)' "$spec_body")" \
        2>/dev/null && echo "Draft PR created." || echo "NOTE: Draft PR not created — gh pr create failed." >&2
    else
      echo "NOTE: Draft PR not created — gh CLI not available. Run /pr to create manually."
    fi
  fi
}

# ---------------------------------------------------------------------------
# cmd_complete — Mark a spec as Complete.
#
# Usage:
#   docs-check.sh complete <feature-id> [docs-dir]
#
# Updates spec status to "Complete". Clears docs/assumptions.md if it exists.
# Fails if spec is not In Progress or feature-id not found.
# ---------------------------------------------------------------------------
cmd_complete() {
  local feature_id="${1:?Usage: complete <feature-id> [docs-dir]}"
  local docs_dir="${2:-$DEFAULT_DOCS_DIR}"
  local specs_dir="$docs_dir/specs"

  # Find the spec file
  local spec_file=""
  for f in "$specs_dir"/*.md; do
    [[ -f "$f" ]] || continue
    local fid
    fid=$(parse_metadata "$f" | jq -r '.feature_id // empty')
    if [[ "$fid" == "$feature_id" ]]; then
      spec_file="$f"
      break
    fi
  done

  if [[ -z "$spec_file" ]]; then
    echo "ERROR: spec with feature_id '$feature_id' not found in $specs_dir" >&2
    exit 1
  fi

  # Verify spec is In Progress
  local current_status
  current_status=$(parse_metadata "$spec_file" | jq -r '.status // empty')
  if [[ "$current_status" != "In Progress" ]]; then
    echo "ERROR: spec '$feature_id' is '$current_status', not 'In Progress'" >&2
    exit 1
  fi

  # Update status to Complete
  update_metadata_status "$spec_file" "Complete"

  # Clear assumptions.md if it exists
  local assumptions_file="$docs_dir/assumptions.md"
  if [[ -f "$assumptions_file" ]]; then
    : > "$assumptions_file"
  fi

  # Remove lifecycle docs (they're preserved in git history on the branch)
  rm -f "$docs_dir/spec.md" "$docs_dir/plan.md" "$docs_dir/stasis.md"

  # Commit completion + cleanup
  local repo_root
  repo_root=$(cd "$docs_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || repo_root="."
  # Use -- to separate paths; paths must be relative to repo root or absolute
  (cd "$repo_root" && git add -A "$docs_dir/" "$spec_file" 2>/dev/null || true)
  git -C "$repo_root" commit -q -m "docs(lifecycle): complete $feature_id — clean up lifecycle docs" 2>/dev/null || true

  # Mark PR as ready (if gh available and PR exists)
  if command -v gh >/dev/null 2>&1; then
    gh pr ready 2>/dev/null || true
  fi

  echo "Completed spec '$feature_id'"
}

# ---------------------------------------------------------------------------
# cmd_land — Switch to main, sync with remote, delete feature branch.
#
# Usage:
#   docs-check.sh land [--force]
#
# Requires: the current branch is NOT main/master.
# --force skips the merged-PR check (for local merges or when gh is unavailable).
# ---------------------------------------------------------------------------

cmd_land() {
  local force=false
  [[ "${1:-}" == "--force" ]] && force=true

  local branch
  branch=$(git branch --show-current 2>/dev/null)

  # Already on main: gh pr merge --delete-branch switches to main and deletes
  # the local branch itself. In that case, just fast-forward local main to
  # origin so subsequent work starts from a clean, in-sync state.
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    if git remote get-url origin >/dev/null 2>&1; then
      git fetch origin 2>/dev/null
      local main_ref="origin/$branch"
      if git rev-parse --verify "$main_ref" >/dev/null 2>&1; then
        git merge --ff-only "$main_ref" 2>/dev/null && \
          echo "Already on $branch. Fast-forwarded to $main_ref." || \
          echo "Already on $branch. Local has diverged from $main_ref — resolve manually."
      else
        echo "Already on $branch. No remote tracking ref."
      fi
    else
      echo "Already on $branch. No remote configured."
    fi
    return 0
  fi

  # Check if PR is merged (unless --force)
  if ! $force && command -v gh >/dev/null 2>&1; then
    local pr_state
    pr_state=$(gh pr view --json state -q '.state' 2>/dev/null || echo "NONE")
    if [[ "$pr_state" != "MERGED" ]]; then
      echo "ERROR: No merged PR found for branch '$branch'. Merge the PR first, or use --force." >&2
      exit 1
    fi
  fi

  # Switch to main
  git checkout main 2>/dev/null || git checkout master 2>/dev/null || {
    echo "ERROR: Could not switch to main/master." >&2
    exit 1
  }
  echo "Switched to main."

  # Fetch and reset (if remote exists)
  if git remote get-url origin >/dev/null 2>&1; then
    git fetch origin 2>/dev/null
    echo "Fetched origin."
    local sha
    sha=$(git rev-parse --short origin/main 2>/dev/null || git rev-parse --short origin/master 2>/dev/null || echo "unknown")
    git reset --hard "origin/main" 2>/dev/null || git reset --hard "origin/master" 2>/dev/null || true
    echo "Main updated to $sha."
  fi

  # Delete local branch
  git branch -d "$branch" 2>/dev/null || git branch -D "$branch" 2>/dev/null || true
  echo "Deleted local branch '$branch'."

  # Delete remote branch (if remote exists)
  if git remote get-url origin >/dev/null 2>&1; then
    git push origin --delete "$branch" 2>/dev/null && \
      echo "Deleted remote branch '$branch'." || \
      echo "Remote branch '$branch' already deleted."
  fi

  echo "Land complete."
}

# ---------------------------------------------------------------------------
# merge_config — Merge ccanvil.json (hub) with ccanvil.local.json (node).
# Duplicated from operations.sh (both scripts need it; keeping small and tested).
merge_config() {
  local dir="$1"
  local hub_file="$dir/.claude/ccanvil.json"
  local local_file="$dir/.claude/ccanvil.local.json"

  if [[ ! -f "$hub_file" && ! -f "$local_file" ]]; then
    echo '{}'
    return 0
  fi

  if [[ -f "$hub_file" ]] && ! jq empty "$hub_file" 2>/dev/null; then
    echo "ERROR: .claude/ccanvil.json is not valid JSON" >&2
    return 1
  fi

  if [[ -f "$local_file" ]] && ! jq empty "$local_file" 2>/dev/null; then
    echo "ERROR: .claude/ccanvil.local.json is not valid JSON" >&2
    return 1
  fi

  if [[ -f "$hub_file" && ! -f "$local_file" ]]; then
    jq '.' "$hub_file"
  elif [[ ! -f "$hub_file" && -f "$local_file" ]]; then
    jq '.' "$local_file"
  else
    jq -s '.[0] * .[1]' "$hub_file" "$local_file"
  fi
}

# cmd_config_get — Read a feature toggle from merged ccanvil config.
#
# Usage:
#   docs-check.sh config-get <key> [project-dir]
#
# Returns the value of features.<key> from the merged effective config
# (ccanvil.json + ccanvil.local.json). Returns "false" if files are
# missing, key is missing, or features object doesn't exist.
# ---------------------------------------------------------------------------
cmd_config_get() {
  local key="${1:?Usage: config-get <key> [project-dir]}"
  local project_dir="${2:-.}"

  local merged
  merged=$(merge_config "$project_dir") || return 1

  local value
  value=$(echo "$merged" | jq -r --arg k "$key" '.features[$k] // "false"' 2>/dev/null)

  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "false"
  else
    echo "$value"
  fi
}

# ---------------------------------------------------------------------------
# Radar — deterministic data gathering for /radar skill
# ---------------------------------------------------------------------------

cmd_radar_gather() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  local result="{}"

  # Active spec
  if [[ -f "$docs_dir/spec.md" ]]; then
    local spec_meta
    spec_meta=$(parse_metadata "$docs_dir/spec.md")
    result=$(echo "$result" | jq --argjson m "$spec_meta" '. + {"active_spec": $m}')
  else
    result=$(echo "$result" | jq '. + {"active_spec": null}')
  fi

  # Recently completed specs (last 5)
  local completed="[]"
  local specs_dir="$docs_dir/specs"
  if [[ -d "$specs_dir" ]]; then
    for f in "$specs_dir"/*.md; do
      [[ -f "$f" ]] || continue
      local meta
      meta=$(parse_metadata "$f")
      local st
      st=$(echo "$meta" | jq -r '.status // empty')
      if [[ "$st" == "Complete" ]]; then
        completed=$(echo "$completed" | jq --argjson m "$meta" '. + [$m]')
      fi
    done
    # Keep last 5 by created date (descending)
    completed=$(echo "$completed" | jq 'sort_by(.created) | reverse | .[0:5]')
  fi
  result=$(echo "$result" | jq --argjson c "$completed" '. + {"completed_recent": $c}')

  # Idea count — ideas.log lives at <project>/.ccanvil/ideas.log (one level above docs_dir).
  local idea_counts='{"total":0,"new":0}'
  local project_dir
  project_dir=$(dirname "$docs_dir")
  if [[ -f "$project_dir/.ccanvil/ideas.log" ]]; then
    idea_counts=$(cmd_idea_count "$project_dir")
  fi
  result=$(echo "$result" | jq --argjson i "$idea_counts" '. + {"ideas": $i}')

  # Roadmap summary (active theme + up next)
  if [[ -f "$docs_dir/roadmap.md" ]]; then
    local active_theme=""
    local in_theme=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^##\ Active\ Theme ]]; then
        in_theme=true; continue
      fi
      if $in_theme; then
        if [[ "$line" =~ ^## ]]; then break; fi
        if [[ -n "$line" && ! "$line" =~ ^\<!-- ]]; then
          active_theme="$line"
          break
        fi
      fi
    done < "$docs_dir/roadmap.md"
    result=$(echo "$result" | jq --arg t "${active_theme:-not set}" '. + {"roadmap": {"active_theme": $t, "exists": true}}')
  else
    result=$(echo "$result" | jq '. + {"roadmap": {"active_theme": "no roadmap", "exists": false}}')
  fi

  # Git activity (last 7 days)
  local git_summary=""
  if git rev-parse HEAD >/dev/null 2>&1; then
    local commit_count
    commit_count=$(git log --oneline --since="7 days ago" 2>/dev/null | wc -l | tr -d ' ')
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    result=$(echo "$result" | jq --arg cc "$commit_count" --arg b "$branch" \
      '. + {"git": {"commits_7d": ($cc | tonumber), "branch": $b}}')
  else
    result=$(echo "$result" | jq '. + {"git": {"commits_7d": 0, "branch": "none"}}')
  fi

  # Spec backlog summary
  local backlog_counts
  backlog_counts=$(cmd_list_specs "$docs_dir" 2>/dev/null | jq '{
    total: length,
    ready: [.[] | select(.status == "Ready")] | length,
    in_progress: [.[] | select(.status == "In Progress")] | length,
    complete: [.[] | select(.status == "Complete")] | length
  }' 2>/dev/null || echo '{"total":0,"ready":0,"in_progress":0,"complete":0}')
  result=$(echo "$result" | jq --argjson b "$backlog_counts" '. + {"backlog": $b}')

  echo "$result" | jq '.'
}

# ---------------------------------------------------------------------------
# Idea management
# ---------------------------------------------------------------------------

cmd_idea_add() {
  local body=""
  local title=""
  local project_dir="."

  # Parse args: first positional is body, then optional --title flag,
  # final positional (if any) is the project dir (defaults to cwd).
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)
        title="$2"; shift 2 ;;
      *)
        if [[ -z "$body" ]]; then
          body="$1"
        else
          project_dir="$1"
        fi
        shift
        ;;
    esac
  done

  [[ -n "$body" ]] || { echo "Usage: idea-add <body> [--title TITLE] [project-dir]" >&2; exit 1; }

  # Defense-in-depth: on Linear-configured nodes, captures must route
  # through the /idea skill (operations.sh -> MCP). Refuse direct script
  # writes so legacy scripts or accidental invocations don't pollute the
  # archive-only .ccanvil/ideas.log.
  local local_cfg="$project_dir/.claude/ccanvil.local.json"
  if [[ -f "$local_cfg" ]]; then
    local routing
    routing=$(jq -r '.integrations.routing.idea // ""' "$local_cfg" 2>/dev/null || echo '')
    if [[ "$routing" == "linear" ]]; then
      echo "ERROR: node is Linear-configured — captures must route via /idea skill" >&2
      return 1
    fi
  fi

  # Default: title = body (short-text fast path; AC-22)
  [[ -z "$title" ]] && title="$body"

  local ideas_log="$project_dir/.ccanvil/ideas.log"
  mkdir -p "$(dirname "$ideas_log")"

  local uid epoch
  uid=$(head -c 2 /dev/urandom | xxd -p)
  epoch=$(date +%s)

  jq -cn --arg uid "$uid" --argjson created "$epoch" \
         --arg title "$title" --arg body "$body" \
    '{uid:$uid, created:$created, status:"new", title:$title, body:$body}' \
    >> "$ideas_log"

  echo "Captured: $title"
}

cmd_idea_list() {
  local filter_status=""
  local project_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) filter_status="$2"; shift 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local ideas_log="$project_dir/.ccanvil/ideas.log"
  if [[ ! -f "$ideas_log" ]]; then
    echo "[]"
    return 0
  fi

  local jq_shape='{id: .uid, created: .created, title: .title, body: .body, status: .status}'
  if [[ -n "$filter_status" ]]; then
    jq -s --arg s "$filter_status" \
      "[.[] | select(.status == \$s) | $jq_shape]" "$ideas_log"
  else
    jq -s "[.[] | $jq_shape]" "$ideas_log"
  fi
}

cmd_idea_count() {
  local project_dir="${1:-.}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"

  if [[ ! -f "$ideas_log" ]]; then
    jq -n '{total:0, new:0, promoted:0, parked:0, dismissed:0, merged:0}'
    return 0
  fi

  jq -s '{
    total:     length,
    new:       [.[] | select(.status == "new")]       | length,
    promoted:  [.[] | select(.status == "promoted")]  | length,
    parked:    [.[] | select(.status == "parked")]    | length,
    dismissed: [.[] | select(.status == "dismissed")] | length,
    merged:    [.[] | select(.status == "merged")]    | length
  }' "$ideas_log"
}

cmd_idea_update() {
  local uid="${1:?Usage: idea-update <uid> <status> [project-dir]}"
  local new_status="${2:?Usage: idea-update <uid> <status> [project-dir]}"
  local project_dir="${3:-.}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"

  [[ -f "$ideas_log" ]] || { echo "ERROR: $ideas_log not found" >&2; exit 1; }

  # Confirm the uid exists before rewriting.
  if ! grep -q "\"uid\":\"$uid\"" "$ideas_log"; then
    echo "ERROR: idea with uid '$uid' not found" >&2
    exit 1
  fi

  local tmp
  tmp=$(mktemp)
  jq -c --arg uid "$uid" --arg s "$new_status" \
    'if .uid == $uid then .status = $s else . end' \
    "$ideas_log" > "$tmp"
  mv "$tmp" "$ideas_log"

  echo "Updated idea $uid to $new_status"
}

# ---------------------------------------------------------------------------
# cmd_idea_sync — Read/ack primitives for .ccanvil/ideas-pending.log.
#
# The pending log holds intents for Linear captures that failed (network,
# auth, etc.). Replay is orchestrated by the /idea skill — this script
# exposes the deterministic read + remove operations.
#
# Invocations:
#   idea-sync [project-dir]             → print {pending, entries} JSON
#   idea-sync --ack <ts> [project-dir]  → remove entry matching ts
# ---------------------------------------------------------------------------
cmd_idea_sync() {
  local project_dir="."
  local ack_ts=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ack) ack_ts="$2"; shift 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local pending="$project_dir/.ccanvil/ideas-pending.log"

  if [[ -n "$ack_ts" ]]; then
    if [[ ! -f "$pending" ]]; then
      echo "ACKED: $ack_ts (pending log absent — no-op)"
      return 0
    fi
    local tmp
    tmp=$(mktemp)
    jq -c --argjson ts "$ack_ts" 'select(.ts != $ts)' "$pending" > "$tmp"
    mv "$tmp" "$pending"
    echo "ACKED: $ack_ts"
    return 0
  fi

  if [[ ! -f "$pending" || ! -s "$pending" ]]; then
    jq -n '{pending: 0, entries: []}'
    return 0
  fi

  jq -s '{pending: length, entries: .}' "$pending"
}

# ---------------------------------------------------------------------------
# cmd_idea_migrate — Move legacy docs/ideas.md entries into .ccanvil/ideas.log
# and/or emit intents for skill-level Linear dispatch.
#
# Invocations:
#   idea-migrate [project-dir]
#     Local end-to-end: parse docs/ideas.md → append to .ccanvil/ideas.log,
#     git rm docs/ideas.md, update .gitignore. Idempotent when file absent.
#
#   idea-migrate --extract [project-dir]
#     Parse docs/ideas.md → emit JSONL intents on stdout. No side effects.
#     Used by the skill when Linear is configured; skill dispatches each
#     intent via MCP, then runs --finalize.
#
#   idea-migrate --finalize [project-dir]
#     git rm docs/ideas.md + update .gitignore. No parsing.
# ---------------------------------------------------------------------------
cmd_idea_migrate() {
  local project_dir="."
  local mode="full"   # full | extract | finalize

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --extract) mode="extract"; shift ;;
      --finalize) mode="finalize"; shift ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local ideas_md="$project_dir/docs/ideas.md"
  local ideas_log="$project_dir/.ccanvil/ideas.log"
  local gitignore="$project_dir/.gitignore"

  _idea_migrate_finalize() {
    if [[ -f "$ideas_md" ]]; then
      if git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1 && \
         git -C "$project_dir" ls-files --error-unmatch docs/ideas.md >/dev/null 2>&1; then
        git -C "$project_dir" rm -q docs/ideas.md
      else
        rm -f "$ideas_md"
      fi
    fi
    touch "$gitignore"
    for entry in "docs/ideas.md" ".ccanvil/ideas-pending.log" ".ccanvil/ideas.log"; do
      if ! grep -qxF "$entry" "$gitignore" 2>/dev/null; then
        echo "$entry" >> "$gitignore"
      fi
    done
    echo "FINALIZED: docs/ideas.md removed; .gitignore updated"
  }

  _idea_migrate_extract() {
    while IFS= read -r line; do
      # New format: - [ ] <uid> <epoch>: text <!-- status:xxx -->
      if [[ "$line" =~ ^-\ \[(.)\]\ ([0-9a-f]{4})\ ([0-9]+):\ (.*)\ \<!--\ status:([a-z:A-Z0-9_-]+)\ --\> ]]; then
        local uid="${BASH_REMATCH[2]}"
        local created="${BASH_REMATCH[3]}"
        local text="${BASH_REMATCH[4]}"
        local status="${BASH_REMATCH[5]}"
        jq -cn --arg uid "$uid" --argjson created "$created" \
               --arg title "$text" --arg body "$text" --arg status "$status" \
          '{uid:$uid, created:$created, status:$status, title:$title, body:$body}'
      # Legacy format: - [ ] YYYY-MM-DD: text <!-- status:xxx -->
      elif [[ "$line" =~ ^-\ \[(.)\]\ ([0-9]{4}-[0-9]{2}-[0-9]{2}):\ (.*)\ \<!--\ status:([a-z:A-Z0-9_-]+)\ --\> ]]; then
        local created="${BASH_REMATCH[2]}"
        local text="${BASH_REMATCH[3]}"
        local status="${BASH_REMATCH[4]}"
        jq -cn --arg created "$created" \
               --arg title "$text" --arg body "$text" --arg status "$status" \
          '{created:$created, status:$status, title:$title, body:$body}'
      fi
    done < "$ideas_md"
  }

  case "$mode" in
    finalize)
      _idea_migrate_finalize
      ;;
    extract)
      [[ -f "$ideas_md" ]] || { echo "Nothing to migrate: $ideas_md not found"; return 0; }
      _idea_migrate_extract
      ;;
    full)
      if [[ ! -f "$ideas_md" ]]; then
        echo "Nothing to migrate: $ideas_md not found"
        return 0
      fi
      mkdir -p "$(dirname "$ideas_log")"
      # Write each parsed entry as a local JSONL idea (title=body, status preserved).
      _idea_migrate_extract >> "$ideas_log"
      local migrated
      migrated=$(_idea_migrate_extract | wc -l | tr -d ' ')
      _idea_migrate_finalize
      echo "MIGRATED: $migrated entries → $ideas_log"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# cmd_idea_setup — One-shot per-node setup for the /idea system.
#
# Writes (or deep-merges into) .claude/ccanvil.local.json and appends the
# three gitignore entries for the new local stores. Idempotent.
#
# Usage:
#   idea-setup --provider local                                  [project-dir]
#   idea-setup --provider linear --team TEAM --project PROJECT   [project-dir]
# ---------------------------------------------------------------------------
cmd_idea_setup() {
  local provider=""
  local team=""
  local project=""
  local project_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="$2"; shift 2 ;;
      --team)     team="$2";     shift 2 ;;
      --project)  project="$2";  shift 2 ;;
      *)          project_dir="$1"; shift ;;
    esac
  done

  case "$provider" in
    local) ;;
    linear)
      [[ -n "$team" ]]    || { echo "ERROR: --provider linear requires --team TEAM" >&2; exit 1; }
      [[ -n "$project" ]] || { echo "ERROR: --provider linear requires --project PROJECT" >&2; exit 1; }
      ;;
    "")  echo "ERROR: --provider is required (local|linear)" >&2; exit 1 ;;
    *)   echo "ERROR: unknown provider '$provider' (must be local|linear)" >&2; exit 1 ;;
  esac

  mkdir -p "$project_dir/.claude" "$project_dir/.ccanvil"

  # Compose the new integrations slice.
  local slice
  if [[ "$provider" == "linear" ]]; then
    slice=$(jq -n --arg team "$team" --arg project "$project" \
      '{integrations: {routing: {idea: "linear"}, providers: {linear: {team: $team, project: $project}}}}')
  else
    slice='{"integrations": {"routing": {"idea": "local"}}}'
  fi

  # Deep-merge into existing ccanvil.local.json (preserve node_uuid, other keys).
  local cfg="$project_dir/.claude/ccanvil.local.json"
  local existing='{}'
  [[ -f "$cfg" ]] && existing=$(cat "$cfg")

  echo "$existing" | jq --argjson slice "$slice" '. * $slice' > "$cfg.tmp"
  mv "$cfg.tmp" "$cfg"

  # .gitignore hygiene — both stores live under the repo and must never be
  # committed; the legacy docs/ideas.md path is ignored so a stale file
  # (until migrated) doesn't leak.
  local gitignore="$project_dir/.gitignore"
  touch "$gitignore"
  for entry in ".ccanvil/ideas.log" ".ccanvil/ideas-pending.log" "docs/ideas.md"; do
    if ! grep -qxF "$entry" "$gitignore" 2>/dev/null; then
      echo "$entry" >> "$gitignore"
    fi
  done

  echo "SETUP: $cfg configured with provider=$provider"
  if [[ "$provider" == "linear" ]]; then
    echo ""
    echo "Next steps:"
    echo "  1. Verify the 'Idea' and 'Icebox' custom statuses exist on team '$team'"
    echo "     in Linear (Team Settings → Issue statuses & automations). If not,"
    echo "     create them in the Backlog category. MCP can't create them for you."
    echo "  2. Run 'docs-check.sh idea-migrate' to move any legacy docs/ideas.md"
    echo "     entries into the local store. The skill's Linear sync flow will"
    echo "     promote them from there."
  else
    echo ""
    echo "Next step: run 'docs-check.sh idea-migrate' if you have a legacy"
    echo "docs/ideas.md to move into .ccanvil/ideas.log."
  fi
}

# ---------------------------------------------------------------------------
# cmd_legacy_refs_scan — Find references to legacy ccanvil verbs/artifacts.
#
# Scans a project dir for:
#   - /catchup  (slash command)
#   - /checkpoint  (slash command, pre-stasis naming)
#   - docs/checkpoint.md  (artifact path)
#   - checkpoint.read | checkpoint.write  (operations.sh op names)
#   - stale-checkpoint  (validate state name)
#
# Classifies each match by scope:
#   - "hub-owned": line appears BEFORE "<!-- NODE-SPECIFIC-START -->" in a file
#                  that contains that marker (indicating the match is in content
#                  the hub pulls and should be fixed at the hub).
#   - "node-specific": line appears AFTER the marker, OR the file has no marker
#                      (the user wrote it and must fix it manually).
#
# Output: JSON array [{file, line, match, scope}].
# Exit: 0 if empty; 1 if any matches found.
# ---------------------------------------------------------------------------
cmd_legacy_refs_scan() {
  local project_dir="${1:-.}"

  local pattern='/catchup|/checkpoint|docs/checkpoint\.md|checkpoint\.(read|write)|stale-checkpoint'

  # Collect matches via grep -rnE; skip .git, node_modules, and binary files.
  # -I: skip binary; -n: line numbers; --exclude-dir: skip common noise.
  # Tolerate empty grep output (exit 1 when no matches).
  local raw_matches
  raw_matches=$(cd "$project_dir" && grep -rnIE \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=dist \
    --exclude-dir=generated \
    "$pattern" . 2>/dev/null || true)

  if [[ -z "$raw_matches" ]]; then
    echo "[]"
    return 0
  fi

  # Per-file marker line lookup. macOS ships bash 3.2 (no associative arrays),
  # so each iteration re-greps — fine for the tiny scanner workload.
  local entries="[]"
  while IFS= read -r raw; do
    [[ -z "$raw" ]] && continue
    # grep -rn format: ./path:line:content
    local file_path="${raw%%:*}"
    local rest="${raw#*:}"
    local line_num="${rest%%:*}"
    local content="${rest#*:}"

    # Normalize leading ./
    file_path="${file_path#./}"

    # Look up the NODE-SPECIFIC marker line (0 if absent).
    local marker
    marker=$(grep -n '<!-- NODE-SPECIFIC-START -->' "$project_dir/$file_path" 2>/dev/null | head -1 | cut -d: -f1 || true)
    marker="${marker:-0}"

    local scope="node-specific"
    if [[ "$marker" != "0" && "$line_num" -lt "$marker" ]]; then
      scope="hub-owned"
    fi

    # Extract the actual matching token(s) from the content line using grep -oE
    local matched
    matched=$(echo "$content" | grep -oE "$pattern" | head -1)
    [[ -z "$matched" ]] && continue

    entries=$(echo "$entries" | jq \
      --arg file "$file_path" \
      --argjson line "$line_num" \
      --arg match "$matched" \
      --arg scope "$scope" \
      '. + [{file: $file, line: $line, match: $match, scope: $scope}]')
  done <<< "$raw_matches"

  echo "$entries"

  local count
  count=$(echo "$entries" | jq 'length')
  if [[ "$count" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# cmd_idea_upgrade — One-command downstream node adoption of the /idea system.
#
# Collapses the 4-step manual sequence (pull-apply -> idea-setup -> idea-migrate
# -> git commit) into a single invocation. Idempotent: re-running on an
# already-upgraded node is a no-op.
#
# Usage:
#   idea-upgrade --provider local                                  [project-dir]
#   idea-upgrade --provider linear --team TEAM --project PROJECT   [project-dir]
# ---------------------------------------------------------------------------
cmd_idea_upgrade() {
  local provider=""
  local team=""
  local project=""
  local project_dir="."
  local dry_run=0
  local create_project=0
  local from_legacy=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider)       provider="$2"; shift 2 ;;
      --team)           team="$2";     shift 2 ;;
      --project)        project="$2";  shift 2 ;;
      --dry-run)        dry_run=1;     shift ;;
      --create-project) create_project=1; shift ;;
      --from-legacy)    from_legacy=1; shift ;;
      *)                project_dir="$1"; shift ;;
    esac
  done

  case "$provider" in
    local) ;;
    linear)
      [[ -n "$team" && -n "$project" ]] || {
        echo "ERROR: --provider linear requires --team and --project" >&2
        return 1
      }
      ;;
    "")  echo "ERROR: --provider is required (local|linear)" >&2; return 1 ;;
    *)   echo "ERROR: unknown provider '$provider' (must be local|linear)" >&2; return 1 ;;
  esac

  if [[ $create_project -eq 1 && "$provider" != "linear" ]]; then
    echo "ERROR: --create-project requires --provider linear" >&2
    return 1
  fi

  # Emit the save_project intent before any file mutation so that a skill
  # layer dispatching this command can pick it off stdout and call MCP
  # itself. Script stays MCP-free (operations.sh-style separation).
  if [[ $create_project -eq 1 ]]; then
    jq -cn --arg team "$team" --arg name "$project" \
      '{tool: "mcp__claude_ai_Linear__save_project", params: {team: $team, name: $name}}'
  fi

  if [[ $dry_run -eq 1 ]]; then
    echo "DRY-RUN: idea-upgrade plan for $project_dir"
    echo "  provider: $provider"
    if [[ "$provider" == "linear" ]]; then
      echo "  team=$team project=$project"
    fi
    echo "  files touched:"
    echo "    .claude/ccanvil.local.json (deep-merge routing.idea + providers.linear)"
    echo "    .gitignore (append .ccanvil/ideas.log, .ccanvil/ideas-pending.log, docs/ideas.md)"
    echo "  commit message: chore(idea-upgrade): configure $provider provider"
    return 0
  fi

  # Idempotency: if the config already routes to the target provider, exit
  # cleanly instead of trying to commit an empty diff.
  local cfg="$project_dir/.claude/ccanvil.local.json"
  if [[ -f "$cfg" ]]; then
    local current_routing
    current_routing=$(jq -r '.integrations.routing.idea // ""' "$cfg" 2>/dev/null || echo '')
    if [[ "$current_routing" == "$provider" && $from_legacy -eq 0 ]]; then
      echo "Already upgraded: $project_dir is configured with provider=$provider"
      return 0
    fi
  fi

  # --from-legacy: when docs/ideas.md is tracked, migrate it inline so the
  # final commit is one-shot (config + removed source + gitignore).
  local migrated_count=0
  local legacy_present=0
  if [[ $from_legacy -eq 1 ]]; then
    if [[ -f "$project_dir/docs/ideas.md" ]]; then
      legacy_present=1
      mkdir -p "$project_dir/.ccanvil"
      local ideas_log="$project_dir/.ccanvil/ideas.log"
      while IFS= read -r line; do
        local body=''
        local uid='' created='' status=''
        if [[ "$line" =~ ^-\ \[(.)\]\ ([0-9a-f]{4})\ ([0-9]+):\ (.*)\ \<!--\ status:([a-z:A-Z0-9_-]+)\ --\> ]]; then
          uid="${BASH_REMATCH[2]}"
          created="${BASH_REMATCH[3]}"
          body="${BASH_REMATCH[4]}"
          status="${BASH_REMATCH[5]}"
        elif [[ "$line" =~ ^-\ \[(.)\]\ ([0-9]{4}-[0-9]{2}-[0-9]{2}):\ (.*)\ \<!--\ status:([a-z:A-Z0-9_-]+)\ --\> ]]; then
          created="${BASH_REMATCH[2]}"
          body="${BASH_REMATCH[3]}"
          status="${BASH_REMATCH[4]}"
        fi
        [[ -z "$body" ]] && continue
        local title
        title=$(cmd_title_from_body "$body")
        if [[ -n "$uid" ]]; then
          jq -cn --arg uid "$uid" --argjson created "$created" \
                 --arg title "$title" --arg body "$body" --arg status "$status" \
            '{uid:$uid, created:$created, status:$status, title:$title, body:$body}' \
            >> "$ideas_log"
        else
          jq -cn --arg created "$created" \
                 --arg title "$title" --arg body "$body" --arg status "$status" \
            '{created:$created, status:$status, title:$title, body:$body}' \
            >> "$ideas_log"
        fi
        migrated_count=$((migrated_count + 1))
      done < "$project_dir/docs/ideas.md"
    else
      echo "Nothing to migrate: docs/ideas.md not found"
    fi
  fi

  # Delegate the config + gitignore write to cmd_idea_setup. Suppress its
  # next-step text (idea-upgrade emits its own summary).
  if [[ "$provider" == "linear" ]]; then
    cmd_idea_setup --provider linear --team "$team" --project "$project" "$project_dir" >/dev/null
  else
    cmd_idea_setup --provider local "$project_dir" >/dev/null
  fi

  # Archive-only semantic: Linear-configured nodes get a read-only header
  # prepended to .ccanvil/ideas.log. The log stays in place for historical
  # reference but new captures route through Linear. Idempotent — the header
  # is never duplicated on re-runs.
  if [[ "$provider" == "linear" ]]; then
    local ideas_log_archive="$project_dir/.ccanvil/ideas.log"
    mkdir -p "$(dirname "$ideas_log_archive")"
    touch "$ideas_log_archive"
    if ! grep -q '^# ARCHIVE:' "$ideas_log_archive" 2>/dev/null; then
      local iso_date
      iso_date=$(date -u +%Y-%m-%d)
      local tmp_log="${ideas_log_archive}.tmp.$$"
      {
        printf '# ARCHIVE: read-only after %s\n' "$iso_date"
        cat "$ideas_log_archive"
      } > "$tmp_log"
      mv "$tmp_log" "$ideas_log_archive"
    fi
  fi

  # Build the single commit. When --from-legacy migrated a tracked file,
  # git rm it so the deletion is in the same commit as the config write.
  local commit_msg="chore(idea-upgrade): configure $provider provider"
  (
    cd "$project_dir" || return 1
    if [[ $legacy_present -eq 1 ]]; then
      git rm -q docs/ideas.md 2>/dev/null || rm -f docs/ideas.md
    fi
    git add .claude/ccanvil.local.json .gitignore
    if [[ $legacy_present -eq 1 ]]; then
      git commit -q -m "chore(idea-upgrade): configure $provider provider + migrate $migrated_count legacy entries"
    else
      git commit -q -m "$commit_msg"
    fi
  )

  if [[ $legacy_present -eq 1 ]]; then
    echo "UPGRADE: node configured with provider=$provider; migrated $migrated_count entries to .ccanvil/ideas.log"
  else
    echo "UPGRADE: node configured with provider=$provider"
  fi
}

# cmd_title_from_body — Derive a concise title from an idea body.
#
# Usage:
#   title-from-body "<body>"
#   echo "<body>" | title-from-body
#
# Behavior:
#   - Empty body                → stdout empty, exit 0
#   - <=80 chars + single-line  → stdout is the body verbatim (fast path)
#   - Longer / multi-line, with `claude` CLI on PATH → invoke CLI and
#                                  truncate the reply to 80 chars.
#   - Longer / multi-line, no CLI → first 80 chars of first line
#                                    (deterministic fallback).
cmd_title_from_body() {
  local title_map=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title-map)
        title_map="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -n "$title_map" && ! -f "$title_map" ]]; then
    echo "ERROR: --title-map file not found: $title_map" >&2
    return 1
  fi

  local body
  if [[ $# -gt 0 ]]; then
    body="$1"
  else
    body=$(cat)
  fi

  if [[ -n "$title_map" ]]; then
    local mapped
    mapped=$(jq -r --arg b "$body" '.[$b] // empty' "$title_map" 2>/dev/null || echo '')
    if [[ -n "$mapped" ]]; then
      printf '%s' "$mapped"
      return 0
    fi
  fi

  if [[ -z "$body" ]]; then
    printf ''
    return 0
  fi

  local has_newline=0
  case "$body" in *$'\n'*) has_newline=1 ;; esac

  if [[ $has_newline -eq 0 && "${#body}" -le 80 ]]; then
    printf '%s' "$body"
    return 0
  fi

  if command -v claude >/dev/null 2>&1; then
    local prompt="Summarize the following idea as a concise title, <=80 chars, intent-preserving, no quotes, no trailing punctuation. Return only the title text."
    local reply
    reply=$(printf '%s\n\n%s' "$prompt" "$body" | claude -p 2>/dev/null) || reply=''
    reply="${reply%$'\n'}"
    if [[ -n "$reply" ]]; then
      printf '%s' "${reply:0:80}"
      return 0
    fi
  fi

  local first_line
  first_line="${body%%$'\n'*}"
  printf '%s' "${first_line:0:80}"
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

cmd="${1:-}"
shift || true

case "$cmd" in
  status)            cmd_status "$@" ;;
  validate)          cmd_validate "$@" ;;
  recommend)         cmd_recommend "$@" ;;
  audit-session)     cmd_audit_session "$@" ;;
  config-get)        cmd_config_get "$@" ;;
  list-specs)        cmd_list_specs "$@" ;;
  activate)          cmd_activate "$@" ;;
  complete)          cmd_complete "$@" ;;
  land)              cmd_land "$@" ;;
  radar-gather)      cmd_radar_gather "$@" ;;
  idea-add)          cmd_idea_add "$@" ;;
  idea-list)         cmd_idea_list "$@" ;;
  idea-count)        cmd_idea_count "$@" ;;
  idea-update)       cmd_idea_update "$@" ;;
  idea-sync)         cmd_idea_sync "$@" ;;
  idea-migrate)      cmd_idea_migrate "$@" ;;
  idea-setup)        cmd_idea_setup "$@" ;;
  idea-upgrade)      cmd_idea_upgrade "$@" ;;
  title-from-body)   cmd_title_from_body "$@" ;;
  legacy-refs-scan)  cmd_legacy_refs_scan "$@" ;;
  *)
    echo "Usage: docs-check.sh {status|validate|recommend|audit-session|config-get|list-specs|activate|complete|land|idea-add|idea-list|idea-count|idea-update|idea-sync|idea-migrate|idea-setup|idea-upgrade|title-from-body|legacy-refs-scan} [args...]" >&2
    exit 1
    ;;
esac
