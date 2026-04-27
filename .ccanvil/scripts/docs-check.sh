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
  local work=""
  local kind=""

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
          [Ww]ork)           work="$val" ;;
          [Kk]ind)           kind="$val" ;;
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
          Work:*)       work="${value#Work: }" ;;
          Kind:*)       kind="${value#Kind: }" ;;
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
  add_field "work" "$work"
  add_field "kind" "$kind"
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
# cmd_session_info — BTS-206. Read session counter + boundary state files.
#
# Args:
#   --project-dir <path>   project root (default: cwd)
#
# Output: JSON {counter, epoch, iso, tz} on stdout.
#   - counter: integer (0 if file missing or non-integer)
#   - epoch:   int or null (parsed from boundary JSON)
#   - iso:     string or null (parsed from boundary JSON)
#   - tz:      string or null (parsed from boundary JSON)
#
# Exit: always 0. Reading is fault-tolerant — corruption surfaces as 0/null,
# never as a non-zero exit. The SessionStart hook is what resets corruption.
# ---------------------------------------------------------------------------
cmd_session_info() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local counter_path boundary_path counter epoch iso tz raw
  counter_path="$project_dir/.ccanvil/state/session-counter"
  boundary_path="$project_dir/.ccanvil/state/session-boundary"

  counter=0
  if [[ -f "$counter_path" ]]; then
    raw=$(tr -d '[:space:]' < "$counter_path" 2>/dev/null || echo "")
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
      counter="$raw"
    else
      echo "WARN: session-counter contains non-integer; reading as 0" >&2
    fi
  fi

  epoch="null"; iso="null"; tz="null"
  if [[ -f "$boundary_path" ]] && jq -e . < "$boundary_path" >/dev/null 2>&1; then
    epoch=$(jq -c '.epoch // null' < "$boundary_path")
    iso=$(jq -c '.iso // null' < "$boundary_path")
    tz=$(jq -c '.tz // null' < "$boundary_path")
  fi

  jq -n \
    --argjson counter "$counter" \
    --argjson epoch "$epoch" \
    --argjson iso "$iso" \
    --argjson tz "$tz" \
    '{counter:$counter, epoch:$epoch, iso:$iso, tz:$tz}'
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

  # BTS-113 — surface the last-compact marker timestamp so /recall and other
  # consumers can reason about freshness. Null when the marker is missing
  # (first session, fresh clone, or PreCompact hook didn't fire).
  local project_root marker_path last_compact_ts
  project_root=$(dirname "$docs_dir")
  marker_path="$project_root/.ccanvil/state/last-compact-ts"
  if [[ -f "$marker_path" ]]; then
    # Strip whitespace (trailing newline from `date +%s >`, plus any stray
    # spaces) so the regex check downstream is tight.
    last_compact_ts=$(tr -d '[:space:]' < "$marker_path" 2>/dev/null || echo "")
  else
    last_compact_ts=""
  fi

  local last_compact_json="null"
  if [[ -n "$last_compact_ts" && "$last_compact_ts" =~ ^[0-9]+$ ]]; then
    last_compact_json="$last_compact_ts"
  fi

  jq -n \
    --argjson spec "$spec_entry" \
    --argjson plan "$plan_entry" \
    --argjson stasis "$stasis_entry" \
    --argjson last_compact_ts "$last_compact_json" \
    '{spec: $spec, plan: $plan, stasis: $stasis, last_compact_ts: $last_compact_ts}'
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

  # Extract Work: and Kind: (BTS-130 — provider-neutral work identity)
  local spec_work plan_work stasis_work stasis_kind
  spec_work=$(echo "$status_json" | jq -r '.spec.work // empty')
  plan_work=$(echo "$status_json" | jq -r '.plan.work // empty')
  stasis_work=$(echo "$status_json" | jq -r '.stasis.work // empty')
  stasis_kind=$(echo "$status_json" | jq -r '.stasis.kind // empty')

  # Determine which docs participate in feature alignment.
  # Session-kind stasis is AMBIENT state (written between features), not
  # feature state — it is excluded from alignment entirely. Absence of kind
  # defaults to feature-kind for backward-compat with pre-BTS-130 stasis files.
  local stasis_participates=true
  if [[ "$stasis_exists" == "true" && "$stasis_kind" == "session" ]]; then
    stasis_participates=false
  fi

  # Collect present feature_ids for the unlinked check below (fids[] counts
  # how many docs carry any metadata at all; session-stasis feature_ids are
  # still counted for "unlinked" detection because those are about metadata
  # presence, not feature alignment). Alignment proper uses align_keys[].
  local fids=()
  [[ -n "$spec_fid" ]] && fids+=("$spec_fid")
  [[ -n "$plan_fid" ]] && fids+=("$plan_fid")
  if $stasis_participates && [[ -n "$stasis_fid" ]]; then
    fids+=("$stasis_fid")
  fi

  # Pick alignment mode: prefer Work: equality when ALL participating docs
  # carry Work:; fall back to feature_id when any participating doc lacks it
  # (legacy grandfather — preserves existing projects pre-BTS-130 unchanged).
  local align_keys=()
  local use_work=true
  if [[ "$spec_exists" == "true" && -z "$spec_work" ]]; then use_work=false; fi
  if [[ "$plan_exists" == "true" && -z "$plan_work" ]]; then use_work=false; fi
  if $stasis_participates && [[ "$stasis_exists" == "true" && -z "$stasis_work" ]]; then
    use_work=false
  fi

  if $use_work; then
    [[ "$spec_exists" == "true" && -n "$spec_work" ]] && align_keys+=("$spec_work")
    [[ "$plan_exists" == "true" && -n "$plan_work" ]] && align_keys+=("$plan_work")
    if $stasis_participates && [[ "$stasis_exists" == "true" && -n "$stasis_work" ]]; then
      align_keys+=("$stasis_work")
    fi
  else
    [[ -n "$spec_fid" ]] && align_keys+=("$spec_fid")
    [[ -n "$plan_fid" ]] && align_keys+=("$plan_fid")
    if $stasis_participates && [[ -n "$stasis_fid" ]]; then
      align_keys+=("$stasis_fid")
    fi
  fi

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

  # Check alignment mismatch across participating docs.
  # align_keys contains Work: values when all docs have Work:, else feature_ids.
  # Session-kind stasis is never in align_keys (excluded above).
  if [[ ${#align_keys[@]} -ge 2 ]]; then
    local first="${align_keys[0]}"
    local mismatch=false
    for k in "${align_keys[@]}"; do
      if [[ "$k" != "$first" ]]; then
        mismatch=true
        break
      fi
    done
    if $mismatch; then
      result="mismatched"
      if $use_work; then
        details=$(echo "$details" | jq '. + ["Work: references do not match across documents"]')
      else
        details=$(echo "$details" | jq '. + ["feature_ids do not match across documents"]')
      fi
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
  # BTS-20: state derivation delegated to cmd_lifecycle_state — single
  # source of truth for "where in the lifecycle are we?" Recommend's job
  # is to render a single rich action string with context (Ready spec ID,
  # triage count, blocker details). Output schema unchanged for callers.
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  local project_root="$(dirname "$docs_dir")"

  local envelope state
  envelope=$(cmd_lifecycle_state --project-dir "$project_root")
  state=$(echo "$envelope" | jq -r '.state')

  local next_action reason

  case "$state" in
    no-active-spec)
      # Distinguish: Ready specs in backlog vs no specs at all.
      # Use status output — spec/plan/stasis all absent confirms "no docs"
      # vs specs/ existing with backlog items.
      local ready_spec specs_count
      ready_spec=$(cmd_list_specs "$docs_dir" 2>/dev/null \
        | jq -r '[.[] | select(.status == "Ready")] | first | .feature_id // empty' 2>/dev/null \
        || echo "")
      specs_count=$(cmd_list_specs "$docs_dir" 2>/dev/null \
        | jq -r 'length // 0' 2>/dev/null \
        || echo 0)
      if [[ -n "$ready_spec" ]]; then
        next_action="Activate a spec: docs-check.sh activate $ready_spec"
        reason="No active spec. Ready specs available in docs/specs/."
      elif [[ "$specs_count" -gt 0 ]]; then
        next_action="Activate a spec: docs-check.sh activate <id>"
        reason="Specs exist in docs/specs/ but none are activated."
      else
        next_action="Describe a feature"
        reason="No spec, plan, or stasis found. Start by describing what you want to build."
      fi
      ;;

    spec-activated)
      next_action="Run /plan"
      reason="Spec exists but no plan. Create an implementation plan from the spec."
      ;;

    plan-written)
      next_action="Ready to build"
      reason="Spec and plan are aligned. Start implementing via TDD."
      ;;

    implementing)
      # Feature-kind stasis present. /compact is the legal-next-action when
      # marker is stale (or absent); forward action when marker is fresh.
      local first_action_imp
      first_action_imp=$(echo "$envelope" | jq -r '.legal_next_actions[0].action // ""')
      if [[ "$first_action_imp" == "/compact" ]]; then
        next_action="/compact to wrap session"
        reason="All docs aligned with stasis. Run /compact to preserve context, then start the next feature."
      else
        # Post-compact, mid-feature: stasis already snapshot, compact already
        # ran, the operator is resuming. Reason makes the resumption explicit.
        next_action="Ready to build"
        reason="Resuming mid-feature implementation — continue from the stasis snapshot."
      fi
      ;;

    session-wrap)
      # Use the envelope's first legal action to determine pre- vs post-compact:
      # /compact in legal_next_actions[0] means stasis-fresh; otherwise compact
      # already fired and we surface forward action.
      local first_action triage_count
      first_action=$(echo "$envelope" | jq -r '.legal_next_actions[0].action // ""')
      if [[ "$first_action" == "/compact" ]]; then
        next_action="/compact to wrap session"
        reason="All docs aligned with stasis. Run /compact to preserve context, then start the next feature."
      else
        # Post-compact: prefer /idea triage when triage > 0, else /radar.
        triage_count=$(cmd_idea_count "$project_root" 2>/dev/null | jq -r '.triage // 0' 2>/dev/null || echo 0)
        if [[ -n "$triage_count" && "$triage_count" -gt 0 ]]; then
          next_action="$triage_count untriaged ideas — run /idea triage"
          reason="Compact already ran. Triage outstanding ideas before starting next feature."
        else
          next_action="/radar to brief the next feature"
          reason="Compact already ran. Review project state and start next feature."
        fi
      fi
      ;;

    blocked)
      # BTS-20 review WARN-1: read validate_result from the envelope (carried
      # by cmd_lifecycle_state) instead of re-running cmd_validate. Avoids a
      # second full validation pass on every blocked path.
      local validate_result
      validate_result=$(echo "$envelope" | jq -r '.validate_result // ""')
      case "$validate_result" in
        unlinked)
          next_action="Add lifecycle metadata to docs"
          reason="Documents exist but lack lifecycle metadata (Feature ID). Add metadata to enable validation."
          ;;
        mismatched)
          next_action="Reconcile feature IDs"
          reason="Documents reference different features. Ensure all docs share the same feature_id."
          ;;
        stale-plan)
          next_action="Re-run /plan"
          reason="Spec has changed since the plan was written. The plan is out of date."
          ;;
        stale-stasis)
          next_action="Update stasis"
          reason="Plan has changed since the stasis was written. The stasis is out of date."
          ;;
        missing-determinism-review)
          next_action="Add Determinism Review to stasis"
          reason="Stasis exists but is missing the required Determinism Review section. Add the section before clearing context."
          ;;
        *)
          next_action="Address blockers"
          reason=$(echo "$envelope" | jq -r '.blockers | join("; ")')
          ;;
      esac
      ;;

    uninitialized|*)
      next_action="Review docs state"
      reason="Unexpected state. Run docs-check.sh validate for details."
      ;;
  esac

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
  local current_line=0

  # Process diff line by line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Track current file from diff headers (also resets line counter)
    if [[ "$line" =~ ^diff\ --git\ a/(.+)\ b/ ]]; then
      current_file="${BASH_REMATCH[1]}"
      current_line=0
      continue
    fi
    # Also capture from +++ header
    if [[ "$line" =~ ^\+\+\+\ b/(.+) ]]; then
      current_file="${BASH_REMATCH[1]}"
      continue
    fi

    # Set line counter from @@ hunk header (anchors all subsequent + lines).
    if [[ "$line" =~ ^@@.*\+([0-9]+) ]]; then
      current_line="${BASH_REMATCH[1]}"
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
            --arg line_num "$current_line" \
            --arg context "$context" \
            '. + [{pattern: $pattern, file: $file, line: ($line_num | tonumber), context: $context}]')

          # Update category count
          categories=$(echo "$categories" | jq \
            --arg cat "$pname" \
            '.[$cat] = ((.[$cat] // 0) + 1)')
        fi
      done
      # Advance line counter for the next + line in this hunk.
      current_line=$((current_line + 1))
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
  # Parse args: <feature-id> [--force-local-ahead|--force-sync] [--no-auto-push] [docs-dir]
  # Flag can appear in any position among the positionals.
  # BTS-122: --force-sync is the canonical name; --force-local-ahead is the
  # legacy alias kept for backward compatibility. Both bypass ahead AND
  # behind checks (union semantics — "I know main has drifted, I want it").
  # BTS-145: --no-auto-push opts out of the auto-push-main behavior; default
  # is to auto-push when on main with unpushed commits (saves a manual step).
  local feature_id=""
  local docs_dir=""
  local force_sync=false
  local auto_push=true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force-local-ahead|--force-sync) force_sync=true; shift ;;
      --no-auto-push) auto_push=false; shift ;;
      *)
        if [[ -z "$feature_id" ]]; then feature_id="$1"
        elif [[ -z "$docs_dir" ]]; then docs_dir="$1"
        fi
        shift
        ;;
    esac
  done
  [[ -n "$feature_id" ]] || { echo "Usage: activate <feature-id> [--force-sync] [--no-auto-push] [docs-dir]" >&2; exit 1; }
  [[ -n "$docs_dir" ]] || docs_dir="$DEFAULT_DOCS_DIR"
  local specs_dir="$docs_dir/specs"
  local repo_root
  repo_root=$(cd "$docs_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || {
    repo_root=$(cd "$docs_dir/.." 2>/dev/null && pwd)
  }

  # BTS-122: delegate main↔origin/main sync verification to cmd_sync_check.
  # Exit code 0 = synced, 1 = ahead, 2 = behind. sync-check emits its own
  # error messages on stderr; we just add the escape-hatch hint.
  # `|| sc_rc=$?` captures the exit code without tripping `set -e`.
  if ! $force_sync; then
    local sc_rc=0
    cmd_sync_check "$repo_root" || sc_rc=$?

    # BTS-145: when AHEAD and on main, auto-push origin main (most common
    # friction point — write spec on main → activate fails → push → retry).
    # Only fires on `main` so unpushed feature-branch commits still error.
    if [[ "$sc_rc" -eq 1 ]] && $auto_push; then
      local current_branch
      current_branch=$(git -C "$repo_root" branch --show-current 2>/dev/null || echo "")
      if [[ "$current_branch" == "main" ]]; then
        echo "" >&2
        echo "AUTO-PUSH: local main is ahead of origin; pushing first..." >&2
        if git -C "$repo_root" push origin main 2>&1 >&2; then
          echo "AUTO-PUSH: success — proceeding with activation." >&2
          sc_rc=0
        else
          echo "ERROR: auto-push to origin/main failed." >&2
          echo "" >&2
          echo "Resolve manually and retry:" >&2
          echo "  git push origin main" >&2
          echo "  bash .ccanvil/scripts/docs-check.sh activate $feature_id" >&2
          echo "" >&2
          echo "Or skip auto-push: --no-auto-push" >&2
          exit 1
        fi
      fi
    fi

    if [[ "$sc_rc" -ne 0 ]]; then
      echo "" >&2
      echo "Or, if you know the drift is intentional:" >&2
      echo "  bash .ccanvil/scripts/docs-check.sh activate $feature_id --force-sync" >&2
      exit 1
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

  # BTS-122 AC-4: halt if the target branch already exists locally. `checkout -b`
  # fails generically; give the user a clear diagnostic and remediation options.
  if git -C "$repo_root" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
    echo "ERROR: branch '$branch_name' already exists." >&2
    echo "" >&2
    echo "Resolve by one of:" >&2
    echo "  git checkout $branch_name      # resume existing work" >&2
    echo "  git branch -D $branch_name     # delete and re-activate (loses branch state)" >&2
    exit 1
  fi

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
      local pr_title
      pr_title=$(cmd_derive_pr_title "$spec_file")
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

  # BTS-213: when spec is Linear-routed, mirror the just-committed In-Progress
  # spec content into the Linear Document via cmd_artifact_write. This keeps
  # the Linear-side content and metadata (Status: In Progress) in sync with
  # the local archive — closing the post-/spec, post-activate window where
  # lifecycle-state would otherwise read Linear and find nothing.
  local project_dir
  project_dir=$(cd "$docs_dir/.." 2>/dev/null && pwd) || project_dir="."
  if [[ "$(_lifecycle_route spec "$project_dir")" == "linear" ]]; then
    if ! cmd_artifact_write --kind spec --feature "$feature_id" < "$docs_dir/spec.md" >/dev/null; then
      echo "WARN: activate completed locally but Linear spec dispatch failed." >&2
      echo "Retry: bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature $feature_id < $docs_dir/spec.md" >&2
    fi
  fi

  # BTS-136: emit AUTO-TRANSITION marker for the linked Linear issue. The
  # /spec or /activate caller scans stdout and dispatches the MCP transition.
  # Silent for legacy specs (no Work:), local-provider, or unknown providers.
  cmd_auto_transition_emit "$branch_name" "in_progress" "$docs_dir"
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

  # BTS-204 Step 14: when any artifact is Linear-routed, delegate to the
  # archive helper (reads from Linear, writes git-tracked history into the
  # session archive directory, then trashes the Linear Documents). On
  # pure-local nodes this is a no-op — cmd_archive_stasis at /stasis time
  # already archives stasis; spec/plan stay in their original location.
  local project_dir
  project_dir=$(cd "$docs_dir/.." 2>/dev/null && pwd) || project_dir="."
  if [[ "$(_has_any_linear_route "$project_dir")" == "true" ]]; then
    _complete_archive_linear "$feature_id" "$project_dir"
  fi

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
# cmd_pr_cleanup — Pre-merge lifecycle cleanup invoked by the /pr skill.
#
# Usage:
#   docs-check.sh pr-cleanup [docs-dir]
#
# Behavior (primary path): when docs/spec.md exists, parse its feature_id and
# delegate to cmd_complete, which flips the archive to Complete, removes
# lifecycle docs, and commits on the feature branch. That commit rides the
# squash-merge into main — no manual `complete` follow-up needed.
#
# Fallback and error-halt behavior added in later steps.
# ---------------------------------------------------------------------------

