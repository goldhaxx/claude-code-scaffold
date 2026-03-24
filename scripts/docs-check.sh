#!/usr/bin/env bash
# docs-check.sh — Deterministic docs lifecycle validation.
#
# Usage:
#   docs-check.sh status [docs-dir]      Extract metadata + compute hashes → JSON
#   docs-check.sh validate [docs-dir]    Check alignment between spec, plan, checkpoint
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
# Output: JSON object with spec, plan, checkpoint entries.
# ---------------------------------------------------------------------------
cmd_status() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"

  local spec_entry plan_entry cp_entry
  spec_entry=$(doc_entry "$docs_dir/spec.md" "spec")
  plan_entry=$(doc_entry "$docs_dir/plan.md" "plan")
  cp_entry=$(doc_entry "$docs_dir/checkpoint.md" "checkpoint")

  jq -n \
    --argjson spec "$spec_entry" \
    --argjson plan "$plan_entry" \
    --argjson checkpoint "$cp_entry" \
    '{spec: $spec, plan: $plan, checkpoint: $checkpoint}'
}

# ---------------------------------------------------------------------------
# cmd_validate — Check alignment between spec, plan, and checkpoint.
#
# Priority order: mismatched > stale-plan > stale-checkpoint > aligned
#
# Output: JSON with result, details array, and per-doc status.
# ---------------------------------------------------------------------------
cmd_validate() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  local status_json
  status_json=$(cmd_status "$docs_dir")

  local spec_exists plan_exists cp_exists
  spec_exists=$(echo "$status_json" | jq -r '.spec.exists')
  plan_exists=$(echo "$status_json" | jq -r '.plan.exists')
  cp_exists=$(echo "$status_json" | jq -r '.checkpoint.exists')

  local details="[]"
  local result="aligned"

  # Extract feature_ids
  local spec_fid plan_fid cp_fid
  spec_fid=$(echo "$status_json" | jq -r '.spec.feature_id // empty')
  plan_fid=$(echo "$status_json" | jq -r '.plan.feature_id // empty')
  cp_fid=$(echo "$status_json" | jq -r '.checkpoint.feature_id // empty')

  # Collect present feature_ids for mismatch check
  local fids=()
  [[ -n "$spec_fid" ]] && fids+=("$spec_fid")
  [[ -n "$plan_fid" ]] && fids+=("$plan_fid")
  [[ -n "$cp_fid" ]] && fids+=("$cp_fid")

  # Multi-spec: if no spec.md exists, check if specs/ has any specs
  # If so, this is "no-active-spec" (not an error — just no feature activated)
  if [[ "$spec_exists" != "true" && "$plan_exists" != "true" && "$cp_exists" != "true" ]]; then
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
  if [[ "$cp_exists" != "true" ]]; then
    details=$(echo "$details" | jq '. + ["checkpoint.md missing"]')
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
  if [[ "$cp_exists" == "true" && -z "$cp_fid" ]]; then
    details=$(echo "$details" | jq '. + ["checkpoint.md unlinked (no metadata)"]')
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

  # Check stale-checkpoint: plan's current hash vs checkpoint's stored plan_hash
  if [[ "$result" != "mismatched" && "$result" != "stale-plan" && "$plan_exists" == "true" && "$cp_exists" == "true" ]]; then
    local plan_current_hash cp_stored_plan_hash
    plan_current_hash=$(echo "$status_json" | jq -r '.plan.content_hash // empty')
    cp_stored_plan_hash=$(echo "$status_json" | jq -r '.checkpoint.plan_hash // empty')

    if [[ -n "$cp_stored_plan_hash" && -n "$plan_current_hash" && "$plan_current_hash" != "$cp_stored_plan_hash" ]]; then
      result="stale-checkpoint"
      details=$(echo "$details" | jq '. + ["plan content changed since checkpoint was written"]')
    fi
  fi

  # Check missing-determinism-review: checkpoint exists but lacks the required section
  if [[ "$result" == "aligned" && "$cp_exists" == "true" ]]; then
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
    done < "$docs_dir/checkpoint.md"

    if ! $has_review || ! $review_has_content; then
      result="missing-determinism-review"
      details=$(echo "$details" | jq '. + ["checkpoint.md missing Determinism Review section or section is empty"]')
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
#   stale-checkpoint  → "Update checkpoint"
#   aligned (no cp)   → "Ready to build"
#   aligned (with cp) → "/clear and /catchup to resume"
#
# Output: JSON with next_action and reason.
# ---------------------------------------------------------------------------
cmd_recommend() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  local validate_json
  validate_json=$(cmd_validate "$docs_dir")

  local result
  result=$(echo "$validate_json" | jq -r '.result')

  local spec_exists plan_exists cp_exists
  spec_exists=$(echo "$validate_json" | jq -r '.status.spec.exists')
  plan_exists=$(echo "$validate_json" | jq -r '.status.plan.exists')
  cp_exists=$(echo "$validate_json" | jq -r '.status.checkpoint.exists')

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
      next_action="Mark a spec as Ready, then activate it"
      reason="Specs exist in docs/specs/ but none are marked Ready."
    fi

  # No docs at all
  elif [[ "$spec_exists" != "true" && "$plan_exists" != "true" && "$cp_exists" != "true" ]]; then
    next_action="Describe a feature"
    reason="No spec, plan, or checkpoint found. Start by describing what you want to build."

  elif [[ "$result" == "unlinked" ]]; then
    next_action="Add lifecycle metadata to docs"
    reason="Documents exist but lack lifecycle metadata (Feature ID). Add metadata to enable validation."

  elif [[ "$result" == "mismatched" ]]; then
    next_action="Reconcile feature IDs"
    reason="Documents reference different features. Ensure all docs share the same feature_id."

  elif [[ "$result" == "stale-plan" ]]; then
    next_action="Re-run /plan"
    reason="Spec has changed since the plan was written. The plan is out of date."

  elif [[ "$result" == "stale-checkpoint" ]]; then
    next_action="Update checkpoint"
    reason="Plan has changed since the checkpoint was written. The checkpoint is out of date."

  elif [[ "$result" == "missing-determinism-review" ]]; then
    next_action="Add Determinism Review to checkpoint"
    reason="Checkpoint exists but is missing the required Determinism Review section. Add the section before clearing context."

  elif [[ "$spec_exists" == "true" && "$plan_exists" != "true" ]]; then
    next_action="Run /plan"
    reason="Spec exists but no plan. Create an implementation plan from the spec."

  elif [[ "$result" == "aligned" && "$cp_exists" == "true" ]]; then
    next_action="/clear and /catchup to resume"
    reason="All docs aligned with checkpoint. Ready to resume or start next feature."

  elif [[ "$result" == "aligned" && "$cp_exists" != "true" ]]; then
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
    if [[ "$line" =~ ^\+ && ! "$current_file" =~ ^scripts/.*\.sh$ ]]; then
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
  local feature_id="${1:?Usage: activate <feature-id> [docs-dir]}"
  local docs_dir="${2:-$DEFAULT_DOCS_DIR}"
  local specs_dir="$docs_dir/specs"
  local repo_root
  repo_root=$(cd "$docs_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || {
    repo_root=$(cd "$docs_dir/.." 2>/dev/null && pwd)
  }

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

  # Check worktree is clean
  if [[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ]]; then
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
  sed -i '' "s/^> Status: .*/> Status: In Progress/" "$spec_file" 2>/dev/null || \
    sed -i "s/^> Status: .*/> Status: In Progress/" "$spec_file"

  # Copy spec to docs/spec.md (after status update so it gets the new status)
  cp "$spec_file" "$docs_dir/spec.md"

  echo "Activated spec '$feature_id' on branch '$branch_name'"
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
  sed -i '' "s/^> Status: .*/> Status: Complete/" "$spec_file" 2>/dev/null || \
    sed -i "s/^> Status: .*/> Status: Complete/" "$spec_file"

  # Clear assumptions.md if it exists
  local assumptions_file="$docs_dir/assumptions.md"
  if [[ -f "$assumptions_file" ]]; then
    : > "$assumptions_file"
  fi

  echo "Completed spec '$feature_id'"
}

