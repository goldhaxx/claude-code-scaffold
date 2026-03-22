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

  # No docs at all
  if [[ "$spec_exists" != "true" && "$plan_exists" != "true" && "$cp_exists" != "true" ]]; then
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
# Dispatch
# ---------------------------------------------------------------------------

cmd="${1:-}"
shift || true

case "$cmd" in
  status)    cmd_status "$@" ;;
  validate)  cmd_validate "$@" ;;
  recommend) cmd_recommend "$@" ;;
  *)
    echo "Usage: docs-check.sh {status|validate|recommend} [docs-dir]" >&2
    exit 1
    ;;
esac