cmd_pr_cleanup() {
  local docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  local spec_file="$docs_dir/spec.md"

  if [[ -f "$spec_file" ]]; then
    local feature_id
    feature_id=$(parse_metadata "$spec_file" | jq -r '.feature_id // empty')
    if [[ -z "$feature_id" ]]; then
      echo "ERROR: could not parse feature_id from $spec_file" >&2
      exit 1
    fi
    cmd_complete "$feature_id" "$docs_dir"
  else
    # Fallback: no active spec (e.g. `/pr` run on a branch without lifecycle spec).
    # Remove any lingering lifecycle docs and commit so nothing rides the merge.
    local repo_root
    repo_root=$(cd "$docs_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || repo_root="."
    rm -f "$docs_dir/spec.md" "$docs_dir/plan.md" "$docs_dir/stasis.md"
    (cd "$repo_root" && git add -A "$docs_dir/" 2>/dev/null || true)
    git -C "$repo_root" commit -q -m "docs(lifecycle): clean up lifecycle docs before merge" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# cmd_extract_work — Read a spec file's `> Work:` metadata and emit JSON.
#
# Usage:
#   docs-check.sh extract-work <spec-file>
#
# Outputs {"provider":"<p>","id":"<i>"} on stdout when the spec carries a
# parseable `> Work: <provider>:<id>` line. Outputs nothing (and exits 0) for
# legacy specs without `Work:` or malformed values — callers treat empty
# stdout as "no linkable work ref" and skip auto-transition silently
# (BTS-119 grandfather rule, AC-5).
#
# Splits on the FIRST colon only so provider-ids containing colons survive
# (e.g. a hypothetical `linear:BTS-1:subtask` would emit id="BTS-1:subtask").
# ---------------------------------------------------------------------------
cmd_extract_work() {
  local spec_file="${1:?Usage: extract-work <spec-file>}"
  if [[ ! -f "$spec_file" ]]; then
    echo "ERROR: spec file not found: $spec_file" >&2
    exit 1
  fi

  local work
  work=$(parse_metadata "$spec_file" | jq -r '.work // empty')
  # No Work: — legacy spec, grandfathered. Empty stdout, success.
  [[ -z "$work" ]] && return 0
  # Malformed: missing ':' separator. Empty stdout, success — callers skip.
  [[ "$work" != *:* ]] && return 0

  local provider="${work%%:*}"
  local id="${work#*:}"
  # Either half empty → malformed; empty stdout, success.
  [[ -z "$provider" || -z "$id" ]] && return 0

  jq -n --arg p "$provider" --arg i "$id" '{provider:$p,id:$i}'
}

# ---------------------------------------------------------------------------
# cmd_auto_close_emit — Map a landed branch to its linked Linear issue and
# emit an AUTO-CLOSE marker that a skill wrapper (/land) can dispatch.
#
# Usage:
#   docs-check.sh auto-close-emit <branch-name> [docs-dir]
#
# Invoked by cmd_land after the post-merge safety net, and directly by
# tests. Pure logic — no git side effects — so bats can exercise every
# branch of the decision tree (AC-5/6/7/9) without standing up a repo.
#
# Decision tree (BTS-119):
#   Branch ≠ claude/<type>/<slug>   → log skip, exit 0 (AC-9)
#   Spec file missing               → silent, exit 0 (non-spec branch)
#   Spec has no Work:               → silent, exit 0 (legacy, AC-5)
#   Work: linear:<ID>               → emit AUTO-CLOSE marker, exit 0
#   Work: local:<uid>               → log skip (scope is Linear-only, AC-6)
#   Work: <other>:<id>              → log skip (no adapter, AC-7)
# ---------------------------------------------------------------------------
cmd_auto_transition_emit() {
  # BTS-136 — emit AUTO-TRANSITION marker for a given role. Mirror of
  # cmd_auto_close_emit's decision tree — only difference is the role is
  # caller-specified and the marker prefix is different.
  local branch="${1:?Usage: auto-transition-emit <branch-name> <role> [docs-dir]}"
  local role="${2:?Usage: auto-transition-emit <branch-name> <role> [docs-dir]}"
  local docs_dir="${3:-$DEFAULT_DOCS_DIR}"

  if [[ ! "$branch" =~ ^claude/[^/]+/(.+)$ ]]; then
    return 0
  fi
  local feature_id="${BASH_REMATCH[1]}"
  local spec_file="${docs_dir}/specs/${feature_id}.md"
  if [[ ! -f "$spec_file" ]]; then
    return 0
  fi

  local work_json
  work_json=$(cmd_extract_work "$spec_file")
  if [[ -z "$work_json" ]]; then
    return 0
  fi

  local provider id
  provider=$(echo "$work_json" | jq -r '.provider')
  id=$(echo "$work_json" | jq -r '.id')

  case "$provider" in
    linear)
      # BTS-149 AC-10: emit the AUTO-TRANSITION marker only — no pre-enqueue.
      # The /activate skill enqueues to .ccanvil/ideas-pending.log only on
      # MCP failure (via idea-pending-append). Inverts the BTS-148
      # enqueue-on-every-call pattern, eliminating success-path write+ack
      # churn (~99% of activate runs succeed). Idempotency on Linear's side
      # makes failure-only enqueue safe — duplicate transitions are no-ops.
      jq -cn --arg id "$id" --arg role "$role" \
        '{provider:"linear",id:$id,role:$role}' | \
        sed 's/^/AUTO-TRANSITION: /'
      ;;
    *)
      # Local + unknown providers: silent. Linear-only auto-transition
      # matches BTS-119's Linear-only auto-close scope.
      return 0
      ;;
  esac
}

cmd_auto_close_emit() {
  local branch="${1:?Usage: auto-close-emit <branch-name> [docs-dir]}"
  local docs_dir="${2:-$DEFAULT_DOCS_DIR}"

  if [[ ! "$branch" =~ ^claude/[^/]+/(.+)$ ]]; then
    echo "auto-close: no feature-id detected in last merge commit — skipping"
    return 0
  fi
  local feature_id="${BASH_REMATCH[1]}"
  local spec_file="${docs_dir}/specs/${feature_id}.md"
  if [[ ! -f "$spec_file" ]]; then
    return 0
  fi

  local work_json
  work_json=$(cmd_extract_work "$spec_file")
  # Legacy spec without Work: → cmd_extract_work prints nothing.
  if [[ -z "$work_json" ]]; then
    return 0
  fi

  local provider id
  provider=$(echo "$work_json" | jq -r '.provider')
  id=$(echo "$work_json" | jq -r '.id')

  case "$provider" in
    linear)
      jq -cn --arg id "$id" '{provider:"linear",id:$id,role:"done"}' | \
        sed 's/^/AUTO-CLOSE: /'
      ;;
    local)
      echo "auto-close: local provider — skipping (BTS-119 Linear-only)"
      ;;
    *)
      echo "auto-close: provider '${provider}' — no adapter, skipping"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# cmd_sync_check — Verify local main is in sync with origin/main (BTS-122).
#
# Usage:
#   docs-check.sh sync-check <repo-root>
#
# Fetches origin/main (with http.lowSpeedTime=5 timeout) then compares local
# main against the refreshed ref. Exit codes:
#   0   in sync, or no-op (no origin remote, or no origin/main ref, or fetch
#       failed and we warned but let the caller proceed on cached state)
#   1   local AHEAD — unpushed commits would leak into a new feature branch
#   2   local BEHIND — activate would cut from a stale baseline
#
# Graceful degradation: fetch failures emit `WARN: offline — skipping sync
# check` on stderr and return 0. Matches BTS-119's "never block forward
# progress on network flakes" posture.
# ---------------------------------------------------------------------------
cmd_sync_check() {
  local repo_root="${1:?Usage: sync-check <repo-root>}"

  # AC-9: no origin remote at all → no-op success.
  if ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi

  # AC-1/AC-3: fetch with short timeout; degrade to WARN on failure.
  if ! git -C "$repo_root" \
      -c http.lowSpeedLimit=1 -c http.lowSpeedTime=5 \
      fetch origin main 2>/dev/null; then
    echo "WARN: offline — skipping sync check" >&2
    return 0
  fi

  # AC-9: fetch succeeded but origin/main ref still absent (empty remote).
  if ! git -C "$repo_root" rev-parse --verify origin/main >/dev/null 2>&1; then
    return 0
  fi

  local ahead behind
  ahead=$(git -C "$repo_root" rev-list --reverse --format="%h %s" \
            --no-commit-header origin/main..main 2>/dev/null || true)
  behind=$(git -C "$repo_root" rev-list --count main..origin/main 2>/dev/null || echo "0")

  # Ahead takes precedence over behind when diverged — unpushed leak is the
  # more dangerous failure mode.
  if [[ -n "$ahead" ]]; then
    echo "ERROR: local main is AHEAD of origin/main — unpushed commits would leak into the feature branch." >&2
    echo "" >&2
    echo "Unpushed commits:" >&2
    echo "$ahead" | sed 's/^/  /' >&2
    echo "" >&2
    echo "Resolve by pushing main first:" >&2
    echo "  git push origin main" >&2
    return 1
  fi

  if [[ "$behind" -gt 0 ]]; then
    echo "ERROR: local main is BEHIND origin/main by $behind commit(s) — activate would cut from a stale baseline." >&2
    echo "" >&2
    echo "Resolve by pulling first:" >&2
    echo "  git pull --ff-only origin main" >&2
    return 2
  fi

  return 0
}