# ---------------------------------------------------------------------------
# merge_scaffold_config — Merge scaffold.json (hub) with scaffold.local.json (node).
# Duplicated from operations.sh (both scripts need it; keeping small and tested).
merge_scaffold_config() {
  local dir="$1"
  local hub_file="$dir/.claude/scaffold.json"
  local local_file="$dir/.claude/scaffold.local.json"

  if [[ ! -f "$hub_file" && ! -f "$local_file" ]]; then
    echo '{}'
    return 0
  fi

  if [[ -f "$hub_file" ]] && ! jq empty "$hub_file" 2>/dev/null; then
    echo "ERROR: .claude/scaffold.json is not valid JSON" >&2
    return 1
  fi

  if [[ -f "$local_file" ]] && ! jq empty "$local_file" 2>/dev/null; then
    echo "ERROR: .claude/scaffold.local.json is not valid JSON" >&2
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

# cmd_config_get — Read a feature toggle from merged scaffold config.
#
# Usage:
#   docs-check.sh config-get <key> [project-dir]
#
# Returns the value of features.<key> from the merged effective config
# (scaffold.json + scaffold.local.json). Returns "false" if files are
# missing, key is missing, or features object doesn't exist.
# ---------------------------------------------------------------------------
cmd_config_get() {
  local key="${1:?Usage: config-get <key> [project-dir]}"
  local project_dir="${2:-.}"

  local merged
  merged=$(merge_scaffold_config "$project_dir") || return 1

  local value
  value=$(echo "$merged" | jq -r --arg k "$key" '.features[$k] // "false"' 2>/dev/null)

  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "false"
  else
    echo "$value"
  fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

cmd="${1:-}"
shift || true

case "$cmd" in
  status)        cmd_status "$@" ;;
  validate)      cmd_validate "$@" ;;
  recommend)     cmd_recommend "$@" ;;
  audit-session) cmd_audit_session "$@" ;;
  config-get)    cmd_config_get "$@" ;;
  list-specs)    cmd_list_specs "$@" ;;
  activate)      cmd_activate "$@" ;;
  complete)      cmd_complete "$@" ;;
  *)
    echo "Usage: docs-check.sh {status|validate|recommend|audit-session|config-get|list-specs|activate|complete} [args...]" >&2
    exit 1
    ;;
esac