# ---------------------------------------------------------------------------
# cmd_pr_guard — Verify the current feature branch is not behind its base
# (origin/main) before finalizing a PR (BTS-122 AC-5).
#
# Usage:
#   docs-check.sh pr-guard
#
# Invoked from the /pr skill's pre-flight block. Fetches origin/main and
# checks that no commits exist in origin/main that aren't already in HEAD.
# If the base has moved past the feature branch, a squash-merge will still
# work but the PR body won't reflect the latest base — more importantly,
# any CI that rebases against main will surface conflicts downstream.
#
# Exit codes:
#   0   feature branch is up-to-date with base, OR no origin/no origin/main
#       ref (no-op, matches cmd_sync_check AC-9), OR fetch failed (WARN:
#       emitted, graceful degradation)
#   1   feature branch is behind origin/main — rebase or merge to update
# ---------------------------------------------------------------------------
cmd_pr_guard() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "ERROR: not inside a git worktree." >&2
    exit 1
  }

  # No-op if no origin remote (fresh local-only repo).
  if ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi

  # Fetch with short timeout; degrade gracefully on failure.
  if ! git -C "$repo_root" \
      -c http.lowSpeedLimit=1 -c http.lowSpeedTime=5 \
      fetch origin main 2>/dev/null; then
    echo "WARN: offline — skipping pr-guard sync check" >&2
    return 0
  fi

  # No-op if origin/main ref absent after fetch.
  if ! git -C "$repo_root" rev-parse --verify origin/main >/dev/null 2>&1; then
    return 0
  fi

  # Commits in origin/main not in HEAD → base has moved past feature branch.
  local behind_count
  behind_count=$(git -C "$repo_root" rev-list --count HEAD..origin/main 2>/dev/null || echo "0")

  if [[ "$behind_count" -gt 0 ]]; then
    echo "ERROR: feature branch is BEHIND origin/main by $behind_count commit(s) — the PR base has moved." >&2
    echo "" >&2
    echo "Resolve by one of:" >&2
    echo "  git rebase origin/main         # linear history, preferred for draft PRs" >&2
    echo "  git merge origin/main          # merge-commit alternative" >&2
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# cmd_land_recover_branch — BTS-138: recover the landed feature branch name
# from the last squash-merge commit's `(#<PR>)` suffix via `gh pr view`.
#
# Usage:
#   docs-check.sh land-recover-branch
#
# Context: `gh pr merge --delete-branch` switches local HEAD to main and
# deletes the feature branch before ccanvil code runs. When cmd_land is
# invoked on main in that state, it cannot emit the AUTO-CLOSE marker via
# the on-branch path (branch is already gone). This helper recovers the
# branch name by inspecting the last squash-merge commit on main and
# querying GitHub — feeding the result into cmd_auto_close_emit.
#
# On success: echoes the recovered branch name, exit 0.
# On recoverable failure: empty stdout + WARN on stderr, exit 0 (never blocks).
#
# Runs inside the CWD's git repo. Caller is responsible for cd.
# ---------------------------------------------------------------------------
cmd_land_recover_branch() {
  # If HEAD commit subject looks like a session-stasis write (from /stasis
  # committed on main right before /compact), skip it and look at HEAD~1.
  local subject
  subject=$(git log -1 --format=%s 2>/dev/null)
  # Tightened from `^docs:[[:space:]]*stasis` (reviewer WARN): require at
  # least one space after `docs:` and ensure `stasis` is followed by a word
  # boundary (space or end) so `docs:stasis-notes` or `docs: stasisnotes`
  # don't falsely trigger the skip.
  if [[ "$subject" =~ ^docs:[[:space:]]+stasis([[:space:]]|$) ]]; then
    subject=$(git log -1 --skip=1 --format=%s 2>/dev/null)
  fi

  # Extract PR number from the trailing `(#<N>)` suffix — GitHub's canonical
  # squash-merge commit format.
  if [[ ! "$subject" =~ \(#([0-9]+)\)$ ]]; then
    echo "WARN: land on main — could not recover PR number from last commit" >&2
    return 0
  fi
  local pr="${BASH_REMATCH[1]}"

  # Require gh binary on PATH. Missing → WARN + skip (never fail).
  if ! command -v gh >/dev/null 2>&1; then
    echo "WARN: land on main — gh unavailable, skipping PR recovery" >&2
    return 0
  fi

  # Query the PR for its head ref. Exit nonzero or empty result → WARN + skip.
  # Avoid relying on $? after assignment — `if ! var=$(...)` captures the
  # subshell exit cleanly in both bash and strict-mode callers.
  local branch
  if ! branch=$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null) \
      || [[ -z "$branch" ]]; then
    echo "WARN: land on main — could not recover landed branch via gh (PR #$pr)" >&2
    return 0
  fi

  printf '%s\n' "$branch"
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

# ---------------------------------------------------------------------------
# BTS-72: detect-repo-type — classifier for the repo's lifecycle adapter.
# Returns one JSON line: {type, has_remote, remote_url}.
#
# type values:
#   github       — origin URL contains "github.com"
#   other-remote — origin set, not github.com (gitlab, bitbucket, github
#                  enterprise on non-github.com domain, etc.)
#   local        — no origin configured (purely local repo)
#
# Exits 2 with a stderr error when invoked outside a git repository.
# ---------------------------------------------------------------------------
cmd_detect_repo_type() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: detect-repo-type: not in a git repository" >&2
    return 2
  fi

  local remote_url=""
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")

  # Reviewer CONCERN-1: extract the URL's HOST before classifying so a
  # repo with `github.com` in its path (e.g., gitlab.com:user/github.com-mirror.git)
  # doesn't poison the substring match.
  local host=""
  if [[ "$remote_url" =~ ^git@([^:]+): ]]; then
    host="${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ ^https?://([^/]+)/ ]]; then
    host="${BASH_REMATCH[1]}"
  fi

  local type has_remote
  if [[ -z "$remote_url" ]]; then
    type="local"
    has_remote=false
  elif [[ "$host" == "github.com" || "$host" == *.github.com ]]; then
    type="github"
    has_remote=true
  else
    type="other-remote"
    has_remote=true
  fi

  jq -n --arg type "$type" --arg url "$remote_url" --argjson has_remote "$has_remote" \
    '{type:$type, has_remote:$has_remote, remote_url:$url}'
}

cmd_land() {
  local force=false
  [[ "${1:-}" == "--force" ]] && force=true

  local branch
  branch=$(git branch --show-current 2>/dev/null)

  # BTS-72: classify repo type once. Local-only repos skip gh-PR checks
  # and perform an in-place merge instead of fetching from a non-existent
  # origin.
  local repo_type
  repo_type=$(cmd_detect_repo_type 2>/dev/null | jq -r '.type // empty' 2>/dev/null || echo "")

  # Already on main: gh pr merge --delete-branch switches to main and deletes
  # the local branch itself. In that case, fast-forward local main to origin
  # so subsequent work starts from a clean, in-sync state, then recover the
  # landed branch via the last squash-merge + gh pr view and delegate to the
  # existing cmd_auto_close_emit (BTS-138). This closes the determinism gap
  # where /land on main was silently skipping the AUTO-CLOSE marker.
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

    # BTS-138: recover landed branch from last squash-merge's (#<PR>) suffix
    # and delegate to the existing AUTO-CLOSE emitter. Silent no-op on any
    # recovery failure — never blocks forward progress.
    local recovered_branch
    recovered_branch=$(cmd_land_recover_branch)
    if [[ -n "$recovered_branch" ]]; then
      cmd_auto_close_emit "$recovered_branch"
    fi
    return 0
  fi

  # Check if PR is merged (unless --force, and skip on local-only repos
  # since there is no PR concept). BTS-72: local-only path merges
  # in-place after switching to main below.
  if ! $force && [[ "$repo_type" != "local" ]] && command -v gh >/dev/null 2>&1; then
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

  # BTS-72: local-only — merge the feature branch in-place if not yet
  # merged. Equivalent to a "local PR merge" — no remote, no gh, just git.
  # Reviewer BLOCKING-2: on conflict, abort the in-flight merge cleanly so
  # the next invocation doesn't see HEAD on main with MERGE_HEAD lingering.
  if [[ "$repo_type" == "local" ]]; then
    if ! git merge-base --is-ancestor "$branch" HEAD 2>/dev/null; then
      if git -c commit.gpgsign=false merge --no-ff --no-edit "$branch" 2>/dev/null; then
        echo "Merged '$branch' into main (local-only)."
      else
        # Clean up the partial merge state before exiting so retry semantics
        # are well-defined. The user is left on main with a clean tree and
        # the original feature branch still intact.
        git merge --abort 2>/dev/null || true
        git checkout "$branch" 2>/dev/null || true
        echo "ERROR: Could not merge '$branch' into main (conflicts). Aborted; resolve on the feature branch and re-run." >&2
        exit 1
      fi
    fi
  fi

  # Fetch and reset (if remote exists). BTS-122 AC-7: fetch failure degrades
  # gracefully — emit WARN: and SKIP the hard reset so we don't blow away
  # local main in favor of a stale cached ref (or no ref at all).
  if git remote get-url origin >/dev/null 2>&1; then
    if git fetch origin 2>/dev/null; then
      echo "Fetched origin."
      local sha
      sha=$(git rev-parse --short origin/main 2>/dev/null || git rev-parse --short origin/master 2>/dev/null || echo "unknown")
      git reset --hard "origin/main" 2>/dev/null || git reset --hard "origin/master" 2>/dev/null || true
      echo "Main updated to $sha."
    else
      echo "WARN: offline — skipping origin fetch and reset. Local main left at current HEAD." >&2
    fi
  fi

  # Post-merge safety net: if the landed branch maps to a spec archive that's
  # still In Progress on main, transition it to Complete. Covers the case
  # where /pr was skipped (PR merged directly from the GitHub UI, etc.).
  if [[ "$branch" =~ ^claude/[^/]+/(.+)$ ]]; then
    local safety_feature_id="${BASH_REMATCH[1]}"
    local safety_spec_file="${DEFAULT_DOCS_DIR}/specs/${safety_feature_id}.md"
    if [[ -f "$safety_spec_file" ]]; then
      local safety_status
      safety_status=$(parse_metadata "$safety_spec_file" | jq -r '.status // empty')
      if [[ "$safety_status" == "In Progress" ]]; then
        update_metadata_status "$safety_spec_file" "Complete"
        ALLOW_MAIN=1 git add "$safety_spec_file" 2>/dev/null
        ALLOW_MAIN=1 git -c commit.gpgsign=false commit -q \
          -m "docs(lifecycle): complete ${safety_feature_id} — post-merge cleanup" 2>/dev/null
        if git remote get-url origin >/dev/null 2>&1; then
          git push origin main 2>/dev/null || true
        fi
        echo "Safety net: transitioned '${safety_feature_id}' to Complete."
      fi
    fi
  fi

  # BTS-119: emit AUTO-CLOSE marker for the skill wrapper (/land) to dispatch
  # the Linear issue transition to Done. Pure emission — the skill parses
  # stdout, resolves `ticket.transition <id> done`, and handles MCP +
  # pending-log fallback. Users who invoke this script directly (bypassing
  # the /land skill) see the marker on stdout; auto-close does not fire and
  # the Linear issue stays open until it is transitioned manually or /land
  # is used on the next merge.
  cmd_auto_close_emit "$branch"

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

  # Idea count — cmd_idea_count is now provider-aware (BTS-164). It dispatches
  # to local log read or Linear API query based on routing.idea config. The
  # previous gate `[[ -f .ccanvil/ideas.log ]]` was wrong because it
  # presupposed local routing; on Linear-routed projects the local log is
  # absent but cmd_idea_count works against Linear via linear-query.sh.
  # On any failure (missing LINEAR_API_KEY, network, etc.) fall back to the
  # zero-count default so radar stays useful even when the count path is
  # broken.
  local idea_counts='{"total":0,"new":0,"icebox_stale_count":0}'
  local project_dir
  project_dir=$(dirname "$docs_dir")
  local fresh_counts
  if fresh_counts=$(cmd_idea_count "$project_dir" 2>/dev/null) && [[ -n "$fresh_counts" ]]; then
    idea_counts="$fresh_counts"
    # Icebox-stale augmentation only makes sense for local routing today
    # (cmd_idea_review_icebox reads the JSONL log). On Linear-routed
    # projects the icebox_stale_count stays at 0 until Step 7 migrates the
    # review-icebox path to the http substrate. Guard on file presence.
    if [[ -f "$project_dir/.ccanvil/ideas.log" ]]; then
      local stale_count
      stale_count=$(cmd_idea_review_icebox "$project_dir" | jq 'length')
      idea_counts=$(echo "$idea_counts" | jq --argjson n "$stale_count" '. + {"icebox_stale_count": $n}')
    else
      idea_counts=$(echo "$idea_counts" | jq '. + {"icebox_stale_count": 0}')
    fi
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
  local parent=""
  local project_dir="."

  # Parse args: first positional is body, then optional --title / --parent
  # flags, final positional (if any) is the project dir (defaults to cwd).
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)
        title="$2"; shift 2 ;;
      --parent)
        # BTS-162: capture-time parent link. Validate at parse time so
        # malformed values fail before the JSONL write.
        if [[ -z "$2" ]]; then
          echo "ERROR: idea-add: --parent requires a non-empty value" >&2
          return 2
        fi
        if [[ "$2" =~ [[:space:]] ]]; then
          echo "ERROR: idea-add: --parent value '$2' contains whitespace" >&2
          return 2
        fi
        parent="$2"; shift 2 ;;
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

  [[ -n "$body" ]] || { echo "Usage: idea-add <body> [--title TITLE] [--parent REF] [project-dir]" >&2; exit 1; }

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

  if [[ -n "$parent" ]]; then
    jq -cn --arg uid "$uid" --argjson created "$epoch" \
           --arg title "$title" --arg body "$body" --arg parent "$parent" \
      '{uid:$uid, created:$created, status:"triage", title:$title, body:$body, parent_id:$parent}' \
      >> "$ideas_log"
  else
    jq -cn --arg uid "$uid" --argjson created "$epoch" \
           --arg title "$title" --arg body "$body" \
      '{uid:$uid, created:$created, status:"triage", title:$title, body:$body}' \
      >> "$ideas_log"
  fi

  echo "Captured: $title"
}

# ---------------------------------------------------------------------------
# BTS-172: idea-template-body — compose templated idea bodies from explicit
# flags. Prepends fixed-order sections (captured-during, surfaced-at,
# Family) before the original body. Missing flags collapse the
# corresponding section without leaving stray blank lines.
#
# Usage:
#   docs-check.sh idea-template-body --body BODY \
#     [--source-skill NAME] [--context TEXT] [--family A,B,C] \
#     [project-dir]
# ---------------------------------------------------------------------------
cmd_idea_template_body() {
  local body=""
  local source_skill=""
  local context=""
  local family=""
  local project_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)
        body="$2"; shift 2 ;;
      --source-skill)
        if [[ -z "$2" ]]; then
          echo "ERROR: idea-template-body: --source-skill requires a non-empty value" >&2
          return 2
        fi
        source_skill="$2"; shift 2 ;;
      --context)
        if [[ -z "$2" ]]; then
          echo "ERROR: idea-template-body: --context requires a non-empty value" >&2
          return 2
        fi
        context="$2"; shift 2 ;;
      --family)
        # Validate the raw value is non-empty AND contains at least one
        # non-comma, non-whitespace character.
        if [[ -z "$2" ]]; then
          echo "ERROR: idea-template-body: --family requires a non-empty comma-separated list" >&2
          return 2
        fi
        if [[ ! "$2" =~ [^[:space:],] ]]; then
          echo "ERROR: idea-template-body: --family requires a non-empty comma-separated list" >&2
          return 2
        fi
        family="$2"; shift 2 ;;
      *)
        project_dir="$1"; shift ;;
    esac
  done

  [[ -n "$body" ]] || { echo "Usage: idea-template-body --body BODY [--source-skill X] [--context X] [--family A,B] [project-dir]" >&2; return 1; }

  # Compose output. Each section is emitted only when its flag is set;
  # blank-line separators only appear between present sections.
  local out=""
  local need_blank=false

  if [[ -n "$source_skill" ]]; then
    out+="Captured during /$source_skill walk-through."$'\n'
    need_blank=true
  fi

  if [[ -n "$context" ]]; then
    out+="Surfaced at $context."$'\n'
    need_blank=true
  fi

  if [[ -n "$family" ]]; then
    [[ "$need_blank" == true ]] && out+=$'\n'
    out+="## Family"$'\n'
    # Split on comma, trim each item, emit one bullet per non-empty.
    local IFS=','
    local item
    for item in $family; do
      # Trim leading/trailing whitespace.
      item="${item#"${item%%[![:space:]]*}"}"
      item="${item%"${item##*[![:space:]]}"}"
      [[ -z "$item" ]] && continue
      out+="- $item"$'\n'
    done
    need_blank=true
  fi

  # Blank line between prepended sections and the original body, only if
  # we actually prepended something.
  [[ "$need_blank" == true ]] && out+=$'\n'
  out+="$body"

  printf '%s\n' "$out"
}

cmd_idea_list() {
  local filter_status=""
  local project_dir="."
  local include_archive=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status)          filter_status="$2"; shift 2 ;;
      --include-archive) include_archive=1; shift ;;
      *)                 project_dir="$1"; shift ;;
    esac
  done

  # Linear-configured nodes: the live query goes through /idea list; this
  # script surfaces the historical archive only when --include-archive is
  # passed.
  local local_cfg="$project_dir/.claude/ccanvil.local.json"
  local routing=""
  if [[ -f "$local_cfg" ]]; then
    routing=$(jq -r '.integrations.routing.idea // ""' "$local_cfg" 2>/dev/null || echo '')
  fi

  if [[ "$routing" == "linear" ]]; then
    echo "Linear-configured node — run /idea list for live queries."
    if [[ $include_archive -eq 1 ]]; then
      echo ""
      echo "ARCHIVE:"
      local ideas_log="$project_dir/.ccanvil/ideas.log"
      if [[ -f "$ideas_log" ]]; then
        grep -v '^# ' "$ideas_log" | jq -s "[.[] | {id: .uid, created: .created, title: .title, body: .body, status: .status}]" 2>/dev/null || echo "[]"
      else
        echo "[]"
      fi
    fi
    return 0
  fi

  local ideas_log="$project_dir/.ccanvil/ideas.log"
  if [[ ! -f "$ideas_log" ]]; then
    echo "[]"
    return 0
  fi

  local jq_shape='{id: .uid, created: .created, title: .title, body: .body, status: .status}'
  if [[ -n "$filter_status" ]]; then
    # Translation table: five-state vocab → matching set including legacy alias.
    # Legacy names remain valid filter inputs (resolve to their new-vocab set).
    local equivalents
    case "$filter_status" in
      triage|new)              equivalents='["triage","new"]' ;;
      backlog|promoted)        equivalents='["backlog","promoted"]' ;;
      icebox|parked)           equivalents='["icebox","parked"]' ;;
      canceled|dismissed)      equivalents='["canceled","dismissed"]' ;;
      duplicate|merged)        equivalents='["duplicate","merged"]' ;;
      *)                       equivalents=$(printf '%s' "$filter_status" | jq -Rs '[.]') ;;
    esac
    grep -v '^# ' "$ideas_log" | jq -s --argjson set "$equivalents" \
      "[.[] | select(.status as \$s | \$set | index(\$s)) | $jq_shape]"
  else
    # Default view: exclude terminal (canceled, duplicate) + deferred (icebox)
    # states, plus their legacy aliases. Surface them via explicit --status.
    local excluded='["icebox","parked","canceled","dismissed","duplicate","merged"]'
    grep -v '^# ' "$ideas_log" | jq -s --argjson exc "$excluded" \
      "[.[] | select(.status as \$s | \$exc | index(\$s) | not) | $jq_shape]"
  fi
}

cmd_idea_count_local() {
  # Reads the gitignored .ccanvil/ideas.log JSONL and aggregates by status.
  # Renamed from cmd_idea_count in BTS-164 — cmd_idea_count is now a thin
  # dispatcher that resolves the routing and calls this for the local path
  # or shells out to linear-query.sh for the http path.
  local project_dir="${1:-.}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"

  # Five-state vocab: triage/backlog/icebox/canceled/duplicate.
  # Legacy vocab folds in: new→triage, promoted→backlog, parked→icebox,
  # dismissed→canceled, merged→duplicate. `new` stays as a back-compat alias
  # for the triage counter so existing callers (radar-gather et al.) don't
  # regress.
  if [[ ! -f "$ideas_log" ]]; then
    jq -n '{total:0, triage:0, backlog:0, icebox:0, canceled:0, duplicate:0, new:0, promoted:0, parked:0, dismissed:0, merged:0}'
    return 0
  fi

  grep -v '^# ' "$ideas_log" | jq -s '
    def triage_set: ["triage", "new"];
    def backlog_set: ["backlog", "promoted"];
    def icebox_set: ["icebox", "parked"];
    def canceled_set: ["canceled", "dismissed"];
    def duplicate_set: ["duplicate", "merged"];
    {
      total:     length,
      triage:    [.[] | select(.status as $s | triage_set    | index($s))] | length,
      backlog:   [.[] | select(.status as $s | backlog_set   | index($s))] | length,
      icebox:    [.[] | select(.status as $s | icebox_set    | index($s))] | length,
      canceled:  [.[] | select(.status as $s | canceled_set  | index($s))] | length,
      duplicate: [.[] | select(.status as $s | duplicate_set | index($s))] | length,
      # Legacy aliases — retained for radar-gather + existing callers.
      new:       [.[] | select(.status as $s | triage_set    | index($s))] | length,
      promoted:  [.[] | select(.status as $s | backlog_set   | index($s))] | length,
      parked:    [.[] | select(.status as $s | icebox_set    | index($s))] | length,
      dismissed: [.[] | select(.status as $s | canceled_set  | index($s))] | length,
      merged:    [.[] | select(.status as $s | duplicate_set | index($s))] | length
    }'
}

cmd_idea_count() {
  # BTS-164: provider-aware idea counter. Resolves idea.count to determine
  # whether to read the local JSONL log (mechanism=bash) or shell out to
  # linear-query.sh and aggregate Linear state (mechanism=http). Same
  # output shape regardless of mechanism so radar-gather and /recall stay
  # provider-neutral.
  local project_dir="${1:-.}"
  local ops="$(dirname "$0")/operations.sh"

  local resolution
  resolution=$(bash "$ops" resolve idea.count --project-dir "$project_dir" 2>/dev/null) || {
    # Resolver failure → fall back to local-log read. Keeps radar-gather
    # working on projects without an operations.sh contract update.
    cmd_idea_count_local "$project_dir"
    return $?
  }

  local mechanism
  mechanism=$(printf '%s' "$resolution" | jq -r '.mechanism')

  case "$mechanism" in
    bash)
      cmd_idea_count_local "$project_dir"
      ;;
    http)
      # BTS-167: env-var presence is enforced by linear-query.sh itself —
      # it auto-sources project-root .env when LINEAR_API_KEY is unset and
      # fails loud (exit 2 with remediation hint) when neither path provides
      # a key. The caller-side pre-flight check that lived here became
      # redundant: it duplicated linear-query.sh's contract and fired
      # before the substrate could load .env.
      local cmd
      cmd=$(printf '%s' "$resolution" | jq -r '.invocation.command')

      local issues
      issues=$(eval "$cmd") || {
        echo "ERROR: idea-count: linear-query.sh invocation failed" >&2
        return 3
      }

      # Aggregate by status NAME (matching the five-state vocab in Linear's
      # workspace: Triage, Backlog, Icebox, Canceled, Duplicate). Other
      # workflow states (Todo, In Progress, Done) are not idea-state vocab
      # and don't roll up into these counts.
      printf '%s' "$issues" | jq '
        def by_status(name): map(select(.status == name)) | length;
        {
          total:     length,
          triage:    by_status("Triage"),
          backlog:   by_status("Backlog"),
          icebox:    by_status("Icebox"),
          canceled:  by_status("Canceled"),
          duplicate: by_status("Duplicate"),
          new:       by_status("Triage"),
          promoted:  by_status("Backlog"),
          parked:    by_status("Icebox"),
          dismissed: by_status("Canceled"),
          merged:    by_status("Duplicate")
        }'
      ;;
    *)
      echo "ERROR: idea-count: unknown mechanism '$mechanism'" >&2
      return 1
      ;;
  esac
}

# cmd_idea_migrate_state — rewrite legacy-vocab status values in ideas.log.
#
# Translates new→triage, promoted→backlog, parked→icebox, dismissed→canceled,
# merged→duplicate. Writes a timestamped backup before mutating. Idempotent:
# a second run against a log with no legacy entries reports 0 migrations.
cmd_idea_migrate_state() {
  local project_dir="${1:-.}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"

  if [[ ! -f "$ideas_log" ]]; then
    echo "0 entries migrated (no ideas.log at $ideas_log)"
    return 0
  fi

  # Count legacy entries up front for the idempotency signal.
  local legacy_count
  legacy_count=$(grep -cE '"status":"(new|promoted|parked|dismissed|merged)"' "$ideas_log" || true)

  if [[ "$legacy_count" -eq 0 ]]; then
    echo "0 entries migrated (no legacy entries in $ideas_log)"
    return 0
  fi

  # Timestamped backup before mutation.
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  cp "$ideas_log" "${ideas_log}.${ts}.bak"

  local tmp
  tmp=$(mktemp)
  jq -c '
    . + {status:
      (if   .status == "new"       then "triage"
       elif .status == "promoted"  then "backlog"
       elif .status == "parked"    then "icebox"
       elif .status == "dismissed" then "canceled"
       elif .status == "merged"    then "duplicate"
       else .status
       end)
    }
  ' "$ideas_log" > "$tmp"
  mv "$tmp" "$ideas_log"

  echo "$legacy_count entries migrated (backup at ${ideas_log}.${ts}.bak)"
}

# cmd_idea_review_icebox — list icebox entries older than 60 days.
#
# Outputs a JSON array (same shape as idea-list) for entries whose status
# is icebox (or legacy alias "parked") and whose `created` epoch is at
# least 60 days (5184000s) in the past. Used by /idea review-icebox and
# surfaced as a count via radar-gather.
cmd_idea_review_icebox() {
  local project_dir="${1:-.}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"
  local now threshold
  now=$(date +%s)
  threshold=$((now - 5184000))

  if [[ ! -f "$ideas_log" ]]; then
    echo "[]"
    return 0
  fi

  grep -v '^# ' "$ideas_log" | jq -s --argjson t "$threshold" '
    [ .[]
      | select((.status == "icebox" or .status == "parked") and .created <= $t)
      | {id: .uid, created: .created, title: .title, body: .body, status: .status}
    ]
  '
}

cmd_idea_update() {
  local uid="${1:?Usage: idea-update <uid> <status> [project-dir]}"
  local new_status="${2:?Usage: idea-update <uid> <status> [project-dir]}"
  local project_dir="${3:-.}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"

  # Accept new vocab (triage/backlog/icebox/canceled/duplicate) and legacy
  # aliases (new/promoted/parked/dismissed/merged). Reject anything else
  # so typos fail loudly instead of silently corrupting the log.
  case "$new_status" in
    triage|backlog|icebox|canceled|duplicate) ;;
    new|promoted|parked|dismissed|merged) ;;
    *)
      echo "ERROR: unknown status '$new_status' (expected one of: triage, backlog, icebox, canceled, duplicate)" >&2
      exit 1
      ;;
  esac

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
# BTS-179: replay orchestration moved to cmd_idea_pending_replay (substrate
# dispatch primitive). cmd_idea_sync remains as: (a) the enumerate-only
# primitive (`idea-sync` with no args → `{pending, entries}` JSON for any
# external consumer that needs to inspect the pending queue) and (b) a
# standalone operator-callable ack subcommand for manual recovery
# (`idea-sync --ack <ts>`). Neither is on the normal /idea sync hot path
# any more; both are preserved for backwards compat and ad-hoc use.
#
# Supported ops (written by /idea or /land skills when the corresponding
# Linear call fails; replayed by /idea sync):
#   add               — failed capture: args = {title, body}
#                       (BTS-166: replayed via http substrate — re-resolve
#                       idea.add and pipe stdin-JSON {title, description})
#   promote           — failed triage-promote: args = {id, priority}
#   defer             — failed triage-defer: args = {id}
#   dismiss           — failed triage-dismiss: args = {id}
#   merge             — failed triage-merge: args = {id, duplicateOf}
#   ticket.transition — failed auto-close from /land (BTS-119) or auto-
#                       transition from /spec/activate (BTS-136):
#                       args = {id, role}. Idempotent — replaying a
#                       transition to the current state is a no-op.
#
# Each entry has shape: {op, args, ts}
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
# cmd_refresh_plan_hash — BTS-177: recompute docs/spec.md content_hash and
# rewrite docs/plan.md's `> Spec hash: <hash>` line to match. Idempotent:
# re-running when hashes already match is a no-op.
#
# Eliminates the manual plan-hash edit Claude was performing on mid-flow
# spec scope expansion (BTS-175 live-API discovery, 2026-04-25).
#
# Invocation:
#   refresh-plan-hash [--project-dir <dir>]
#
# Output: {updated: <bool>, spec_hash: "<hash>", plan: "docs/plan.md"}
# Exit 0 on success (including no-op); non-zero on missing spec/plan or
# malformed plan metadata.
# ---------------------------------------------------------------------------
cmd_refresh_plan_hash() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local spec_file="$project_dir/docs/spec.md"
  local plan_file="$project_dir/docs/plan.md"

  if [[ ! -f "$spec_file" ]]; then
    echo "ERROR: docs/spec.md not found" >&2
    return 1
  fi
  if [[ ! -f "$plan_file" ]]; then
    echo "ERROR: docs/plan.md not found" >&2
    return 1
  fi
  if ! grep -qE '^> Spec hash: [a-f0-9]{6,}' "$plan_file"; then
    echo "ERROR: docs/plan.md has no '> Spec hash:' metadata line" >&2
    return 1
  fi

  local new_hash current_hash
  new_hash=$(content_hash "$spec_file")
  current_hash=$(grep -E '^> Spec hash: [a-f0-9]{6,}' "$plan_file" | head -1 | sed -E 's/^> Spec hash: //')

  if [[ "$new_hash" == "$current_hash" ]]; then
    jq -n --arg h "$new_hash" '{updated:false, spec_hash:$h, plan:"docs/plan.md"}'
    return 0
  fi

  # Atomic rewrite: tmpfile + mv.
  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN
  sed -E "s|^> Spec hash: [a-f0-9]{6,}|> Spec hash: $new_hash|" "$plan_file" > "$tmp"
  mv "$tmp" "$plan_file"

  jq -n --arg h "$new_hash" '{updated:true, spec_hash:$h, plan:"docs/plan.md"}'
}

# ---------------------------------------------------------------------------
# cmd_derive_pr_title — BTS-181: derive a deterministic PR title from a spec
# file in the form `feat(<feature-id>): <truncated-first-summary-line>`.
# Truncation rules:
#   - First period in the Summary line strips everything from the period on.
#   - Remaining suffix is capped at 80 chars (trailing whitespace trimmed).
#   - Empty Summary section falls back to `activate feature`.
# Used by cmd_activate (PR creation) and cmd_assert_pr_title (PR title repair).
# ---------------------------------------------------------------------------
cmd_derive_pr_title() {
  local spec_file="${1:-}"
  local lookback=8
  if [[ -z "$spec_file" ]]; then
    echo "ERROR: derive-pr-title: missing <spec-file> argument" >&2
    return 1
  fi
  if [[ ! -f "$spec_file" ]]; then
    echo "ERROR: derive-pr-title: spec file not found: $spec_file" >&2
    return 1
  fi

  local feature_id_meta first_line
  feature_id_meta=$(grep -m1 '^> Feature:' "$spec_file" | sed -E 's/^> Feature:[[:space:]]*//')
  first_line=$(sed -n '/^## Summary$/,/^## /{ /^## /d; /^$/d; p; }' "$spec_file" | head -1 | sed 's/^[[:space:]]*//')

  if [[ -z "$first_line" ]]; then
    echo "feat(${feature_id_meta}): activate feature"
    return 0
  fi

  # Period-strip: drop everything from the first '.' onward.
  local suffix="${first_line%%.*}"

  # 80-char cap, then word-boundary walk (BTS-182), then trim trailing ws.
  if (( ${#suffix} > 80 )); then
    suffix="${suffix:0:80}"
    local i ch
    for (( i=79; i >= 80 - lookback; i-- )); do
      ch="${suffix:i:1}"
      if [[ "$ch" == " " || "$ch" == $'\t' || "$ch" == "-" ]]; then
        suffix="${suffix:0:i}"
        break
      fi
    done
  fi
  suffix="${suffix%"${suffix##*[![:space:]]}"}"

  echo "feat(${feature_id_meta}): ${suffix}"
}

# ---------------------------------------------------------------------------
# cmd_archive_stasis — BTS-22: copy docs/stasis.md to
# docs/sessions/<epoch>-<feature_id>.md so cross-session stasis history
# survives without git archeology. Idempotent on byte-identical content;
# errors on collision with non-identical content.
# ---------------------------------------------------------------------------
cmd_archive_stasis() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local stasis_file="$project_dir/docs/stasis.md"
  if [[ ! -f "$stasis_file" ]]; then
    echo "ERROR: archive-stasis: docs/stasis.md not found at $stasis_file" >&2
    return 1
  fi

  local feature_id epoch
  feature_id=$(grep -m1 '^> Feature:' "$stasis_file" | sed -E 's/^> Feature:[[:space:]]*//' || true)
  if [[ -z "$feature_id" ]]; then
    echo "ERROR: archive-stasis: stasis missing > Feature: metadata" >&2
    return 1
  fi
  epoch=$(grep -m1 '^> Last updated:' "$stasis_file" | sed -E 's/^> Last updated:[[:space:]]*//' || true)
  if [[ -z "$epoch" ]]; then
    epoch=$(grep -m1 '^> Created:' "$stasis_file" | sed -E 's/^> Created:[[:space:]]*//' || true)
  fi
  if [[ -z "$epoch" ]]; then
    echo "ERROR: archive-stasis: stasis missing > Last updated: or > Created: epoch" >&2
    return 1
  fi

  local sessions_dir="$project_dir/docs/sessions"
  local rel_path="docs/sessions/${epoch}-${feature_id}.md"
  local dest="$project_dir/$rel_path"

  if [[ -f "$dest" ]]; then
    if diff -q "$stasis_file" "$dest" >/dev/null 2>&1; then
      jq -n --arg path "$rel_path" \
        '{archived: false, path: $path, reason: "already-archived"}'
      return 0
    else
      jq -n --arg path "$rel_path" \
        '{error: "collision", existing: $path}' >&2
      return 1
    fi
  fi

  mkdir -p "$sessions_dir"
  cp "$stasis_file" "$dest"
  jq -n --arg path "$rel_path" '{archived: true, path: $path}'
}

# ---------------------------------------------------------------------------
# cmd_sessions_list — BTS-22: list archived stasis files in
# docs/sessions/, sorted newest-first by epoch. Used by /recall to read
# recent N sessions without git archeology.
# ---------------------------------------------------------------------------
cmd_sessions_list() {
  local project_dir="."
  local limit=10
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      --limit)       limit="$2"; shift 2 ;;
      *)             project_dir="$1"; shift ;;
    esac
  done

  local sessions_dir="$project_dir/docs/sessions"
  if [[ ! -d "$sessions_dir" ]]; then
    echo "[]"
    return 0
  fi

  local entries="[]"
  while IFS= read -r -d '' file; do
    local fid epoch kind
    fid=$(grep -m1 '^> Feature:' "$file" | sed -E 's/^> Feature:[[:space:]]*//' || true)
    epoch=$(grep -m1 '^> Last updated:' "$file" | sed -E 's/^> Last updated:[[:space:]]*//' || true)
    if [[ -z "$epoch" ]]; then
      epoch=$(grep -m1 '^> Created:' "$file" | sed -E 's/^> Created:[[:space:]]*//' || true)
    fi
    kind=$(grep -m1 '^> Kind:' "$file" | sed -E 's/^> Kind:[[:space:]]*//' || true)

    if [[ -z "$fid" || -z "$epoch" || ! "$epoch" =~ ^[0-9]+$ ]]; then
      echo "WARN: sessions-list: skipping malformed file: $(basename "$file")" >&2
      continue
    fi

    local rel="docs/sessions/$(basename "$file")"
    entries=$(echo "$entries" | jq \
      --arg path "$rel" \
      --argjson epoch "$epoch" \
      --arg fid "$fid" \
      --arg kind "$kind" \
      '. + [{path: $path, epoch: $epoch, feature_id: $fid, kind: $kind}]')
  done < <(find "$sessions_dir" -maxdepth 1 -type f -name '*.md' -print0)

  echo "$entries" | jq --argjson limit "$limit" 'sort_by(-.epoch) | .[:$limit]'
}

# ---------------------------------------------------------------------------
# cmd_assert_pr_title — BTS-178: ensure a draft PR's live title matches the
# spec-derived expected form (`feat(<feature-id>): <first-summary-line>`).
# Force-updates via `gh pr edit` when the title is placeholder-shaped (e.g.
# `feat(auth-system)`, `feat(default)`) or missing the `feat(<feature-id>):`
# prefix. No-op when prefix already matches — trusts user edits to the
# descriptive suffix.
#
# Eliminates the BTS-175 trap where PR #99 squash-merged with subject
# `feat(auth-system): Auth feature.` because the placeholder title slipped
# past `cmd_activate`'s creation flow.
#
# Invocation:
#   assert-pr-title <pr-number> [--project-dir <dir>]
#
# Output: {updated: <bool>, expected: "<title>", actual: "<title>"}
# Exit 0 on success (updated or no-op); non-zero on missing spec, missing
# branch, or gh CLI absent.
# ---------------------------------------------------------------------------
cmd_assert_pr_title() {
  local pr_number=""
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      *)
        if [[ -z "$pr_number" ]]; then pr_number="$1"; else project_dir="$1"; fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr_number" ]]; then
    echo "ERROR: assert-pr-title requires <pr-number>" >&2
    return 2
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not available — assert-pr-title requires GitHub CLI" >&2
    return 1
  fi

  # Locate spec source: prefer active docs/spec.md; fall back to the archive
  # at docs/specs/<feature-id>.md keyed by the current branch name.
  local spec_file=""
  if [[ -f "$project_dir/docs/spec.md" ]]; then
    spec_file="$project_dir/docs/spec.md"
  else
    local branch
    branch=$(git -C "$project_dir" branch --show-current 2>/dev/null || echo "")
    # Accept claude/feat/<id>, feat/<id>, or any prefix ending in feat/<id>.
    local feature_id=""
    if [[ "$branch" =~ /feat/(.+)$ ]] || [[ "$branch" =~ ^feat/(.+)$ ]]; then
      feature_id="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$feature_id" && -f "$project_dir/docs/specs/$feature_id.md" ]]; then
      spec_file="$project_dir/docs/specs/$feature_id.md"
    else
      echo "ERROR: no spec found for branch '$branch' to derive expected title" >&2
      return 1
    fi
  fi

  # Derive expected title via the BTS-181 substrate primitive.
  local feature_id_meta expected_title
  feature_id_meta=$(grep -m1 '^> Feature:' "$spec_file" | sed -E 's/^> Feature:[[:space:]]*//')
  expected_title=$(cmd_derive_pr_title "$spec_file")

  # Read live title.
  local actual_title
  actual_title=$(gh pr view "$pr_number" --json title --jq .title 2>&1) || {
    echo "ERROR: gh pr view failed: $actual_title" >&2
    return 1
  }

  # Decision: force-update when title is placeholder-shaped OR missing the
  # feat(<feature-id>): prefix. Trust user edits to the suffix as long as
  # the prefix matches.
  local needs_update=false
  if [[ "$actual_title" =~ ^feat\(auth-system\) ]] || [[ "$actual_title" =~ ^feat\(default\) ]]; then
    needs_update=true
  elif ! [[ "$actual_title" == "feat(${feature_id_meta}):"* ]]; then
    needs_update=true
  fi

  if $needs_update; then
    gh pr edit "$pr_number" --title "$expected_title" >/dev/null
    jq -n --arg expected "$expected_title" --arg actual "$actual_title" \
      '{updated:true, expected:$expected, actual:$actual}'
  else
    jq -n --arg expected "$expected_title" --arg actual "$actual_title" \
      '{updated:false, expected:$expected, actual:$actual}'
  fi
}

# ---------------------------------------------------------------------------
# cmd_idea_pending_replay — BTS-179: replay every entry in
# .ccanvil/ideas-pending.log via the http substrate, ack on success,
# preserve on failure. Replaces the per-skill shell loop in /idea sync.
#
# Each entry is dispatched by op:
#   add               — resolve idea.add, eval $cmd --input-json - with
#                       {title, description} piped via stdin-JSON.
#                       --parent-id appended when args.parent_id present.
#   promote           — resolve ticket.transition <id> backlog,
#                       eval $cmd --priority <N>
#   defer             — resolve ticket.transition <id> icebox, eval $cmd
#   dismiss           — resolve ticket.transition <id> canceled, eval $cmd
#   merge             — resolve ticket.transition <id> duplicate,
#                       eval $cmd --duplicate-of <target>
#   ticket.transition — resolve ticket.transition <id> <role>, eval $cmd
#
# Invocation:
#   idea-pending-replay [--project-dir <dir>]
#
# Output: {synced, failed, pending, entries: [{ts, op, result, error?}]}
# Exit 0 when failed == 0; non-zero otherwise.
# ---------------------------------------------------------------------------
cmd_idea_pending_replay() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local pending="$project_dir/.ccanvil/ideas-pending.log"

  # Empty/absent log → empty summary, exit 0.
  if [[ ! -f "$pending" || ! -s "$pending" ]]; then
    jq -n '{synced: 0, failed: 0, pending: 0, entries: []}'
    return 0
  fi

  local synced=0 failed=0
  local results_file failed_file entries_file
  results_file=$(mktemp)
  failed_file=$(mktemp)
  entries_file=$(mktemp)
  trap 'rm -f "$results_file" "$failed_file" "$entries_file"' RETURN

  # Snapshot the pending log; iterate from the snapshot so per-entry ack
  # rewrites of the live log don't perturb iteration. Also avoids the
  # ts-collision class (multiple entries appended in the same second share
  # a ts, and idea-sync --ack removes all matches).
  cp "$pending" "$entries_file"

  # Iterate JSONL safely: read each line directly, no echo round-trip.
  # Use fd 3 so dispatched commands can't accidentally consume entries_file
  # via inherited stdin (e.g., a wrapper that calls `cat` would otherwise
  # drain the rest of the loop's input).
  while IFS= read -r entry <&3; do
    [[ -z "$entry" ]] && continue
    local op ts
    op=$(printf '%s' "$entry" | jq -r '.op')
    ts=$(printf '%s' "$entry" | jq -r '.ts')

    local resolution_op resolution cmd dispatch_status=0 dispatch_err=""

    case "$op" in
      add)
        resolution_op="idea.add"
        ;;
      promote)
        resolution_op="ticket.transition"
        ;;
      defer)
        resolution_op="ticket.transition"
        ;;
      dismiss)
        resolution_op="ticket.transition"
        ;;
      merge)
        resolution_op="ticket.transition"
        ;;
      ticket.transition)
        resolution_op="ticket.transition"
        ;;
      *)
        failed=$((failed + 1))
        jq -n --argjson ts "$ts" --arg op "$op" --arg err "unknown op" \
          '{ts:$ts, op:$op, result:"failed", error:$err}' >> "$results_file"
        continue
        ;;
    esac

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ "$op" == "add" ]]; then
      resolution=$(bash "$script_dir/operations.sh" resolve idea.add --project-dir "$project_dir" 2>&1) || {
        failed=$((failed + 1))
        jq -n --argjson ts "$ts" --arg op "$op" --arg err "resolve idea.add failed: $resolution" \
          '{ts:$ts, op:$op, result:"failed", error:$err}' >> "$results_file"
        continue
      }
      cmd=$(printf '%s' "$resolution" | jq -r '.invocation.command')
      local parent_id title description
      parent_id=$(printf '%s' "$entry" | jq -r '.args.parent_id // ""')
      title=$(printf '%s' "$entry" | jq -r '.args.title')
      description=$(printf '%s' "$entry" | jq -r '.args.body')
      if [[ -n "$parent_id" ]]; then
        cmd="$cmd --parent-id $(printf '%s' "$parent_id" | jq -Rr @sh)"
      fi
      dispatch_err=$(
        cd "$project_dir" && \
        jq -n --arg title "$title" --arg description "$description" \
          '{title:$title, description:$description}' \
          | eval "$cmd --input-json -" 2>&1 >/dev/null
      ) || dispatch_status=$?
    else
      local id role priority target
      id=$(printf '%s' "$entry" | jq -r '.args.id')
      case "$op" in
        promote) role="backlog" ;;
        defer)   role="icebox" ;;
        dismiss) role="canceled" ;;
        merge)   role="duplicate" ;;
        ticket.transition) role=$(printf '%s' "$entry" | jq -r '.args.role') ;;
      esac
      resolution=$(bash "$script_dir/operations.sh" resolve ticket.transition "$id" "$role" --project-dir "$project_dir" 2>&1) || {
        failed=$((failed + 1))
        jq -n --argjson ts "$ts" --arg op "$op" --arg err "resolve ticket.transition failed: $resolution" \
          '{ts:$ts, op:$op, result:"failed", error:$err}' >> "$results_file"
        continue
      }
      cmd=$(printf '%s' "$resolution" | jq -r '.invocation.command')
      if [[ "$op" == "promote" ]]; then
        priority=$(printf '%s' "$entry" | jq -r '.args.priority')
        cmd="$cmd --priority $(printf '%s' "$priority" | jq -Rr @sh)"
      elif [[ "$op" == "merge" ]]; then
        target=$(printf '%s' "$entry" | jq -r '.args.duplicateOf // .args.duplicate_of')
        cmd="$cmd --duplicate-of $(printf '%s' "$target" | jq -Rr @sh)"
      fi
      dispatch_err=$(cd "$project_dir" && eval "$cmd" </dev/null 2>&1 >/dev/null) || dispatch_status=$?
    fi

    if [[ "$dispatch_status" -eq 0 ]]; then
      synced=$((synced + 1))
      jq -n --argjson ts "$ts" --arg op "$op" '{ts:$ts, op:$op, result:"synced"}' >> "$results_file"
    else
      failed=$((failed + 1))
      printf '%s\n' "$entry" >> "$failed_file"
      jq -n --argjson ts "$ts" --arg op "$op" --arg err "$dispatch_err" \
        '{ts:$ts, op:$op, result:"failed", error:$err}' >> "$results_file"
    fi
  done 3< "$entries_file"

  # Rewrite pending log with only the failed entries (atomic mv).
  if [[ -s "$failed_file" ]]; then
    mv "$failed_file" "$pending"
  else
    : > "$pending"
    rm -f "$failed_file"
  fi

  local pending_count=0
  if [[ -f "$pending" && -s "$pending" ]]; then
    pending_count=$(jq -s 'length' "$pending")
  fi

  jq -s --argjson synced "$synced" --argjson failed "$failed" --argjson pending "$pending_count" \
    '{synced:$synced, failed:$failed, pending:$pending, entries:.}' "$results_file"

  [[ "$failed" -eq 0 ]]
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
  # BTS-132: optional --respect-allowlist <path> pre-filters raw matches
  # against a user-supplied allowlist (same ERE format as
  # hub/tests/legacy-refs-allowlist.txt). Default (no flag) returns every
  # raw match — preserves existing behavior for backward compat.
  local allowlist=""
  if [[ "${1:-}" == "--respect-allowlist" ]]; then
    allowlist="${2:-}"
    if [[ -z "$allowlist" ]]; then
      echo "ERROR: --respect-allowlist requires a path argument" >&2
      return 2
    fi
    if [[ ! -f "$allowlist" ]]; then
      echo "ERROR: allowlist file not found: $allowlist" >&2
      return 2
    fi
    shift 2
  fi

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

  # BTS-132: when --respect-allowlist was passed, filter raw_matches against
  # the allowlist. Skip comment lines (^#) and blank lines; apply remaining
  # ERE patterns via grep -vEf. Normalize leading './' on file paths first
  # since allowlist entries are repo-relative (e.g., `^hub/research/`).
  if [[ -n "$allowlist" ]]; then
    local allowlist_tmp
    allowlist_tmp=$(mktemp)
    trap 'rm -f "$allowlist_tmp"' RETURN
    grep -vE '^[[:space:]]*(#|$)' "$allowlist" > "$allowlist_tmp" || true
    if [[ -s "$allowlist_tmp" ]]; then
      raw_matches=$(echo "$raw_matches" | sed 's|^\./||' | grep -vEf "$allowlist_tmp" || true)
    fi
    if [[ -z "$raw_matches" ]]; then
      echo "[]"
      return 0
    fi
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
# cmd_stamp_spec — Replace the > Created: line in a spec with the current epoch.
#
# Usage:
#   docs-check.sh stamp-spec <feature_id> [docs-dir]
#
# Replaces an existing `> Created: <anything>` line in docs/specs/<id>.md with
# `> Created: <current epoch>`. Errors if the spec does not exist or lacks a
# Created: line — never silently inserts.
#
# Output (stdout, JSON): {"feature_id":"<id>","stamped_epoch":<n>,"file":"<path>"}
# ---------------------------------------------------------------------------
cmd_stamp_spec() {
  local feature_id="${1:-}"
  local docs_dir="${2:-docs}"

  if [[ -z "$feature_id" ]]; then
    echo "ERROR: stamp-spec requires <feature_id>" >&2
    return 2
  fi

  local spec_path="$docs_dir/specs/$feature_id.md"
  if [[ ! -f "$spec_path" ]]; then
    echo "ERROR: spec not found: $spec_path" >&2
    return 1
  fi

  if ! grep -q '^> Created:' "$spec_path"; then
    echo "ERROR: no Created: line in $spec_path — write a placeholder first" >&2
    return 1
  fi

  local epoch
  epoch=$(date +%s)

  # Replace the Created: line in place. Use a temp file for portability.
  local tmp
  tmp="${spec_path}.stamp.tmp"
  awk -v ep="$epoch" '
    /^> Created:/ && !done { print "> Created: " ep; done=1; next }
    { print }
  ' "$spec_path" > "$tmp"
  mv "$tmp" "$spec_path"

  jq -n \
    --arg fid "$feature_id" \
    --argjson ep "$epoch" \
    --arg f "$spec_path" \
    '{feature_id: $fid, stamped_epoch: $ep, file: $f}'
}

# ---------------------------------------------------------------------------
# cmd_remote_presence — Probe origin remote presence for a repo (BTS-117).
#
# Usage:
#   docs-check.sh remote-presence [repo-dir]
#
# Output (stdout, JSON): {has_origin: bool, url: string|null, git_repo: bool}
# Exit code: always 0 (callers branch on has_origin, not status).
# ---------------------------------------------------------------------------
cmd_remote_presence() {
  local repo_dir="${1:-.}"

  local git_repo="false"
  local has_origin="false"
  local url="null"

  if git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_repo="true"
    local origin_url
    if origin_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null) && [[ -n "$origin_url" ]]; then
      has_origin="true"
      url=$(printf '%s' "$origin_url" | jq -Rs .)
    fi
  fi

  if [[ "$url" == "null" ]]; then
    jq -nc \
      --argjson has "$has_origin" \
      --argjson g "$git_repo" \
      '{has_origin: $has, url: null, git_repo: $g}'
  else
    jq -nc \
      --argjson has "$has_origin" \
      --argjson u "$url" \
      --argjson g "$git_repo" \
      '{has_origin: $has, url: $u, git_repo: $g}'
  fi
}

# ---------------------------------------------------------------------------
# cmd_idea_pending_append — Safely append one entry to .ccanvil/ideas-pending.log.
#
# BTS-123: replaces the unsafe `echo '{"op":...}' >> log` pattern that broke on
# bodies with newlines/quotes/backslashes. Uses jq -nc for JSON-correct escape.
#
# Usage:
#   docs-check.sh idea-pending-append --op <op> [flags...]
#
# Per-op flag matrix:
#   add               --title <T> --body <B>
#   promote           --id <ID> --priority <N>
#   defer | dismiss   --id <ID>
#   merge             --id <ID> --duplicate-of <DID>
#   ticket.transition --id <ID> --role <ROLE>
# ---------------------------------------------------------------------------
cmd_idea_pending_append() {
  local op="" title="" body="" id="" priority="" role="" duplicate_of="" parent=""
  local project_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --op)             op="$2"; shift 2 ;;
      --title)          title="$2"; shift 2 ;;
      --body)           body="$2"; shift 2 ;;
      --id)             id="$2"; shift 2 ;;
      --priority)       priority="$2"; shift 2 ;;
      --role)           role="$2"; shift 2 ;;
      --duplicate-of)   duplicate_of="$2"; shift 2 ;;
      --parent)
        # BTS-162: validate parity with cmd_idea_add — defense in depth
        # against direct callers, even though the skill validates upstream.
        if [[ -z "$2" ]]; then
          echo "ERROR: idea-pending-append: --parent requires a non-empty value" >&2
          return 2
        fi
        if [[ "$2" =~ [[:space:]] ]]; then
          echo "ERROR: idea-pending-append: --parent value '$2' contains whitespace" >&2
          return 2
        fi
        parent="$2"; shift 2 ;;
      --project-dir)    project_dir="$2"; shift 2 ;;
      *)                echo "ERROR: unknown flag: $1" >&2; return 2 ;;
    esac
  done

  if [[ -z "$op" ]]; then
    echo "ERROR: idea-pending-append requires --op" >&2
    return 2
  fi

  local pending="$project_dir/.ccanvil/ideas-pending.log"
  mkdir -p "$(dirname "$pending")"

  local ts
  ts=$(date +%s)

  local entry
  case "$op" in
    add)
      if [[ -z "$title" ]]; then echo "ERROR: --op add requires --title" >&2; return 2; fi
      if [[ -n "$parent" ]]; then
        entry=$(jq -nc \
          --arg op "$op" --arg title "$title" --arg body "$body" \
          --arg parent "$parent" --argjson ts "$ts" \
          '{op:$op, args:{title:$title, body:$body, parent_id:$parent}, ts:$ts}')
      else
        entry=$(jq -nc \
          --arg op "$op" --arg title "$title" --arg body "$body" --argjson ts "$ts" \
          '{op:$op, args:{title:$title, body:$body}, ts:$ts}')
      fi
      ;;
    promote)
      if [[ -z "$id" || -z "$priority" ]]; then
        echo "ERROR: --op promote requires --id and --priority" >&2; return 2
      fi
      entry=$(jq -nc \
        --arg op "$op" --arg id "$id" --argjson priority "$priority" --argjson ts "$ts" \
        '{op:$op, args:{id:$id, priority:$priority}, ts:$ts}')
      ;;
    defer|dismiss)
      if [[ -z "$id" ]]; then echo "ERROR: --op $op requires --id" >&2; return 2; fi
      entry=$(jq -nc \
        --arg op "$op" --arg id "$id" --argjson ts "$ts" \
        '{op:$op, args:{id:$id}, ts:$ts}')
      ;;
    merge)
      if [[ -z "$id" || -z "$duplicate_of" ]]; then
        echo "ERROR: --op merge requires --id and --duplicate-of" >&2; return 2
      fi
      entry=$(jq -nc \
        --arg op "$op" --arg id "$id" --arg dup "$duplicate_of" --argjson ts "$ts" \
        '{op:$op, args:{id:$id, duplicateOf:$dup}, ts:$ts}')
      ;;
    ticket.transition)
      if [[ -z "$id" || -z "$role" ]]; then
        echo "ERROR: --op ticket.transition requires --id and --role" >&2; return 2
      fi
      entry=$(jq -nc \
        --arg op "$op" --arg id "$id" --arg role "$role" --argjson ts "$ts" \
        '{op:$op, args:{id:$id, role:$role}, ts:$ts}')
      ;;
    *)
      echo "ERROR: unknown op: $op (expected: add|promote|defer|dismiss|merge|ticket.transition)" >&2
      return 2
      ;;
  esac

  printf '%s\n' "$entry" >> "$pending"
}

# ---------------------------------------------------------------------------
# cmd_idea_pending_validate — Validate every line in .ccanvil/ideas-pending.log.
#
# Output (stdout, JSON): {count: N, valid: bool, errors: [<line-num>...]}
# Exit codes: 0 when valid (or empty/missing), non-zero when any line fails to parse.
# ---------------------------------------------------------------------------
cmd_idea_pending_validate() {
  local project_dir="${1:-.}"
  local pending="$project_dir/.ccanvil/ideas-pending.log"

  if [[ ! -f "$pending" ]]; then
    jq -n '{count: 0, valid: true, errors: []}'
    return 0
  fi

  local count=0
  local errors_json="[]"
  local lineno=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    [[ -z "$line" ]] && continue
    if echo "$line" | jq -e . >/dev/null 2>&1; then
      count=$((count + 1))
    else
      errors_json=$(echo "$errors_json" | jq --argjson n "$lineno" '. + [$n]')
    fi
  done < "$pending"

  local valid="true"
  if [[ "$(echo "$errors_json" | jq 'length')" -gt 0 ]]; then
    valid="false"
  fi

  jq -n \
    --argjson count "$count" \
    --argjson valid "$valid" \
    --argjson errors "$errors_json" \
    '{count: $count, valid: $valid, errors: $errors}'

  if [[ "$valid" == "false" ]]; then
    return 1
  fi
}

# BTS-201: scan session captures for bug-shape ideas missing evidence anchors.
# Returns JSON {evidence_gaps: [{id, title, reason}], scanned: N, fallback?:"24h"}.
# Inputs:
#   --since <commit>      — git commit; floor for createdAt filter (epoch via git log -1)
#   --project-dir <path>  — defaults to "."
#   --input-json <file>   — bypass live idea.list resolver; read canned issues array
#   --no-time-filter      — skip createdAt filter (test mode)
cmd_evidence_scan_session() {
  local since="" project_dir="." input_json="" no_time_filter=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --input-json) input_json="${2:-}"; shift 2 ;;
      --no-time-filter) no_time_filter=1; shift ;;
      *) shift ;;
    esac
  done

  # Determine since-epoch (or 24h fallback)
  local since_epoch="" fallback=""
  if [[ -n "$since" ]]; then
    since_epoch=$(git -C "$project_dir" log -1 --format=%ct "$since" 2>/dev/null || true)
  fi
  if [[ -z "$since_epoch" ]]; then
    since_epoch=$(( $(date +%s) - 86400 ))
    [[ -n "$since" ]] && fallback="24h"
    # Empty --since with no resolution also implies fallback at first-stasis
    # nodes; we mark fallback only when the operator explicitly passed an
    # unresolvable --since to keep the signal informative.
  fi

  # Load issues (canned for tests, resolved live otherwise)
  local issues
  if [[ -n "$input_json" ]]; then
    [[ ! -f "$input_json" ]] && {
      echo "ERROR: evidence-scan-session: --input-json file not found: $input_json" >&2
      return 3
    }
    issues=$(cat "$input_json")
  else
    local ops="$(dirname "$0")/operations.sh"
    local resolution
    resolution=$(bash "$ops" resolve idea.list --project-dir "$project_dir" 2>/dev/null) || {
      echo "ERROR: evidence-scan-session: idea.list resolution failed" >&2
      return 3
    }
    local cmd_str
    cmd_str=$(printf '%s' "$resolution" | jq -r '.invocation.command')
    issues=$(eval "$cmd_str") || {
      echo "ERROR: evidence-scan-session: list invocation failed" >&2
      return 3
    }
  fi

  # Validate JSON shape
  if ! echo "$issues" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: evidence-scan-session: invalid JSON from idea.list (expected array)" >&2
    return 3
  fi

  # Bug-shape heuristic — must match the regex documented in
  # .claude/rules/evidence-required-for-captures.md and /idea SKILL.md.
  local bug_re='fail|false[- ]positive|broken|errored?|blocked by|doesn'\''?t work|crashes?|hang(s|ing)?'

  local gaps='[]'
  local scanned=0

  while IFS= read -r issue; do
    [[ -z "$issue" ]] && continue

    local id title body created_at
    id=$(echo "$issue" | jq -r '.id // empty')
    title=$(echo "$issue" | jq -r '.title // empty')
    body=$(echo "$issue" | jq -r '.description // empty')
    created_at=$(echo "$issue" | jq -r '.createdAt // empty')

    # Time filter (skip in test mode)
    if (( ! no_time_filter )) && [[ -n "$created_at" ]]; then
      local created_epoch
      # ISO8601 → epoch; date(1) on macOS uses -j -f, GNU uses -d. Try both.
      created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created_at%%.*}" "+%s" 2>/dev/null \
        || date -d "${created_at%%.*}" "+%s" 2>/dev/null \
        || echo 0)
      [[ "$created_epoch" -le "$since_epoch" ]] && continue
    fi

    scanned=$((scanned + 1))

    # DIAGNOSE: titles are exempt from evidence requirement
    [[ "$title" =~ ^DIAGNOSE: ]] && continue

    # Bug-shape match against title (case-insensitive)
    if ! echo "$title" | grep -qiE "$bug_re"; then
      continue
    fi

    # Bug-shape detected → check for all four anchors line-leading
    local missing=0
    for anchor in 'Command:' 'Output:' 'Exit:' 'Reproduce:'; do
      if ! echo "$body" | grep -qE "^$anchor"; then
        missing=1
        break
      fi
    done

    if (( missing )); then
      gaps=$(echo "$gaps" | jq --arg id "$id" --arg t "$title" \
        '. + [{id:$id, title:$t, reason:"missing-evidence-anchors"}]')
    fi
  done < <(echo "$issues" | jq -c '.[]')

  if [[ -n "$fallback" ]]; then
    jq -n --argjson gaps "$gaps" --argjson scanned "$scanned" --arg fb "$fallback" \
      '{evidence_gaps:$gaps, scanned:$scanned, fallback:$fb}'
  else
    jq -n --argjson gaps "$gaps" --argjson scanned "$scanned" \
      '{evidence_gaps:$gaps, scanned:$scanned}'
  fi
}

# ---------------------------------------------------------------------------
# cmd_lifecycle_state (BTS-20) — Unified state envelope.
#
# Composes cmd_validate + git/marker state into a structured envelope:
#   {state, legal_next_actions:[{action, command, reason}], blockers:[], suggestions:[]}
#
# .ccanvil/templates/lifecycle-graph.json codifies the state machine as data
# (consumed by tests for schema validation; structural reference for future
# Session-2/3 work). Session-1 does not parse the graph file at runtime —
# legal_next_actions are hand-derived in the case statement below. This trade
# is intentional: the graph is the contract, the code is the implementation.
# pr-open / pr-merged states exist in the graph but are not emitted yet
# (deferred to Session-2 — would require a gh subprocess for detection).
# ---------------------------------------------------------------------------
# BTS-204 Step 8: storage-abstraction helpers for lifecycle-state.
# When routing.<kind> is "linear", artifact presence is determined by
# Linear (Document existence at the deterministic uuid5), not filesystem.

# _lifecycle_route — read integrations.routing.<kind> from merged config.
# Returns "linear" or "local". Defaults to "local" when key absent.
_lifecycle_route() {
  local kind="$1" project_dir="${2:-.}"
  local hub_file="$project_dir/.claude/ccanvil.json"
  local local_file="$project_dir/.claude/ccanvil.local.json"
  local route="local"
  for f in "$hub_file" "$local_file"; do
    if [[ -f "$f" ]]; then
      local r
      r=$(jq -r --arg k "$kind" '.integrations.routing[$k] // empty' "$f" 2>/dev/null)
      [[ -n "$r" ]] && route="$r"
    fi
  done
  echo "$route"
}

# _has_any_linear_route — quick fast-path check. Returns "true" iff at least
# one of spec/plan/stasis routes to linear in the merged config. Used to
# skip ALL Linear querying on pure-local nodes (preserves existing behavior
# byte-for-byte; no network calls, no auth probing, no env-var sniffing).
_has_any_linear_route() {
  local project_dir="${1:-.}"
  local kind
  for kind in spec plan stasis; do
    if [[ "$(_lifecycle_route "$kind" "$project_dir")" == "linear" ]]; then
      echo "true"
      return 0
    fi
  done
  echo "false"
}

# _active_feature_id — derive the active feature id (e.g., "BTS-204") from
# context. Order of precedence:
#   1. LIFECYCLE_FEATURE_ID_OVERRIDE env var (test-only path)
#   2. docs/spec.md `> Work:` metadata (when present, e.g., legacy mid-migration)
#   3. git branch name (claude/<type>/bts-204-foo → BTS-204)
# Returns empty string when none resolves.
_active_feature_id() {
  local project_dir="${1:-.}"
  if [[ -n "${LIFECYCLE_FEATURE_ID_OVERRIDE:-}" ]]; then
    echo "$LIFECYCLE_FEATURE_ID_OVERRIDE"
    return 0
  fi
  if [[ -f "$project_dir/docs/spec.md" ]]; then
    # Strip "> Work: " prefix, then strip an explicit provider prefix like
    # "linear:" or "local:". Ticket IDs themselves are uppercase (e.g.,
    # BTS-204), so they cannot match `^[a-z]+:` and remain untouched.
    local work
    work=$(grep -E '^> Work:' "$project_dir/docs/spec.md" 2>/dev/null | head -1 | sed -E 's/^> Work:[[:space:]]*//; s/^[a-z]+://')
    if [[ -n "$work" ]]; then
      echo "$work"
      return 0
    fi
  fi
  local branch
  branch=$(git -C "$project_dir" branch --show-current 2>/dev/null) || true
  if [[ "$branch" == claude/*/* ]]; then
    local fid="${branch##*/}"
    if [[ "$fid" =~ ^([a-zA-Z]+-[0-9]+) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
      return 0
    fi
  fi
  echo ""
}

# _artifact_present_linear — query Linear via document-updated-at to determine
# if the lifecycle Document for <kind, feature_id> exists. Returns "true" or
# "false". Network errors, missing API key, or stub-down all map to "false"
# so the lifecycle stays usable in degraded conditions (Linear-unreachable
# is reported by other paths — this helper just answers presence).
_artifact_present_linear() {
  local kind="$1" feature_id="$2"
  local resolve_kind
  case "$kind" in
    spec)   resolve_kind="spec" ;;
    plan)   resolve_kind="plan" ;;
    stasis) resolve_kind="feature-stasis" ;;
    *)      echo "false"; return 0 ;;
  esac
  local script_dir doc_id
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  doc_id=$(bash "$script_dir/linear-query.sh" resolve-document-id --kind "$resolve_kind" --ticket "$feature_id" 2>/dev/null)
  if [[ -z "$doc_id" ]]; then
    echo "false"; return 0
  fi
  if bash "$script_dir/linear-query.sh" document-updated-at "$doc_id" >/dev/null 2>&1; then
    echo "true"
  else
    echo "false"
  fi
}

# BTS-204 Step 14: archive Linear-stored lifecycle artifacts to docs/sessions/
# at /complete time, then trash the Linear Documents. Forward-only history.
_complete_archive_linear() {
  local feature_id="$1" project_dir="${2:-.}"
  local script_dir epoch sessions_dir
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  epoch=$(date +%s)
  sessions_dir="$project_dir/docs/sessions"
  mkdir -p "$sessions_dir"

  local kind
  for kind in spec plan stasis; do
    local route
    route=$(_lifecycle_route "$kind" "$project_dir")
    [[ "$route" != "linear" ]] && continue

    local resolve_kind ticket
    case "$kind" in
      spec)   resolve_kind="spec";          ticket="$feature_id" ;;
      plan)   resolve_kind="plan";          ticket="$feature_id" ;;
      stasis) resolve_kind="feature-stasis"; ticket="$feature_id" ;;
    esac
    local doc_id content
    doc_id=$(bash "$script_dir/linear-query.sh" resolve-document-id --kind "$resolve_kind" --ticket "$ticket")
    content=$(bash "$script_dir/linear-query.sh" get-document "$doc_id" 2>/dev/null | jq -r '.content // empty')
    if [[ -n "$content" ]]; then
      local dest="$sessions_dir/${epoch}-${feature_id}-${kind}.md"
      printf '%s\n' "$content" > "$dest"
      bash "$script_dir/linear-query.sh" trash-document "$doc_id" >/dev/null 2>&1 || true
      echo "Archived ${kind} → $dest" >&2
    fi
  done
}

# BTS-204 Phase 7: document-cache for concurrent-edit safety.
# Stores {<doc_id>: {updatedAt}} at .ccanvil/state/document-cache.json.
# Atomic writes via mktemp+mv. Cache file is gitignored (regenerable state).
_doc_cache_path() {
  echo "${1:-.}/.ccanvil/state/document-cache.json"
}

_doc_cache_get_updated_at() {
  local doc_id="$1" project_dir="${2:-.}"
  local cache_path
  cache_path=$(_doc_cache_path "$project_dir")
  [[ -f "$cache_path" ]] || { echo ""; return 0; }
  jq -r --arg id "$doc_id" '.[$id].updatedAt // empty' "$cache_path" 2>/dev/null
}

_doc_cache_set_updated_at() {
  local doc_id="$1" updated_at="$2" project_dir="${3:-.}"
  local cache_path tmp
  cache_path=$(_doc_cache_path "$project_dir")
  mkdir -p "$(dirname "$cache_path")"
  tmp=$(mktemp "${cache_path}.XXXXXX")
  if [[ -f "$cache_path" ]]; then
    jq --arg id "$doc_id" --arg ts "$updated_at" \
      '.[$id] = {updatedAt: $ts}' "$cache_path" > "$tmp"
  else
    jq -n --arg id "$doc_id" --arg ts "$updated_at" \
      '{($id): {updatedAt: $ts}}' > "$tmp"
  fi
  mv "$tmp" "$cache_path"
}

# Returns 0 if write is safe (cache absent OR remote updatedAt matches cache).
# Returns 1 if remote updatedAt has advanced past cache (concurrent edit detected).
_doc_concurrent_edit_check() {
  local doc_id="$1" project_dir="${2:-.}"
  local script_dir cached remote
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  cached=$(_doc_cache_get_updated_at "$doc_id" "$project_dir")
  [[ -z "$cached" ]] && return 0   # No cache yet — first write; safe.
  remote=$(bash "$script_dir/linear-query.sh" document-updated-at "$doc_id" 2>/dev/null | jq -r '.updatedAt // empty')
  [[ -z "$remote" ]] && return 0   # Document missing remote (will create); safe.
  if [[ "$remote" != "$cached" ]]; then
    return 1
  fi
  return 0
}

# BTS-204 Phase 6: ssot-migrate — operator-driven, idempotent migration of
# lifecycle artifacts between local files and Linear Documents. Bidirectional.
# Never auto-triggered. Per AC-12.
cmd_ssot_migrate() {
  local direction="" feature=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to)       direction="$2"; shift 2 ;;
      --feature)  feature="$2";   shift 2 ;;
      *) shift ;;
    esac
  done
  case "$direction" in
    linear|local) ;;
    *) echo "ERROR: ssot-migrate requires --to {linear|local}" >&2; return 2 ;;
  esac
  if [[ -z "$feature" ]]; then
    echo "ERROR: ssot-migrate requires --feature <BTS-N> (or feature-id)" >&2
    return 2
  fi

  local project_dir="."
  local migrated=0 skipped=0 errors=0
  local kind

  if [[ "$direction" == "linear" ]]; then
    # Local → Linear: for each artifact whose route is linear, read the
    # local file, write it via artifact-write (which upserts to Linear),
    # then remove the local file on success.
    for kind in spec plan stasis; do
      [[ "$(_lifecycle_route "$kind" "$project_dir")" != "linear" ]] && continue
      local local_path
      case "$kind" in
        spec)   local_path="$project_dir/docs/spec.md" ;;
        plan)   local_path="$project_dir/docs/plan.md" ;;
        stasis) local_path="$project_dir/docs/stasis.md" ;;
      esac
      if [[ ! -f "$local_path" ]]; then
        skipped=$((skipped + 1))
        continue
      fi
      if cmd_artifact_write --kind "$kind" --feature "$feature" < "$local_path" >/dev/null 2>&1; then
        rm -f "$local_path"
        migrated=$((migrated + 1))
      else
        errors=$((errors + 1))
      fi
    done
  else
    # Linear → local: read from Linear via artifact-read, materialize files.
    # Linear Documents are NOT trashed (operator may want to flip back).
    for kind in spec plan stasis; do
      [[ "$(_lifecycle_route "$kind" "$project_dir")" != "linear" ]] && continue
      local content target
      case "$kind" in
        spec)   target="$project_dir/docs/spec.md" ;;
        plan)   target="$project_dir/docs/plan.md" ;;
        stasis) target="$project_dir/docs/stasis.md" ;;
      esac
      content=$(cmd_artifact_read --kind "$kind" --feature "$feature" 2>/dev/null) || { skipped=$((skipped + 1)); continue; }
      if [[ -z "$content" ]]; then
        skipped=$((skipped + 1))
        continue
      fi
      printf '%s' "$content" > "$target"
      migrated=$((migrated + 1))
    done
  fi

  jq -n --arg dir "$direction" --argjson m "$migrated" --argjson s "$skipped" --argjson e "$errors" \
    '{direction:$dir, migrated:$m, skipped:$s, errors:$e}'
}

# BTS-204 Phase 4: provider-aware artifact read/write compound primitives.
# Skills call these instead of hardcoded file IO. Routing decision +
# upsert orchestration live in one place; skill prose stays terse.

# cmd_route_of — public wrapper over `_lifecycle_route`. Exposes the routing
# decision so skill prose (e.g. /spec) can branch on `linear` vs `local`
# without reaching into private helpers. BTS-213.
# Usage:
#   docs-check.sh route-of <spec|plan|stasis> [--project-dir <dir>]
# Outputs "linear" or "local" on stdout. Exit 2 on missing/unknown kind.
cmd_route_of() {
  local kind="" project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      spec|plan|stasis) kind="$1"; shift ;;
      *) shift ;;
    esac
  done
  if [[ -z "$kind" ]]; then
    echo "Usage: route-of <spec|plan|stasis> [--project-dir <dir>]" >&2
    return 2
  fi
  _lifecycle_route "$kind" "$project_dir"
}

# cmd_artifact_read — read spec/plan/stasis content from the routed source.
# Args:
#   --kind <spec|plan|stasis>
#   --feature <BTS-N>           required when http-routed (or --stasis-kind feature)
#   --stasis-kind <feature|session>  defaults to "feature"
# Output: artifact content on stdout (markdown). Exit 0 on found, 2 on missing.
cmd_artifact_read() {
  local kind="" feature="" stasis_kind="feature"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind)         kind="$2";        shift 2 ;;
      --feature)      feature="$2";     shift 2 ;;
      --stasis-kind)  stasis_kind="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -z "$kind" ]] && { echo "ERROR: artifact-read --kind is required" >&2; return 2; }

  local route project_dir="."
  route=$(_lifecycle_route "$kind" "$project_dir")

  if [[ "$route" != "linear" ]]; then
    local target
    case "$kind" in
      spec)   target="docs/spec.md" ;;
      plan)   target="docs/plan.md" ;;
      stasis) target="docs/stasis.md" ;;
      *) echo "ERROR: artifact-read unknown kind '$kind'" >&2; return 2 ;;
    esac
    [[ ! -f "$target" ]] && return 2
    cat "$target"
    return 0
  fi

  # Linear route. Need feature_id (or project context for session-stasis).
  local script_dir resolve_kind ticket
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  case "$kind" in
    spec)   resolve_kind="spec";   ticket="$feature" ;;
    plan)   resolve_kind="plan";   ticket="$feature" ;;
    stasis)
      if [[ "$stasis_kind" == "session" ]]; then
        resolve_kind="session-stasis"
        ticket=$(_session_stasis_ticket "$project_dir")
      else
        resolve_kind="feature-stasis"
        ticket="$feature"
      fi
      ;;
  esac
  [[ -z "$ticket" ]] && { echo "ERROR: artifact-read $kind requires a ticket (use --feature)" >&2; return 2; }

  local doc_id
  doc_id=$(bash "$script_dir/linear-query.sh" resolve-document-id --kind "$resolve_kind" --ticket "$ticket")
  # W-2 fix: surface GraphQL errors instead of swallowing them. Skills calling
  # artifact-read need to distinguish "not found" (route legitimately empty)
  # from "auth/network failure" (substrate problem).
  local err
  err=$(mktemp); local content rc
  content=$(bash "$script_dir/linear-query.sh" get-document "$doc_id" 2>"$err"); rc=$?
  if [[ $rc -ne 0 ]]; then
    cat "$err" >&2
    rm -f "$err"
    # Distinguish not-found from real errors. linear-query.sh emits "Entity not
    # found: Document" for missing; everything else is a substrate problem.
    if grep -q "Entity not found" "$err" 2>/dev/null || grep -q "Entity not found" <<<"$err"; then
      return 2
    fi
    return 3
  fi
  rm -f "$err"
  printf '%s\n' "$content" | jq -r '.content // empty'
}

# cmd_artifact_write — write artifact content to the routed destination.
# Reads content from stdin. For Linear, performs upsert via document-updated-at
# pre-check, then save-document with --create-with-id on first write.
cmd_artifact_write() {
  local kind="" feature="" stasis_kind="feature"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind)         kind="$2";        shift 2 ;;
      --feature)      feature="$2";     shift 2 ;;
      --stasis-kind)  stasis_kind="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -z "$kind" ]] && { echo "ERROR: artifact-write --kind is required" >&2; return 2; }

  local content project_dir="."
  content=$(cat)

  local route
  route=$(_lifecycle_route "$kind" "$project_dir")

  if [[ "$route" != "linear" ]]; then
    local target
    case "$kind" in
      spec)   target="docs/spec.md" ;;
      plan)   target="docs/plan.md" ;;
      stasis) target="docs/stasis.md" ;;
      *) echo "ERROR: artifact-write unknown kind '$kind'" >&2; return 2 ;;
    esac
    printf '%s' "$content" > "$target"
    return 0
  fi

  # Linear route — upsert.
  local script_dir resolve_kind ticket parent_field parent_value title
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  case "$kind" in
    spec)   resolve_kind="spec";   ticket="$feature"; title="Spec: $feature";   parent_field="issueId" ;;
    plan)   resolve_kind="plan";   ticket="$feature"; title="Plan: $feature";   parent_field="issueId" ;;
    stasis)
      if [[ "$stasis_kind" == "session" ]]; then
        resolve_kind="session-stasis"
        ticket=$(_session_stasis_ticket "$project_dir")
        title="Session State"
        parent_field="projectId"
      else
        resolve_kind="feature-stasis"
        ticket="$feature"
        title="Stasis: $feature"
        parent_field="issueId"
      fi
      ;;
  esac
  [[ -z "$ticket" ]] && { echo "ERROR: artifact-write $kind requires --feature" >&2; return 2; }

  if [[ "$parent_field" == "issueId" ]]; then
    parent_value=$(bash "$script_dir/linear-query.sh" get-issue "$feature" 2>/dev/null | jq -r '.uuid // empty')
    [[ -z "$parent_value" ]] && { echo "ERROR: artifact-write could not resolve issue UUID for $feature" >&2; return 3; }
  else
    parent_value=$(_session_stasis_ticket "$project_dir")
    [[ -z "$parent_value" ]] && { echo "ERROR: artifact-write project_id missing in provider config" >&2; return 3; }
  fi

  local doc_id
  doc_id=$(bash "$script_dir/linear-query.sh" resolve-document-id --kind "$resolve_kind" --ticket "$ticket")

  # BTS-204 Step 19: pre-write concurrent-edit check (AC-8).
  # If the cache has a known updatedAt and Linear's current updatedAt has
  # advanced past it, refuse the write — surface document-history hint.
  # When ALLOW_CONCURRENT_EDIT_OVERRIDE=1, skip the check (operator escape).
  if [[ "${ALLOW_CONCURRENT_EDIT_OVERRIDE:-0}" != "1" ]]; then
    if ! _doc_concurrent_edit_check "$doc_id" "$project_dir"; then
      cat >&2 <<EOF
ERROR: concurrent edit detected on Linear Document $doc_id.
The remote updatedAt has advanced past the cached value.
Run: bash .ccanvil/scripts/linear-query.sh document-history $doc_id
to see what changed. Set ALLOW_CONCURRENT_EDIT_OVERRIDE=1 to force-write.

NOTE: this check is not atomic with the write — sub-second races still
exist. Override only when you've reviewed the divergence and the remote
edit is acceptable to discard. Multi-agent atomicity is out of scope.
EOF
      return 4
    fi
  fi

  local result
  if bash "$script_dir/linear-query.sh" document-updated-at "$doc_id" >/dev/null 2>&1; then
    # Update path
    result=$(jq -n --arg id "$doc_id" --arg content "$content" '{id:$id, content:$content}' \
      | bash "$script_dir/linear-query.sh" save-document --input-json -) || return $?
  else
    # Create path with caller-supplied UUID
    result=$(jq -n --arg id "$doc_id" --arg title "$title" --arg content "$content" \
      --arg parent_field "$parent_field" --arg parent "$parent_value" \
      '{id:$id, title:$title, content:$content} + ({} + (if $parent_field == "issueId" then {issueId:$parent} else {projectId:$parent} end))' \
      | bash "$script_dir/linear-query.sh" save-document --create-with-id --input-json -) || return $?
  fi
  echo "$result"
  # Cache the new updatedAt for next concurrent-edit check.
  local new_ts
  new_ts=$(printf '%s' "$result" | jq -r '.updatedAt // empty')
  if [[ -n "$new_ts" ]]; then
    _doc_cache_set_updated_at "$doc_id" "$new_ts" "$project_dir"
  fi
}

# _session_stasis_ticket — read project_id from merged config; used as the
# deterministic "ticket" key for session-stasis Document UUID derivation.
_session_stasis_ticket() {
  local project_dir="${1:-.}"
  local hub_file="$project_dir/.claude/ccanvil.json"
  local local_file="$project_dir/.claude/ccanvil.local.json"
  for f in "$hub_file" "$local_file"; do
    if [[ -f "$f" ]]; then
      local pid
      pid=$(jq -r '.integrations.providers.linear.project_id // empty' "$f" 2>/dev/null)
      [[ -n "$pid" ]] && { echo "$pid"; return 0; }
    fi
  done
  echo ""
}

cmd_lifecycle_state() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      *) shift ;;
    esac
  done

  # AC-9: uninitialized — not a ccanvil project (no .ccanvil/ root).
  # Requiring .git/ is too strict — recommend test fixtures and bare project
  # roots may not initialize git. The .ccanvil/ presence is the canonical
  # ccanvil marker; AC-9 fixtures use /tmp paths with neither.
  if [[ ! -d "$project_dir/.ccanvil" ]]; then
    jq -n --arg err "not a ccanvil project (.ccanvil/ missing)" \
      '{state:"uninitialized", legal_next_actions:[], blockers:[], suggestions:[], error:$err}'
    return 2
  fi

  local docs_dir="$project_dir/docs"
  local validate_json
  validate_json=$(cmd_validate "$docs_dir")

  local result spec_exists plan_exists stasis_exists stasis_kind
  result=$(echo "$validate_json" | jq -r '.result')
  spec_exists=$(echo "$validate_json" | jq -r '.status.spec.exists')
  plan_exists=$(echo "$validate_json" | jq -r '.status.plan.exists')
  stasis_exists=$(echo "$validate_json" | jq -r '.status.stasis.exists')
  stasis_kind=$(echo "$validate_json" | jq -r '.status.stasis.kind // empty')

  # BTS-204 Step 8: when any lifecycle artifact is routed to Linear, override
  # the filesystem-based exists flags using Linear-side presence checks. The
  # fast-path skips this entirely on pure-local nodes (zero network cost).
  if [[ "$(_has_any_linear_route "$project_dir")" == "true" ]]; then
    local feat
    feat=$(_active_feature_id "$project_dir")
    if [[ -n "$feat" ]]; then
      local kind
      for kind in spec plan stasis; do
        if [[ "$(_lifecycle_route "$kind" "$project_dir")" == "linear" ]]; then
          local present
          present=$(_artifact_present_linear "$kind" "$feat")
          case "$kind" in
            spec)   spec_exists="$present"   ;;
            plan)   plan_exists="$present"   ;;
            stasis) stasis_exists="$present" ;;
          esac
        fi
      done
    fi
  fi

  # post-compact freshness: marker_ts >= stasis.last_updated means compact
  # has run at or after the current stasis was written. Mirrors the marker
  # check in cmd_recommend (BTS-113).
  local stasis_ts marker_ts marker_path
  stasis_ts=$(echo "$validate_json" | jq -r '.status.stasis.last_updated // empty')
  marker_path="$project_dir/.ccanvil/state/last-compact-ts"
  marker_ts=""
  if [[ -f "$marker_path" ]]; then
    marker_ts=$(tr -d '[:space:]' < "$marker_path" 2>/dev/null || echo "")
  fi
  local compact_fresh=false
  if [[ -n "$marker_ts" && "$marker_ts" =~ ^[0-9]+$ \
        && -n "$stasis_ts" && "$stasis_ts" =~ ^[0-9]+$ \
        && "$marker_ts" -ge "$stasis_ts" ]]; then
    compact_fresh=true
  fi

  # Derive state.
  local state="no-active-spec"
  local blockers='[]'

  case "$result" in
    mismatched|stale-plan|stale-stasis|unlinked|missing-determinism-review)
      state="blocked"
      blockers=$(echo "$validate_json" | jq -c '.details')
      ;;
    *)
      if [[ "$spec_exists" == "true" && "$plan_exists" != "true" ]]; then
        state="spec-activated"
      elif [[ "$spec_exists" == "true" && "$plan_exists" == "true" ]]; then
        if [[ "$stasis_exists" == "true" && "$stasis_kind" != "session" ]]; then
          state="implementing"
        else
          state="plan-written"
        fi
      elif [[ "$stasis_exists" == "true" && "$stasis_kind" == "session" ]]; then
        state="session-wrap"
      else
        state="no-active-spec"
      fi
      ;;
  esac

  # Derive legal_next_actions for the current state. Structural edges live
  # in lifecycle-graph.json; contextual filtering happens here.
  local actions='[]'
  case "$state" in
    no-active-spec)
      actions=$(jq -n '[
        {action:"/radar", command:"/radar", reason:"orient before next feature"},
        {action:"/idea triage", command:"/idea triage", reason:"clear triage queue first"},
        {action:"/spec", command:"/spec <work-ref> <description>", reason:"start a new feature"},
        {action:"activate", command:"bash .ccanvil/scripts/docs-check.sh activate <feature-id>", reason:"activate a Ready spec from docs/specs/"}
      ]')
      ;;
    spec-activated)
      actions=$(jq -n '[
        {action:"/plan", command:"/plan", reason:"draft implementation plan from active spec"}
      ]')
      ;;
    plan-written)
      actions=$(jq -n '[
        {action:"implement", command:"TDD red → green → refactor → commit", reason:"execute plan steps"},
        {action:"/pr", command:"/pr", reason:"finalize and mark PR ready"},
        {action:"/stasis", command:"/stasis", reason:"snapshot session progress before context reset"}
      ]')
      ;;
    implementing)
      # Feature-kind stasis present → session boundary mid-feature.
      # When marker is fresh (compact already ran) prefer forward action;
      # otherwise /compact is the next move (matches cmd_recommend's BTS-113
      # forward-momentum logic).
      if $compact_fresh; then
        actions=$(jq -n '[
          {action:"/radar", command:"/radar", reason:"orient on next feature (compact already ran)"},
          {action:"implement", command:"TDD red → green → refactor → commit", reason:"continue plan steps"},
          {action:"/pr", command:"/pr", reason:"finalize and mark PR ready"}
        ]')
      else
        actions=$(jq -n '[
          {action:"/compact", command:"/compact", reason:"all docs aligned with stasis — preserve context, then start the next feature"},
          {action:"/pr", command:"/pr", reason:"finalize and mark PR ready"},
          {action:"implement", command:"TDD red → green → refactor → commit", reason:"continue plan steps"}
        ]')
      fi
      ;;
    session-wrap)
      if $compact_fresh; then
        actions=$(jq -n '[
          {action:"/radar", command:"/radar", reason:"orient on next feature (compact already ran)"},
          {action:"activate", command:"bash .ccanvil/scripts/docs-check.sh activate <feature-id>", reason:"start the next feature"},
          {action:"/idea triage", command:"/idea triage", reason:"clear triage queue if non-empty"}
        ]')
      else
        actions=$(jq -n '[
          {action:"/compact", command:"/compact", reason:"clear context after stasis"}
        ]')
      fi
      ;;
    blocked)
      actions=$(jq -n --argjson b "$blockers" '[
        {action:"recover", command:"address validate.details", reason:($b | join("; "))}
      ]')
      ;;
  esac

  # Carry the underlying validate.result so consumers like cmd_recommend
  # can map blocked → specific recovery message without re-running validate.
  jq -n \
    --arg state "$state" \
    --arg validate_result "$result" \
    --argjson actions "$actions" \
    --argjson blockers "$blockers" \
    '{state:$state, validate_result:$validate_result, legal_next_actions:$actions, blockers:$blockers, suggestions:[]}'
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
  pr-cleanup)        cmd_pr_cleanup "$@" ;;
  detect-repo-type)  cmd_detect_repo_type "$@" ;;
  land)              cmd_land "$@" ;;
  land-recover-branch) cmd_land_recover_branch "$@" ;;
  extract-work)      cmd_extract_work "$@" ;;
  auto-close-emit)   cmd_auto_close_emit "$@" ;;
  auto-transition-emit) cmd_auto_transition_emit "$@" ;;
  sync-check)        cmd_sync_check "$@" ;;
  pr-guard)          cmd_pr_guard "$@" ;;
  radar-gather)      cmd_radar_gather "$@" ;;
  idea-add)          cmd_idea_add "$@" ;;
  idea-list)         cmd_idea_list "$@" ;;
  idea-count)        cmd_idea_count "$@" ;;
  idea-count-local)  cmd_idea_count_local "$@" ;;
  idea-update)       cmd_idea_update "$@" ;;
  idea-sync)         cmd_idea_sync "$@" ;;
  idea-pending-replay) cmd_idea_pending_replay "$@" ;;
  refresh-plan-hash) cmd_refresh_plan_hash "$@" ;;
  assert-pr-title)   cmd_assert_pr_title "$@" ;;
  derive-pr-title)   cmd_derive_pr_title "$@" ;;
  archive-stasis)    cmd_archive_stasis "$@" ;;
  sessions-list)     cmd_sessions_list "$@" ;;
  idea-review-icebox) cmd_idea_review_icebox "$@" ;;
  idea-migrate-state) cmd_idea_migrate_state "$@" ;;
  idea-migrate)      cmd_idea_migrate "$@" ;;
  idea-setup)        cmd_idea_setup "$@" ;;
  idea-upgrade)      cmd_idea_upgrade "$@" ;;
  title-from-body)   cmd_title_from_body "$@" ;;
  legacy-refs-scan)  cmd_legacy_refs_scan "$@" ;;
  stamp-spec)        cmd_stamp_spec "$@" ;;
  idea-pending-append) cmd_idea_pending_append "$@" ;;
  idea-template-body) cmd_idea_template_body "$@" ;;
  idea-pending-validate) cmd_idea_pending_validate "$@" ;;
  remote-presence)   cmd_remote_presence "$@" ;;
  evidence-scan-session) cmd_evidence_scan_session "$@" ;;
  lifecycle-state)   cmd_lifecycle_state "$@" ;;
  artifact-read)     cmd_artifact_read "$@" ;;
  artifact-write)    cmd_artifact_write "$@" ;;
  route-of)          cmd_route_of "$@" ;;
  ssot-migrate)      cmd_ssot_migrate "$@" ;;
  session-info)      cmd_session_info "$@" ;;
  *)
    echo "Usage: docs-check.sh {status|validate|recommend|audit-session|config-get|list-specs|activate|complete|pr-cleanup|land|idea-add|idea-list|idea-count|idea-update|idea-sync|idea-pending-replay|refresh-plan-hash|idea-migrate|idea-setup|idea-upgrade|title-from-body|legacy-refs-scan|stamp-spec|idea-pending-append|idea-pending-validate|remote-presence} [args...]" >&2
    exit 1
    ;;
esac
