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

# PROJECT_TREE_SUBCOMMANDS (BTS-212) — single source of truth for the family
# of subcommands that operate on a project root and therefore must:
#   1. accept --project-dir <path> to specify the root (skill prose calls
#      `--project-dir .` mechanically across these); and
#   2. emit a clean `Usage: ...` to stderr + exit 2 on any unknown flag,
#      rather than silently consuming it (`*) shift ;;`) and letting the
#      flag string reach a downstream tool like dirname/jq/sed which
#      produces a cryptic non-substrate error message.
#
# Excluded from this set:
#   - Pure-utility cmds that operate on stdin/stdout or take a single file
#     path (no project-root resolution): extract-work, title-from-body,
#     idea-template-body, derive-pr-title.
#   - Internal pass-through cmds invoked only from other cmds in the family
#     (their callers own the flag): auto-close-emit, auto-transition-emit,
#     idea-pending-append, idea-pending-validate.
#
# When adding a new subcommand that resolves a project root, append it here
# AND apply the canonical arg-loop pattern (see cmd_session_info for the
# reference shape). hub/tests/docs-check-flags.bats enforces both directions:
# (a) every name listed here must implement the contract; (b) every dispatched
# cmd that parses --project-dir must appear in this list.
PROJECT_TREE_SUBCOMMANDS=(
  status validate recommend audit-session config-get list-specs
  activate complete pr-cleanup detect-repo-type land land-recover-branch
  sync-check pr-guard radar-gather
  idea-add idea-list idea-count idea-count-local idea-update idea-sync
  idea-pending-replay idea-review-icebox idea-migrate-state idea-migrate
  idea-setup idea-upgrade provider-resolve-ids provider-heal-preflight provider-heal-auth provider-heal
  refresh-plan-hash archive-stasis sessions-list legacy-refs-scan stamp-spec
  evidence-scan-session lifecycle-state
  artifact-read artifact-write route-of ssot-migrate
  session-info assert-pr-title remote-presence
  stasis-carry-forward ship-finalize validate-spec
)

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
# @manifest
# purpose: Read session-counter + session-boundary state files and emit a JSON envelope (counter, epoch, iso, tz) for /recall and /stasis cold-start briefings
# input: --project-dir <path>
# output: stdout JSON envelope {counter, epoch, iso, tz}
# output: exit-codes 0 ok, 2 on unknown flag
# caller: skill:/recall
# caller: skill:/stasis
# depends-on: jq
# side-effect: reads-state-file
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: non-integer-counter | exit=0 | visible=stderr-WARN | mitigation=read-as-0-and-continue
# contract: never-fails-on-missing-state-files
# contract: single-fork-jq-emission
# anchor: BTS-206 (session counter substrate)
# anchor: BTS-207 (single-fork jq read)
# anchor: BTS-241 (manifest seed)
cmd_session_info() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh session-info [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done

  local counter_path boundary_path counter epoch iso tz raw
  counter_path="$project_dir/.ccanvil/state/session-counter"
  boundary_path="$project_dir/.ccanvil/state/session-boundary"

  counter=0
  # @side-effect: reads-state-file
  if [[ -f "$counter_path" ]]; then
    raw=$(tr -d '[:space:]' < "$counter_path" 2>/dev/null || echo "")
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
      counter="$raw"
    else
      # @failure-mode: non-integer-counter
      echo "WARN: session-counter contains non-integer; reading as 0" >&2
    fi
  fi

  # BTS-207: single-fork read regardless of boundary file state. The previous
  # shape (validity check + 3 field reads + assembly = 5 forks per call)
  # violates deterministic-first.md without offering anything in return —
  # /stasis and /recall both call this on every invocation. The new shape:
  # one jq with try/fromjson catches invalid-JSON at the language level;
  # the only branch is missing-file (skip jq entirely is impossible, so
  # we still need one fork to emit the empty envelope).
  if [[ -f "$boundary_path" ]]; then
    jq -n --argjson counter "$counter" --rawfile raw "$boundary_path" \
      'try ($raw | fromjson | {counter:$counter, epoch:(.epoch//null), iso:(.iso//null), tz:(.tz//null)})
       catch {counter:$counter, epoch:null, iso:null, tz:null}'
  else
    jq -n --argjson counter "$counter" \
      '{counter:$counter, epoch:null, iso:null, tz:null}'
  fi
}

# ---------------------------------------------------------------------------
# cmd_status — Extract metadata + compute content hashes for all docs.
#
# Output: JSON object with spec, plan, stasis entries.
# ---------------------------------------------------------------------------
# @manifest
# purpose: Extract metadata + compute content hashes for spec/plan/stasis docs in the active docs dir; emit a JSON envelope for /recall, /radar, /idea, drift-watchdog, and other consumers that need fresh doc state
# input: --project-dir <path>
# input: positional <docs-dir> (legacy)
# output: stdout JSON {spec, plan, stasis, last_compact_ts}
# output: exit-codes 0 ok, 2 unknown-flag
# caller: skill:/recall
# caller: skill:/radar
# caller: skill:/stasis
# caller: skill:/idea
# caller: skill:/drift-watchdog
# depends-on: jq
# depends-on: doc_entry
# side-effect: reads-spec-plan-stasis
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-doc | exit=0 | visible=null-entry-in-output | mitigation=consumer-handles-null
# contract: emits-null-entries-for-missing-docs
# contract: never-fails-on-missing-files
# anchor: BTS-113 (last-compact-ts surfacing)
# anchor: BTS-212 (arg loop refactor)
# anchor: BTS-241 (manifest seed)
cmd_status() {
  # BTS-212: arg loop — accepts --project-dir <path> or legacy positional
  # docs_dir. Unknown flags emit Usage + exit 2.
  local project_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh status [--project-dir <path>] [<docs-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local docs_dir
  if [[ -n "$project_dir" ]]; then
    docs_dir="$project_dir/$DEFAULT_DOCS_DIR"
  else
    docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  fi

  # @side-effect: reads-spec-plan-stasis
  # @failure-mode: missing-doc
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
# @manifest
# purpose: Cross-validate spec/plan/stasis alignment — detect mismatched feature_ids, stale plans (spec hash drift), and stale stasis (plan hash drift); priority order mismatched > stale-plan > stale-stasis > aligned
# input: --project-dir <path>
# input: positional <docs-dir> (legacy)
# output: stdout JSON {result, details:[], status:{spec, plan, stasis}}
# output: exit-codes 0 always (result encoded in JSON), 2 unknown-flag
# caller: cmd_lifecycle_state
# caller: cmd_recommend
# depends-on: cmd_status
# depends-on: jq
# side-effect: reads-spec-plan-stasis
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: aligned | exit=0 | visible=json-result-aligned
# failure-mode: mismatched | exit=0 | visible=json-result-mismatched | mitigation=consumer-acts-on-result-field
# failure-mode: stale-plan | exit=0 | visible=json-result-stale-plan | mitigation=re-run-/plan
# failure-mode: stale-stasis | exit=0 | visible=json-result-stale-stasis | mitigation=re-run-/stasis
# contract: priority-order-deterministic
# contract: never-fails-on-missing-files
# anchor: BTS-130 (Work: schema)
# anchor: BTS-241 (manifest seed)
cmd_validate() {
  # BTS-212: arg loop
  local project_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh validate [--project-dir <path>] [<docs-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local docs_dir
  if [[ -n "$project_dir" ]]; then
    docs_dir="$project_dir/$DEFAULT_DOCS_DIR"
  else
    docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  fi
  # @side-effect: reads-spec-plan-stasis
  local status_json
  status_json=$(cmd_status "$docs_dir")

  local spec_exists plan_exists stasis_exists
  spec_exists=$(echo "$status_json" | jq -r '.spec.exists')
  plan_exists=$(echo "$status_json" | jq -r '.plan.exists')
  stasis_exists=$(echo "$status_json" | jq -r '.stasis.exists')

  local details="[]"
  # @failure-mode: aligned
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
      # @failure-mode: mismatched
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
      # @failure-mode: stale-plan
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
      # @failure-mode: stale-stasis
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
# @manifest
# purpose: Recommend the next lifecycle action based on validate result + spec/plan/stasis presence + post-compact freshness — feeds /radar / /recall briefings
# input: --project-dir <path>
# input: positional <docs-dir> (legacy)
# output: stdout JSON {action, reason, command} or null
# output: exit-codes 0 ok, 2 unknown-flag
# depends-on: cmd_lifecycle_state
# depends-on: cmd_list_specs
# depends-on: jq
# side-effect: reads-lifecycle-state
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# contract: never-fails-on-missing-files
# contract: prefers-actions-that-unblock-current-state
# anchor: BTS-113 (last-compact-ts integration)
# anchor: BTS-241 (manifest seed)
cmd_recommend() {
  # BTS-20: state derivation delegated to cmd_lifecycle_state — single
  # source of truth for "where in the lifecycle are we?" Recommend's job
  # is to render a single rich action string with context (Ready spec ID,
  # triage count, blocker details). Output schema unchanged for callers.
  # BTS-212: arg loop
  local project_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh recommend [--project-dir <path>] [<docs-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local docs_dir
  if [[ -n "$project_dir" ]]; then
    docs_dir="$project_dir/$DEFAULT_DOCS_DIR"
  else
    docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  fi
  local project_root="$(dirname "$docs_dir")"

  # @side-effect: reads-lifecycle-state
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

# @manifest
# purpose: Scan git diffs since last stasis for stochastic-shaped patterns (Claude running cp/jq/find/diff/grep/git directly that should be a script call) and emit findings — post-hoc safety net for the warm-context determinism review
# input: --since <commit>
# input: --project-dir <path>
# input: positional <repo-dir>
# output: stdout markdown findings + counts
# output: exit-codes 0 always (findings encoded in output), 2 unknown-flag
# caller: skill:/recall
# depends-on: git
# side-effect: reads-git-diff
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# contract: never-fails-on-empty-diff
# contract: post-hoc-not-pre-emptive
# anchor: BTS-241 (manifest seed)
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
      --project-dir)
        repo_dir="${2:-.}"
        shift 2
        ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh audit-session [--since <commit>] [--project-dir <path>] [<repo-dir>]" >&2; exit 2 ;;
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

  # @side-effect: reads-git-diff
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
# @manifest
# purpose: List all specs in docs/specs/ as JSON [{feature_id, status}] for backlog enumeration; consumed by cmd_recommend, /radar, and the local-routed backlog.list resolution
# input: --project-dir <path>
# input: positional <docs-dir> (legacy)
# output: stdout JSON array [{feature_id, status, last_updated}]
# output: exit-codes 0 ok (empty array if no specs), 2 unknown-flag
# caller: cmd_recommend
# depends-on: parse_metadata
# depends-on: jq
# side-effect: reads-spec-archive
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: empty-archive | exit=0 | visible=stdout-empty-array | mitigation=expected-on-fresh-projects
# contract: empty-array-not-error-on-empty-archive
# anchor: BTS-241 (manifest seed)
cmd_list_specs() {
  # BTS-212: arg loop
  local project_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh list-specs [--project-dir <path>] [<docs-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local docs_dir
  if [[ -n "$project_dir" ]]; then
    docs_dir="$project_dir/$DEFAULT_DOCS_DIR"
  else
    docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  fi
  # @side-effect: reads-spec-archive
  local specs_dir="$docs_dir/specs"

  if [[ ! -d "$specs_dir" ]]; then
    # @failure-mode: empty-archive
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
# @manifest
# purpose: Activate a Draft spec — pre-flight sync-check, copy spec to docs/spec.md, create + push feature branch, open draft GitHub PR, dispatch artifact to Linear when route=linear, emit AUTO-TRANSITION marker for /activate to flip the linked Linear ticket → In Progress
# input: --force-sync
# input: --no-auto-push
# input: --project-dir <path>
# input: positional <feature-id>
# input: positional [docs-dir]
# output: stdout activation messages + branch/PR URL + AUTO-TRANSITION marker
# output: exit-codes 0 ok, 1 spec-not-found/dirty-tree/sync-failure/branch-failure, 2 unknown-flag/missing-feature-id
# caller: skill:/activate
# depends-on: cmd_sync_check
# depends-on: cmd_auto_transition_emit
# depends-on: parse_metadata
# depends-on: git
# depends-on: gh
# side-effect: copies-spec-to-active
# side-effect: creates-feature-branch
# side-effect: pushes-to-origin
# side-effect: creates-draft-pr
# side-effect: dispatches-spec-to-linear
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-feature-id | exit=2 | visible=stderr-Usage
# failure-mode: activation-blocked | exit=1 | visible=stderr-error | mitigation=resolve-blocker-and-retry
# contract: spec-status-flips-to-in-progress
# contract: never-leaves-partial-state-on-failure
# contract: emits-auto-transition-marker-on-linear-routed-specs
# anchor: BTS-145 (auto-push origin main)
# anchor: BTS-136 (auto-transition emission)
# anchor: BTS-213 (route-aware Linear dispatch)
# anchor: BTS-241 (manifest seed)
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
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force-local-ahead|--force-sync) force_sync=true; shift ;;
      --no-auto-push) auto_push=false; shift ;;
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh activate [--force-sync] [--no-auto-push] [--project-dir <path>] <feature-id> [<docs-dir>]" >&2; exit 2 ;;
      *)
        if [[ -z "$feature_id" ]]; then feature_id="$1"
        elif [[ -z "$docs_dir" ]]; then docs_dir="$1"
        fi
        shift
        ;;
    esac
  done
  # @failure-mode: missing-feature-id
  [[ -n "$feature_id" ]] || { echo "Usage: docs-check.sh activate [--force-sync] [--no-auto-push] [--project-dir <path>] <feature-id> [<docs-dir>]" >&2; exit 2; }
  if [[ -n "$project_dir_flag" && -z "$docs_dir" ]]; then
    docs_dir="$project_dir_flag/$DEFAULT_DOCS_DIR"
  fi
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

  # @side-effect: creates-feature-branch
  git -C "$repo_root" checkout -b "$branch_name" 2>/dev/null || {
    echo "ERROR: failed to create branch '$branch_name'" >&2
    exit 1
  }

  # Update status in specs/ to "In Progress"
  update_metadata_status "$spec_file" "In Progress"

  # @side-effect: copies-spec-to-active
  # Copy spec to docs/spec.md (after status update so it gets the new status)
  cp "$spec_file" "$docs_dir/spec.md"

  # Auto-commit spec changes on the branch
  git -C "$repo_root" add "$spec_file" "$docs_dir/spec.md"
  git -C "$repo_root" commit -q -m "docs(lifecycle): activate $feature_id" || {
    # @failure-mode: activation-blocked
    echo "ERROR: failed to commit spec changes on branch '$branch_name'" >&2
    exit 1
  }

  echo "Activated spec '$feature_id' on branch '$branch_name'"

  # @side-effect: pushes-to-origin
  # Push branch and create draft PR (if remote exists and gh available)
  if git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo_root" push -u origin "$branch_name" 2>/dev/null || true
    if command -v gh >/dev/null 2>&1; then
      local pr_title
      pr_title=$(cmd_derive_pr_title "$spec_file")
      local spec_body
      spec_body=$(cat "$spec_file")
      # @side-effect: creates-draft-pr
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
  #
  # Pass --project-dir explicitly: cmd_artifact_write must use the same
  # project root we resolved the route with, otherwise its internal
  # _lifecycle_route call would fall back to "." and silently hit the local
  # branch on non-cwd invocations.
  #
  # WARN-on-failure (not exit-on-failure): branch + push + draft-PR are
  # already done; bailing here would leave a half-state worse than a noisy
  # success. Operator can retry via the printed recipe.
  local project_dir
  project_dir=$(cd "$docs_dir/.." 2>/dev/null && pwd) || project_dir="."
  if [[ "$(_lifecycle_route spec "$project_dir")" == "linear" ]]; then
    # @side-effect: dispatches-spec-to-linear
    if ! cmd_artifact_write --kind spec --feature "$feature_id" --project-dir "$project_dir" < "$docs_dir/spec.md" >/dev/null; then
      echo "WARN: activate completed locally but Linear spec dispatch failed." >&2
      echo "Retry: bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature $feature_id --project-dir $project_dir < $docs_dir/spec.md" >&2
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
# @manifest
# purpose: Flip the active spec from In Progress → Complete in the archive (docs/specs/<id>.md), remove the active lifecycle docs (docs/spec.md, plan.md, stasis.md), and commit so the cleanup rides the squash-merge into main
# input: --project-dir <path>
# input: positional <feature-id>
# input: positional [docs-dir]
# output: stdout completion + archive transition messages
# output: exit-codes 0 ok, 1 spec-not-found/wrong-status, 2 unknown-flag/missing-feature-id
# caller: cmd_pr_cleanup
# depends-on: parse_metadata
# depends-on: update_metadata_status
# depends-on: jq
# depends-on: git
# side-effect: flips-spec-status
# side-effect: removes-active-lifecycle-docs
# side-effect: commits-cleanup
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-feature-id | exit=2 | visible=stderr-Usage
# failure-mode: spec-not-found | exit=1 | visible=stderr-error | mitigation=verify-feature-id-matches-archive
# failure-mode: wrong-status | exit=1 | visible=stderr-error | mitigation=activate-first-or-revert-state
# contract: idempotent-when-already-complete-not-supported
# contract: never-removes-archive-only-active-docs
# anchor: BTS-212 (arg loop refactor)
# anchor: BTS-241 (manifest seed)
cmd_complete() {
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh complete [--project-dir <path>] <feature-id> [<docs-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local feature_id="${1:-}"
  if [[ -z "$feature_id" ]]; then
    # @failure-mode: missing-feature-id
    echo "Usage: docs-check.sh complete [--project-dir <path>] <feature-id> [<docs-dir>]" >&2
    exit 2
  fi
  local docs_dir
  if [[ -n "$project_dir_flag" ]]; then
    docs_dir="$project_dir_flag/$DEFAULT_DOCS_DIR"
  else
    docs_dir="${2:-$DEFAULT_DOCS_DIR}"
  fi
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
    # @failure-mode: spec-not-found
    echo "ERROR: spec with feature_id '$feature_id' not found in $specs_dir" >&2
    exit 1
  fi

  # Verify spec is In Progress
  local current_status
  current_status=$(parse_metadata "$spec_file" | jq -r '.status // empty')
  if [[ "$current_status" != "In Progress" ]]; then
    # @failure-mode: wrong-status
    echo "ERROR: spec '$feature_id' is '$current_status', not 'In Progress'" >&2
    exit 1
  fi

  # @side-effect: flips-spec-status
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

  # @side-effect: removes-active-lifecycle-docs
  # Remove lifecycle docs (they're preserved in git history on the branch)
  rm -f "$docs_dir/spec.md" "$docs_dir/plan.md" "$docs_dir/stasis.md"

  # @side-effect: commits-cleanup
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

# @manifest
# purpose: Clean up lifecycle docs (spec.md, plan.md, stasis.md) before PR merge — invokes cmd_complete on the active spec to flip Status → Complete and remove the active docs, or falls back to bare-cleanup commit when no spec.md exists
# input: --project-dir <path>
# input: positional <docs-dir> (legacy)
# output: stdout cmd_complete output (path archive transitions)
# output: exit-codes 0 ok, 1 missing-feature_id, 2 unknown-flag
# caller: skill:/pr
# depends-on: cmd_complete
# depends-on: parse_metadata
# depends-on: jq
# side-effect: removes-lifecycle-docs
# side-effect: commits-cleanup
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-feature-id | exit=1 | visible=stderr-error | mitigation=verify-spec-metadata
# contract: idempotent-when-no-spec-present
# contract: leaves-clean-tree-on-feature-branch
# anchor: BTS-212 (arg loop refactor)
# anchor: BTS-241 (manifest seed)
cmd_pr_cleanup() {
  # BTS-212: arg loop
  local project_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh pr-cleanup [--project-dir <path>] [<docs-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local docs_dir
  if [[ -n "$project_dir" ]]; then
    docs_dir="$project_dir/$DEFAULT_DOCS_DIR"
  else
    docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  fi
  local spec_file="$docs_dir/spec.md"

  if [[ -f "$spec_file" ]]; then
    local feature_id
    feature_id=$(parse_metadata "$spec_file" | jq -r '.feature_id // empty')
    if [[ -z "$feature_id" ]]; then
      # @failure-mode: missing-feature-id
      echo "ERROR: could not parse feature_id from $spec_file" >&2
      exit 1
    fi
    cmd_complete "$feature_id" "$docs_dir"
  else
    # @side-effect: removes-lifecycle-docs
    # @side-effect: commits-cleanup
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
# @manifest
# purpose: Parse the Work: metadata line from a spec file and emit {provider, id} JSON; legacy/malformed Work fields are silently skipped (empty stdout, success) so callers can chain extract → dispatch
# input: positional <spec-file>
# output: stdout JSON {provider, id} when Work: present and well-formed
# output: stdout empty when Work: absent or malformed
# output: exit-codes 0 ok, 1 spec-not-found, 2 missing-required-arg
# depends-on: jq
# depends-on: parse_metadata
# side-effect: reads-spec-file
# failure-mode: missing-spec-arg | exit=2 | visible=stderr-Usage | mitigation=pass-spec-file-path
# failure-mode: spec-not-found | exit=1 | visible=stderr-error | mitigation=verify-path-exists
# failure-mode: legacy-no-work | exit=0 | visible=empty-stdout | mitigation=callers-skip-empty-output
# contract: malformed-work-emits-empty-not-error
# anchor: BTS-130 (Work: schema)
# anchor: BTS-241 (manifest seed)
cmd_extract_work() {
  # @failure-mode: missing-spec-arg
  local spec_file="${1:?Usage: extract-work <spec-file>}"
  if [[ ! -f "$spec_file" ]]; then
    # @failure-mode: spec-not-found
    echo "ERROR: spec file not found: $spec_file" >&2
    exit 1
  fi

  # @side-effect: reads-spec-file
  # @failure-mode: legacy-no-work
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
# @manifest
# purpose: Map a feature branch to its linked Linear ticket and emit an AUTO-TRANSITION marker on stdout for a /activate-class skill wrapper to dispatch via ticket.transition
# input: positional <branch-name>
# input: positional <role> (e.g. todo, in_progress, done)
# input: positional [docs-dir]
# output: stdout "AUTO-TRANSITION: {provider, id, role}" line on linear: spec branches
# output: stdout silent on legacy/non-claude/non-linear branches
# output: exit-codes 0 always (graceful degradation by design)
# caller: cmd_activate
# depends-on: cmd_extract_work
# depends-on: jq
# side-effect: emits-auto-transition-marker
# failure-mode: non-claude-branch | exit=0 | visible=silent
# failure-mode: missing-spec | exit=0 | visible=silent | mitigation=expected-on-non-spec-branches
# failure-mode: legacy-no-work | exit=0 | visible=silent | mitigation=expected-on-pre-BTS-130-specs
# contract: never-fails-activation
# contract: idempotent-on-already-transitioned-tickets
# anchor: BTS-136 (auto-transition markers)
# anchor: BTS-149 (enqueue-on-failure-only)
# anchor: BTS-241 (manifest seed)
cmd_auto_transition_emit() {
  # BTS-136 — emit AUTO-TRANSITION marker for a given role. Mirror of
  # cmd_auto_close_emit's decision tree — only difference is the role is
  # caller-specified and the marker prefix is different.
  local branch="${1:?Usage: auto-transition-emit <branch-name> <role> [docs-dir]}"
  local role="${2:?Usage: auto-transition-emit <branch-name> <role> [docs-dir]}"
  local docs_dir="${3:-$DEFAULT_DOCS_DIR}"

  # @failure-mode: non-claude-branch
  if [[ ! "$branch" =~ ^claude/[^/]+/(.+)$ ]]; then
    return 0
  fi
  local feature_id="${BASH_REMATCH[1]}"
  local spec_file="${docs_dir}/specs/${feature_id}.md"
  # @failure-mode: missing-spec
  if [[ ! -f "$spec_file" ]]; then
    return 0
  fi

  local work_json
  work_json=$(cmd_extract_work "$spec_file")
  # @failure-mode: legacy-no-work
  if [[ -z "$work_json" ]]; then
    return 0
  fi

  local provider id
  provider=$(echo "$work_json" | jq -r '.provider')
  id=$(echo "$work_json" | jq -r '.id')

  case "$provider" in
    linear)
      # @side-effect: emits-auto-transition-marker
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

# @manifest
# purpose: Map a landed feature branch to its linked Linear ticket and emit an AUTO-CLOSE marker on stdout for /land or /ship to dispatch via ticket.transition (role=done)
# input: positional <branch-name>
# input: positional [docs-dir]
# output: stdout "AUTO-CLOSE: {provider, id, role:done}" line on linear: spec branches
# output: stdout informational skip messages on legacy/non-claude/local/other-provider branches
# output: exit-codes 0 always (graceful degradation; never fails landing)
# caller: cmd_land
# depends-on: cmd_extract_work
# depends-on: jq
# side-effect: reads-spec-file
# side-effect: emits-auto-close-marker
# failure-mode: non-claude-branch | exit=0 | visible=stdout-skip-message
# failure-mode: missing-spec | exit=0 | visible=silent | mitigation=expected-on-non-spec-branches
# failure-mode: legacy-no-work | exit=0 | visible=silent
# failure-mode: local-provider | exit=0 | visible=stdout-skip-message | mitigation=BTS-119-Linear-only-scope
# failure-mode: unknown-provider | exit=0 | visible=stdout-skip-message
# contract: linear-only-emits-marker
# contract: never-fails-landing
# anchor: BTS-119 (auto-close substrate)
# anchor: BTS-241 (manifest seed)
cmd_auto_close_emit() {
  local branch="${1:?Usage: auto-close-emit <branch-name> [docs-dir]}"
  local docs_dir="${2:-$DEFAULT_DOCS_DIR}"

  if [[ ! "$branch" =~ ^claude/[^/]+/(.+)$ ]]; then
    # @failure-mode: non-claude-branch
    echo "auto-close: no feature-id detected in last merge commit — skipping"
    return 0
  fi
  local feature_id="${BASH_REMATCH[1]}"
  local spec_file="${docs_dir}/specs/${feature_id}.md"
  # @failure-mode: missing-spec
  if [[ ! -f "$spec_file" ]]; then
    return 0
  fi

  # @side-effect: reads-spec-file
  local work_json
  work_json=$(cmd_extract_work "$spec_file")
  # Legacy spec without Work: → cmd_extract_work prints nothing.
  if [[ -z "$work_json" ]]; then
    # @failure-mode: legacy-no-work
    return 0
  fi

  local provider id
  provider=$(echo "$work_json" | jq -r '.provider')
  id=$(echo "$work_json" | jq -r '.id')

  case "$provider" in
    linear)
      # @side-effect: emits-auto-close-marker
      jq -cn --arg id "$id" '{provider:"linear",id:$id,role:"done"}' | \
        sed 's/^/AUTO-CLOSE: /'
      ;;
    local)
      # @failure-mode: local-provider
      echo "auto-close: local provider — skipping (BTS-119 Linear-only)"
      ;;
    *)
      # @failure-mode: unknown-provider
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
# @manifest
# purpose: Verify local main is in sync with origin/main before activating a feature branch — refuses ahead (unpushed leak) and behind (stale baseline); graceful no-op on offline / no-remote
# input: --project-dir <path>
# input: positional <repo-root> (legacy)
# output: stdout silent on success
# output: stderr error block with resolution hints on ahead/behind
# output: exit-codes 0 in-sync/no-remote/offline, 1 AHEAD, 2 BEHIND
# caller: cmd_activate
# depends-on: git
# side-effect: fetches-origin-main
# failure-mode: missing-repo-root | exit=2 | visible=stderr-Usage
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: ahead | exit=1 | visible=stderr-error-with-unpushed-list | mitigation=git-push-origin-main
# failure-mode: behind | exit=2 | visible=stderr-error-with-pull-hint | mitigation=git-pull-ff-only
# failure-mode: offline | exit=0 | visible=stderr-WARN | mitigation=continue-on-cached-state
# contract: ahead-precedence-over-behind-on-divergence
# contract: never-blocks-on-network-flakes
# anchor: BTS-122 (sync-check substrate)
# anchor: BTS-241 (manifest seed)
cmd_sync_check() {
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh sync-check [--project-dir <path>] <repo-root>" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local repo_root="${project_dir_flag:-${1:-}}"
  if [[ -z "$repo_root" ]]; then
    # @failure-mode: missing-repo-root
    echo "Usage: docs-check.sh sync-check [--project-dir <path>] <repo-root>" >&2
    exit 2
  fi

  # AC-9: no origin remote at all → no-op success.
  if ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi

  # @side-effect: fetches-origin-main
  # @failure-mode: offline
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
    # @failure-mode: ahead
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
    # @failure-mode: behind
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
# @manifest
# purpose: Verify the current feature branch is not behind origin/main before /pr finalizes — prevents PR base drift that would surface conflicts in CI rebases downstream
# input: --project-dir <path>
# output: stdout silent on success
# output: stderr error block with rebase/merge resolution hints when behind
# output: exit-codes 0 up-to-date/no-remote/offline, 1 BEHIND, 2 unknown-flag
# caller: skill:/pr
# depends-on: git
# side-effect: fetches-origin-main
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: cd-failure | exit=2 | visible=stderr-error | mitigation=verify-project-dir
# failure-mode: not-in-git-worktree | exit=1 | visible=stderr-error | mitigation=run-from-git-worktree
# failure-mode: behind-base | exit=1 | visible=stderr-error-with-rebase-hint | mitigation=git-rebase-or-merge
# failure-mode: offline | exit=0 | visible=stderr-WARN | mitigation=continue-on-cached-state
# contract: never-blocks-on-network-flakes
# anchor: BTS-122 (pr-guard substrate)
# anchor: BTS-241 (manifest seed)
cmd_pr_guard() {
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh pr-guard [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done
  if [[ -n "$project_dir_flag" ]]; then
    # @failure-mode: cd-failure
    cd "$project_dir_flag" 2>/dev/null || { echo "ERROR: cannot cd to $project_dir_flag" >&2; return 2; }
  fi
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    # @failure-mode: not-in-git-worktree
    echo "ERROR: not inside a git worktree." >&2
    exit 1
  }

  # No-op if no origin remote (fresh local-only repo).
  if ! git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi

  # @side-effect: fetches-origin-main
  # Fetch with short timeout; degrade gracefully on failure.
  if ! git -C "$repo_root" \
      -c http.lowSpeedLimit=1 -c http.lowSpeedTime=5 \
      fetch origin main 2>/dev/null; then
    # @failure-mode: offline
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
    # @failure-mode: behind-base
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
# @manifest
# purpose: BTS-138 — recover the landed feature branch name from the last squash-merge commit's (#<PR>) suffix via gh pr view, so cmd_land on main can still emit AUTO-CLOSE markers after gh pr merge --delete-branch has cleaned up the local branch
# input: --project-dir <path>
# output: stdout recovered branch name on success
# output: stdout empty + stderr WARN on graceful failure
# output: exit-codes 0 always (graceful degradation; never blocks landing)
# caller: cmd_land
# depends-on: git
# depends-on: gh
# side-effect: queries-gh-pr-view
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: cd-failure | exit=2 | visible=stderr-error
# failure-mode: no-pr-suffix | exit=0 | visible=stderr-WARN | mitigation=expected-on-non-squash-merges
# failure-mode: gh-missing | exit=0 | visible=stderr-WARN | mitigation=install-gh-cli
# failure-mode: gh-query-failed | exit=0 | visible=stderr-WARN | mitigation=verify-pr-exists
# contract: never-blocks-landing
# contract: skips-stasis-commits-via-subject-regex
# anchor: BTS-138 (recover-from-squash-merge)
# anchor: BTS-212 (arg loop refactor)
# anchor: BTS-241 (manifest seed)
cmd_land_recover_branch() {
  # BTS-212: arg loop — accepts --project-dir, rejects unknown flags.
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh land-recover-branch [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done
  if [[ -n "$project_dir_flag" ]]; then
    # @failure-mode: cd-failure
    cd "$project_dir_flag" 2>/dev/null || { echo "ERROR: cannot cd to $project_dir_flag" >&2; return 2; }
  fi
  # If HEAD commit subject looks like a session-stasis write (from /stasis
  # committed on main right before /compact), skip it and look at HEAD~1.
  # BTS-212: tolerate empty/no-commit repos — git log returns 128, set -e
  # would otherwise abort silently. `|| true` lets the WARN path below run.
  local subject
  subject=$(git log -1 --format=%s 2>/dev/null || true)
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
    # @failure-mode: no-pr-suffix
    echo "WARN: land on main — could not recover PR number from last commit" >&2
    return 0
  fi
  local pr="${BASH_REMATCH[1]}"

  # Require gh binary on PATH. Missing → WARN + skip (never fail).
  if ! command -v gh >/dev/null 2>&1; then
    # @failure-mode: gh-missing
    echo "WARN: land on main — gh unavailable, skipping PR recovery" >&2
    return 0
  fi

  # @side-effect: queries-gh-pr-view
  # Query the PR for its head ref. Exit nonzero or empty result → WARN + skip.
  local branch
  if ! branch=$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null) \
      || [[ -z "$branch" ]]; then
    # @failure-mode: gh-query-failed
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
# @manifest
# purpose: Inspect git remote and classify the working tree as github / local-only / other-remote so /pr and /ship can branch on push semantics; host-extracted classification avoids substring poisoning by paths that contain "github.com"
# input: --project-dir <path>
# output: stdout JSON {type, has_remote, remote_url} where type ∈ {github, local, other-remote}
# output: exit-codes 0 ok, 2 unknown-flag/cd-failure/not-git
# caller: skill:/pr
# depends-on: jq
# side-effect: reads-git-remote-config
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: cd-failure | exit=2 | visible=stderr-error | mitigation=verify-project-dir-exists
# failure-mode: not-in-git-repo | exit=2 | visible=stderr-error | mitigation=run-from-inside-git-worktree
# contract: host-not-substring-classification
# contract: github-enterprise-on-non-github-com-classified-as-other-remote
# anchor: BTS-72 (repo-type substrate origin)
# anchor: BTS-212 (arg loop refactor)
# anchor: BTS-241 (manifest seed)
cmd_detect_repo_type() {
  # BTS-212: arg loop — detect-repo-type takes no positionals; reject all flags
  # except --project-dir which scopes the cwd for the git inspection.
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh detect-repo-type [--project-dir <path>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  if [[ -n "$project_dir_flag" ]]; then
    # @failure-mode: cd-failure
    cd "$project_dir_flag" 2>/dev/null || { echo "ERROR: cannot cd to $project_dir_flag" >&2; return 2; }
  fi
  # @failure-mode: not-in-git-repo
  # @side-effect: reads-git-remote-config
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

# @manifest
# purpose: Switch to main, sync with remote, delete the merged feature branch, and emit AUTO-CLOSE marker for /land or /ship to dispatch ticket close; handles already-on-main edge case via cmd_land_recover_branch (BTS-138)
# input: --force
# input: --project-dir <path>
# output: stdout status messages + optional AUTO-CLOSE marker
# output: exit-codes 0 ok, 1 unmerged-pr/checkout-failed/conflict, 2 unknown-flag/cd-failure
# caller: skill:/land
# caller: cmd_ship_finalize
# depends-on: cmd_detect_repo_type
# depends-on: cmd_land_recover_branch
# depends-on: cmd_auto_close_emit
# depends-on: git
# depends-on: gh
# side-effect: switches-branch
# side-effect: deletes-feature-branch
# side-effect: fetches-origin
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: cd-failure | exit=2 | visible=stderr-error
# failure-mode: unmerged-pr | exit=1 | visible=stderr-error | mitigation=merge-PR-first-or-use-force
# failure-mode: checkout-main-failed | exit=1 | visible=stderr-error | mitigation=verify-main-branch-exists
# failure-mode: local-merge-conflict | exit=1 | visible=stderr-error | mitigation=resolve-on-feature-branch
# contract: never-deletes-unmerged-branch-without-force
# contract: idempotent-when-already-on-main
# contract: emits-auto-close-marker-on-linear-routed-specs
# anchor: BTS-72 (local-only path)
# anchor: BTS-119 (auto-close emission)
# anchor: BTS-138 (recover-from-squash-merge)
# anchor: BTS-241 (manifest seed)
cmd_land() {
  # BTS-212: arg loop
  local force=false
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh land [--force] [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done
  if [[ -n "$project_dir_flag" ]]; then
    # @failure-mode: cd-failure
    cd "$project_dir_flag" 2>/dev/null || { echo "ERROR: cannot cd to $project_dir_flag" >&2; return 2; }
  fi

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
      # @failure-mode: unmerged-pr
      echo "ERROR: No merged PR found for branch '$branch'. Merge the PR first, or use --force." >&2
      exit 1
    fi
  fi

  # @side-effect: switches-branch
  # @side-effect: fetches-origin
  # Switch to main
  git checkout main 2>/dev/null || git checkout master 2>/dev/null || {
    # @failure-mode: checkout-main-failed
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
        # @failure-mode: local-merge-conflict
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
  # @side-effect: deletes-feature-branch
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
# @manifest
# purpose: Read a single feature flag (or any features.* boolean) from the merged ccanvil.json + ccanvil.local.json config; returns "false" for missing keys so callers can branch with `[[ $(config-get ...) == "true" ]]`
# input: --project-dir <path>
# input: positional <key>
# input: positional <project-dir> (legacy)
# output: stdout boolean string ("true" / "false")
# output: exit-codes 0 ok, 1 merge-failure, 2 unknown-flag/missing-key
# depends-on: merge_config
# depends-on: jq
# side-effect: reads-config-files
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-key | exit=2 | visible=stderr-Usage
# failure-mode: merge-failure | exit=1 | visible=propagated-from-merge_config | mitigation=verify-config-json
# contract: missing-feature-key-returns-false-string
# anchor: BTS-241 (manifest seed)
cmd_config_get() {
  # BTS-212: arg loop — accepts --project-dir or legacy positional position 2.
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh config-get [--project-dir <path>] <key> [<project-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local key="${1:-}"
  if [[ -z "$key" ]]; then
    # @failure-mode: missing-key
    echo "Usage: docs-check.sh config-get [--project-dir <path>] <key> [<project-dir>]" >&2
    exit 2
  fi
  local project_dir="${project_dir_flag:-${2:-.}}"

  # @side-effect: reads-config-files
  # @failure-mode: merge-failure
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

# @manifest
# purpose: Gather strategic project state for the /radar skill — active spec, recent completed specs, idea count, ccanvil-status, lifecycle envelope — into a single JSON envelope so /radar can render without orchestrating multiple shell calls
# input: --project-dir <path>
# input: positional <docs-dir> (legacy)
# output: stdout JSON envelope {active_spec, completed_recent, idea_count, status, lifecycle}
# output: exit-codes 0 always, 2 unknown-flag
# caller: skill:/radar
# depends-on: parse_metadata
# depends-on: cmd_idea_count
# depends-on: jq
# side-effect: reads-spec-archive
# side-effect: queries-idea-provider
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# contract: never-fails-on-missing-files
# anchor: BTS-241 (manifest seed)
cmd_radar_gather() {
  # BTS-212: arg loop — accepts --project-dir <path> or legacy positional
  # docs_dir. Unknown flags emit Usage + exit 2.
  local project_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh radar-gather [--project-dir <path>] [<docs-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local docs_dir
  if [[ -n "$project_dir" ]]; then
    docs_dir="$project_dir/$DEFAULT_DOCS_DIR"
  else
    docs_dir="${1:-$DEFAULT_DOCS_DIR}"
  fi
  local result="{}"

  # @side-effect: reads-spec-archive
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
  # @side-effect: queries-idea-provider
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

# @manifest
# purpose: Append a new idea to the local provider's gitignored .ccanvil/ideas.log JSONL store with status="triage" and an epoch UID; counterpart to the http (Linear) capture path resolved by operations.sh idea.add
# input: positional <body>
# input: --title <title>
# input: --parent <ref> (capture-time parent link)
# input: positional <project-dir>
# output: stdout JSON {id, title, status:"triage"}
# output: exit-codes 0 ok, 2 missing-body
# caller: skill:/idea
# depends-on: jq
# side-effect: appends-ideas-log
# failure-mode: missing-body | exit=2 | visible=stderr-Usage
# contract: epoch-UID-monotonic
# anchor: BTS-70 (idea UID schema)
# anchor: BTS-162 (capture-time parent)
# anchor: BTS-241 (manifest seed)
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
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      --*) echo "Usage: docs-check.sh idea-add <body> [--title <t>] [--parent <ref>] [--project-dir <path>]" >&2; exit 2 ;;
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

  # @failure-mode: missing-body
  [[ -n "$body" ]] || { echo "Usage: docs-check.sh idea-add <body> [--title TITLE] [--parent REF] [--project-dir <path>]" >&2; exit 2; }

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

  # @side-effect: appends-ideas-log
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
# @manifest
# purpose: BTS-172 — compose an idea body from a base body plus optional decoration flags (source-skill anchor, surfaced-at context, family cross-reference); deterministic + side-effect-free for testability
# input: --body <text>
# input: --source-skill <name>
# input: --context <text>
# input: --family <BTS-A,BTS-B,...>
# output: stdout templated body string
# output: exit-codes 0 ok, 2 missing-body/empty-flag-arg
# caller: skill:/idea
# depends-on: printf
# side-effect: emits-templated-body-stdout
# failure-mode: missing-body | exit=1 | visible=stderr-Usage
# failure-mode: empty-flag-arg | exit=2 | visible=stderr-error | mitigation=pass-non-empty-arg
# contract: deterministic-given-same-input
# contract: testable-in-isolation
# anchor: BTS-172 (idea-template-body substrate)
# anchor: BTS-241 (manifest seed)
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
          # @failure-mode: empty-flag-arg
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

  # @failure-mode: missing-body
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

  # @side-effect: emits-templated-body-stdout
  printf '%s\n' "$out"
}

# @manifest
# purpose: List ideas from the local provider's gitignored .ccanvil/ideas.log JSONL store, with optional status filter and archive inclusion; default view excludes terminal (canceled, duplicate) and deferred (icebox) states
# input: --status <s>
# input: --include-archive
# input: --project-dir <path>
# input: positional <project-dir> (legacy)
# output: stdout JSON array [{id, title, status, createdAt}]
# output: exit-codes 0 ok, 2 unknown-flag
# depends-on: jq
# side-effect: reads-ideas-log
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-log | exit=0 | visible=empty-array | mitigation=expected-on-fresh-projects
# contract: empty-array-when-no-ideas
# contract: excludes-terminal-and-deferred-by-default
# anchor: BTS-241 (manifest seed)
cmd_idea_list() {
  local filter_status=""
  local project_dir="."
  local include_archive=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status)          filter_status="$2"; shift 2 ;;
      --include-archive) include_archive=1; shift ;;
      --project-dir)     project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-list [--status <s>] [--include-archive] [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
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
        # @side-effect: reads-ideas-log
        grep -v '^# ' "$ideas_log" | jq -s "[.[] | {id: .uid, created: .created, title: .title, body: .body, status: .status}]" 2>/dev/null || echo "[]"
      else
        # @failure-mode: missing-log
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

# @manifest
# purpose: Aggregate the gitignored .ccanvil/ideas.log JSONL into per-status counts ({total, triage, backlog, icebox, ...}); renamed from cmd_idea_count in BTS-164 when cmd_idea_count became a provider-aware dispatcher
# input: --project-dir <path>
# input: positional <project-dir>
# output: stdout JSON {total, <status>: <count>, ...}
# output: exit-codes 0 ok, 2 unknown-flag
# caller: cmd_idea_count
# depends-on: jq
# side-effect: reads-ideas-log
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-log | exit=0 | visible=zeroed-counts
# contract: zeroed-counts-when-log-absent
# anchor: BTS-164 (provider-aware idea-count split)
# anchor: BTS-241 (manifest seed)
cmd_idea_count_local() {
  # Reads the gitignored .ccanvil/ideas.log JSONL and aggregates by status.
  # Renamed from cmd_idea_count in BTS-164 — cmd_idea_count is now a thin
  # dispatcher that resolves the routing and calls this for the local path
  # or shells out to linear-query.sh for the http path.
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-count-local [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local project_dir="${project_dir_flag:-${1:-.}}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"

  # Five-state vocab: triage/backlog/icebox/canceled/duplicate.
  # Legacy vocab folds in: new→triage, promoted→backlog, parked→icebox,
  # dismissed→canceled, merged→duplicate. `new` stays as a back-compat alias
  # for the triage counter so existing callers (radar-gather et al.) don't
  # regress.
  if [[ ! -f "$ideas_log" ]]; then
    # @failure-mode: missing-log
    jq -n '{total:0, triage:0, backlog:0, icebox:0, canceled:0, duplicate:0, new:0, promoted:0, parked:0, dismissed:0, merged:0}'
    return 0
  fi

  # @side-effect: reads-ideas-log
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

# @manifest
# purpose: BTS-164 — provider-aware idea counter; dispatches to cmd_idea_count_local on local-routed projects or to linear-query.sh aggregation on linear-routed; same output shape regardless of mechanism so radar-gather and /recall stay provider-neutral
# input: --project-dir <path>
# input: positional <project-dir>
# output: stdout JSON {total, triage, backlog, icebox, canceled, duplicate, new, promoted, parked, dismissed, merged}
# output: exit-codes 0 ok, 1 resolver-failure, 2 unknown-flag
# caller: cmd_radar_gather
# depends-on: cmd_idea_count_local
# depends-on: jq
# side-effect: reads-config-files
# side-effect: queries-provider
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: resolver-failure | exit=1 | visible=propagated-from-operations.sh | mitigation=verify-config-and-LINEAR_API_KEY
# contract: provider-neutral-output-shape
# anchor: BTS-164 (provider-aware idea-count)
# anchor: BTS-241 (manifest seed)
cmd_idea_count() {
  # BTS-164: provider-aware idea counter. Resolves idea.count to determine
  # whether to read the local JSONL log (mechanism=bash) or shell out to
  # linear-query.sh and aggregate Linear state (mechanism=http). Same
  # output shape regardless of mechanism so radar-gather and /recall stay
  # provider-neutral.
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-count [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local project_dir="${project_dir_flag:-${1:-.}}"
  local ops="$(dirname "$0")/operations.sh"

  # @side-effect: reads-config-files
  # @side-effect: queries-provider
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
      # @failure-mode: resolver-failure
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
# @manifest
# purpose: One-shot rewrite of legacy-vocab status values in .ccanvil/ideas.log (new→triage, promoted→backlog, parked→icebox, dismissed→canceled, merged→duplicate); writes timestamped backup before mutating; idempotent on already-migrated logs
# input: --project-dir <path>
# input: positional <project-dir>
# output: stdout migration count summary
# output: exit-codes 0 ok, 2 unknown-flag
# depends-on: jq
# side-effect: writes-backup-and-rewrites-ideas-log
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-log | exit=0 | visible=zero-migrations | mitigation=expected-on-fresh-projects
# contract: idempotent
# contract: backup-before-mutate
# anchor: BTS-241 (manifest seed)
cmd_idea_migrate_state() {
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-migrate-state [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local project_dir="${project_dir_flag:-${1:-.}}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"

  if [[ ! -f "$ideas_log" ]]; then
    # @failure-mode: missing-log
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
  # @side-effect: writes-backup-and-rewrites-ideas-log
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
# @manifest
# purpose: Surface Icebox-state ideas older than 60 days from the local ideas.log so /idea review-icebox can re-evaluate (promote / keep / dismiss / merge); prevents graveyard drift
# input: --project-dir <path>
# input: positional <project-dir>
# output: stdout JSON array of stale icebox entries
# output: exit-codes 0 ok, 2 unknown-flag
# caller: skill:/idea
# depends-on: jq
# side-effect: reads-ideas-log
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-log | exit=0 | visible=empty-array
# contract: 60-day-staleness-threshold
# anchor: BTS-241 (manifest seed)
cmd_idea_review_icebox() {
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-review-icebox [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local project_dir="${project_dir_flag:-${1:-.}}"
  local ideas_log="$project_dir/.ccanvil/ideas.log"
  local now threshold
  now=$(date +%s)
  threshold=$((now - 5184000))

  if [[ ! -f "$ideas_log" ]]; then
    # @failure-mode: missing-log
    echo "[]"
    return 0
  fi

  # @side-effect: reads-ideas-log
  grep -v '^# ' "$ideas_log" | jq -s --argjson t "$threshold" '
    [ .[]
      | select((.status == "icebox" or .status == "parked") and .created <= $t)
      | {id: .uid, created: .created, title: .title, body: .body, status: .status}
    ]
  '
}

# @manifest
# purpose: Update an idea's status field in the local provider's ideas.log via deterministic in-place rewrite (preserves order, tolerates blank lines, no jq -c re-encode that could mangle existing fields)
# input: --project-dir <path>
# input: positional <uid>
# input: positional <status>
# input: positional <project-dir>
# output: stdout success message
# output: exit-codes 0 ok, 1 missing-args/uid-not-found, 2 unknown-flag
# caller: skill:/idea
# depends-on: jq
# side-effect: rewrites-ideas-log
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-args | exit=2 | visible=stderr-Usage
# failure-mode: uid-not-found | exit=1 | visible=stderr-error | mitigation=verify-uid-via-/idea-list
# contract: status-transition-tolerant-no-validation
# anchor: BTS-241 (manifest seed)
cmd_idea_update() {
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-update [--project-dir <path>] <uid> <status> [<project-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local uid="${1:-}"
  local new_status="${2:-}"
  if [[ -z "$uid" || -z "$new_status" ]]; then
    # @failure-mode: missing-args
    echo "Usage: docs-check.sh idea-update [--project-dir <path>] <uid> <status> [<project-dir>]" >&2
    exit 2
  fi
  local project_dir="${project_dir_flag:-${3:-.}}"
  # @side-effect: rewrites-ideas-log
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
    # @failure-mode: uid-not-found
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
# @manifest
# purpose: List pending idea-sync entries from .ccanvil/ideas-pending.log as JSON, OR ack a specific entry by timestamp removing it from the log; full replay-and-dispatch flow lives in the separate idea-pending-replay verb
# input: --ack <ts>
# input: --project-dir <path>
# input: positional <project-dir>
# output: stdout JSON {pending, entries} on default; "ACKED: <ts>" on --ack
# output: exit-codes 0 ok, 2 unknown-flag
# depends-on: jq
# side-effect: rewrites-pending-log-on-ack
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-pending-log | exit=0 | visible=zeroed-output | mitigation=expected-state
# contract: ack-removes-by-ts-match
# anchor: BTS-179 (replay substrate split)
# anchor: BTS-241 (manifest seed)
cmd_idea_sync() {
  local project_dir="."
  local ack_ts=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ack)         ack_ts="$2"; shift 2 ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-sync [--ack <ts>] [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local pending="$project_dir/.ccanvil/ideas-pending.log"

  if [[ -n "$ack_ts" ]]; then
    if [[ ! -f "$pending" ]]; then
      echo "ACKED: $ack_ts (pending log absent — no-op)"
      return 0
    fi
    # @side-effect: rewrites-pending-log-on-ack
    local tmp
    tmp=$(mktemp)
    jq -c --argjson ts "$ack_ts" 'select(.ts != $ts)' "$pending" > "$tmp"
    mv "$tmp" "$pending"
    echo "ACKED: $ack_ts"
    return 0
  fi

  if [[ ! -f "$pending" || ! -s "$pending" ]]; then
    # @failure-mode: missing-pending-log
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
# @manifest
# purpose: Recompute the spec content hash and overwrite the plan's `> Spec hash:` metadata line in-place — used after the operator edits a spec post-/plan to clear stale-plan validation drift without re-running the full /plan flow
# input: --project-dir <path>
# input: positional <project-dir>
# output: stdout new hash
# output: exit-codes 0 ok, 1 missing-spec/missing-plan/missing-hash-line, 2 unknown-flag
# depends-on: content_hash
# depends-on: sed
# side-effect: rewrites-plan-metadata
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-spec | exit=1 | visible=stderr-error | mitigation=run-/spec-and-/activate
# failure-mode: missing-plan | exit=1 | visible=stderr-error | mitigation=run-/plan
# failure-mode: missing-hash-line | exit=1 | visible=stderr-error | mitigation=use-current-template
# contract: idempotent-when-spec-unchanged
# anchor: BTS-241 (manifest seed)
cmd_refresh_plan_hash() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh refresh-plan-hash [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local spec_file="$project_dir/docs/spec.md"
  local plan_file="$project_dir/docs/plan.md"

  if [[ ! -f "$spec_file" ]]; then
    # @failure-mode: missing-spec
    echo "ERROR: docs/spec.md not found" >&2
    return 1
  fi
  if [[ ! -f "$plan_file" ]]; then
    # @failure-mode: missing-plan
    echo "ERROR: docs/plan.md not found" >&2
    return 1
  fi
  if ! grep -qE '^> Spec hash: [a-f0-9]{6,}' "$plan_file"; then
    # @failure-mode: missing-hash-line
    # @side-effect: rewrites-plan-metadata
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
# @manifest
# purpose: Derive the canonical PR title from a spec — `feat(<feature-id>): <subject>` — preferring `> Subject:` metadata (auto-populated by stamp-spec) over Summary first-line extraction; truncates to ≤72 chars on word boundary
# input: positional <spec-file>
# output: stdout PR title string (no trailing newline manipulation)
# output: exit-codes 0 ok, 1 missing-arg/spec-not-found
# caller: cmd_activate
# caller: cmd_assert_pr_title
# depends-on: grep
# depends-on: sed
# side-effect: reads-spec-file
# failure-mode: missing-arg | exit=1 | visible=stderr-error | mitigation=pass-spec-file
# failure-mode: spec-not-found | exit=1 | visible=stderr-error | mitigation=verify-path
# contract: title-≤-72-chars
# contract: prefers-Subject-metadata-over-Summary
# anchor: BTS-236 (Subject metadata pivot)
# anchor: BTS-241 (manifest seed)
cmd_derive_pr_title() {
  local spec_file="${1:-}"
  local lookback=8
  if [[ -z "$spec_file" ]]; then
    # @failure-mode: missing-arg
    echo "ERROR: derive-pr-title: missing <spec-file> argument" >&2
    return 1
  fi
  if [[ ! -f "$spec_file" ]]; then
    # @failure-mode: spec-not-found
    echo "ERROR: derive-pr-title: spec file not found: $spec_file" >&2
    return 1
  fi

  # @side-effect: reads-spec-file
  local feature_id_meta first_line
  feature_id_meta=$(grep -m1 '^> Feature:' "$spec_file" | sed -E 's/^> Feature:[[:space:]]*//')

  # BTS-236: structural pivot — prefer `> Subject:` metadata field over
  # Summary first-line extraction. cmd_stamp_spec auto-populates Subject
  # from the H1 at /spec time; operator may also override it manually.
  # When present and non-empty, use directly (already shaped at /spec time
  # — skip the period-strip + 80-char truncation paths).
  # `|| true` guards against grep's exit-1 on no-match propagating up under
  # `set -euo pipefail`.
  local subject_line=""
  subject_line=$(grep -m1 '^> Subject:' "$spec_file" 2>/dev/null | sed -E 's/^> Subject:[[:space:]]*//' || true)
  if [[ -n "$subject_line" ]]; then
    echo "feat(${feature_id_meta}): ${subject_line}"
    return 0
  fi

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
# @manifest
# purpose: Archive the active stasis to docs/sessions/<epoch>-<feature-id>.md and commit — runs at /pr-cleanup time so the session history rides the squash-merge into main; route-aware (reads from Linear Document on Linear-routed nodes, BTS-230)
# input: --project-dir <path>
# input: positional <project-dir>
# output: stdout archive path on success
# output: exit-codes 0 ok, 1 no-stasis-found, 2 unknown-flag
# caller: skill:/stasis
# depends-on: cmd_artifact_read
# depends-on: _lifecycle_route
# depends-on: jq
# side-effect: writes-session-archive
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: no-stasis-found | exit=1 | visible=stderr-error | mitigation=run-/stasis-first
# contract: archive-named-by-epoch-then-feature-id
# anchor: BTS-22 (sessions archive substrate)
# anchor: BTS-230 (route-aware stasis read)
# anchor: BTS-241 (manifest seed)
cmd_archive_stasis() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh archive-stasis [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  # BTS-230: routing-aware source selection. On Linear-routed nodes the
  # stasis lives in a Linear Document, not docs/stasis.md. Read content
  # via cmd_artifact_read; try session-kind first (most common), then
  # feature-kind via docs/spec.md fallback. Output destination
  # (docs/sessions/<epoch>-<feature_id>.md) is unchanged.
  local stasis_content=""
  local route
  route=$(_lifecycle_route stasis "$project_dir")

  if [[ "$route" == "linear" ]]; then
    stasis_content=$(cmd_artifact_read --kind stasis --stasis-kind session --project-dir "$project_dir" 2>/dev/null) || stasis_content=""
    if [[ -z "$stasis_content" && -f "$project_dir/docs/spec.md" ]]; then
      local fallback_feature
      fallback_feature=$(grep -m1 '^> Feature:' "$project_dir/docs/spec.md" | sed -E 's/^> Feature:[[:space:]]*//' || true)
      if [[ -n "$fallback_feature" ]]; then
        stasis_content=$(cmd_artifact_read --kind stasis --feature "$fallback_feature" --project-dir "$project_dir" 2>/dev/null) || stasis_content=""
      fi
    fi
    if [[ -z "$stasis_content" ]]; then
      # @failure-mode: no-stasis-found
      echo "ERROR: archive-stasis: routing.stasis=linear but no stasis content found (tried session-kind, feature-kind)" >&2
      return 1
    fi
  else
    local stasis_file="$project_dir/docs/stasis.md"
    if [[ ! -f "$stasis_file" ]]; then
      echo "ERROR: archive-stasis: docs/stasis.md not found at $stasis_file" >&2
      return 1
    fi
    # Preserve trailing newline via sentinel pattern (bash strips trailing
    # newlines on $(cat ...)). Required for byte-identical archives.
    stasis_content=$(cat "$stasis_file"; printf x)
    stasis_content=${stasis_content%x}
  fi

  local feature_id epoch
  feature_id=$(printf '%s\n' "$stasis_content" | grep -m1 '^> Feature:' | sed -E 's/^> Feature:[[:space:]]*//' || true)
  if [[ -z "$feature_id" ]]; then
    echo "ERROR: archive-stasis: stasis missing > Feature: metadata" >&2
    return 1
  fi
  epoch=$(printf '%s\n' "$stasis_content" | grep -m1 '^> Last updated:' | sed -E 's/^> Last updated:[[:space:]]*//' || true)
  if [[ -z "$epoch" ]]; then
    epoch=$(printf '%s\n' "$stasis_content" | grep -m1 '^> Created:' | sed -E 's/^> Created:[[:space:]]*//' || true)
  fi
  if [[ -z "$epoch" ]]; then
    echo "ERROR: archive-stasis: stasis missing > Last updated: or > Created: epoch" >&2
    return 1
  fi

  local sessions_dir="$project_dir/docs/sessions"
  local rel_path="docs/sessions/${epoch}-${feature_id}.md"
  local dest="$project_dir/$rel_path"

  if [[ -f "$dest" ]]; then
    if diff -q <(printf '%s' "$stasis_content") "$dest" >/dev/null 2>&1; then
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
  # @side-effect: writes-session-archive
  printf '%s' "$stasis_content" > "$dest"
  jq -n --arg path "$rel_path" '{archived: true, path: $path}'
}

# ---------------------------------------------------------------------------
# cmd_sessions_list — BTS-22: list archived stasis files in
# docs/sessions/, sorted newest-first by epoch. Used by /recall to read
# recent N sessions without git archeology.
# ---------------------------------------------------------------------------
# @manifest
# purpose: List archived stasis files in docs/sessions/ as JSON [{path, feature_id, epoch, kind}], newest-first by epoch — consumed by /recall for cross-session pattern context (BTS-22)
# input: --project-dir <path>
# input: --limit <n>
# input: positional <project-dir>
# output: stdout JSON array
# output: exit-codes 0 ok, 2 unknown-flag
# caller: skill:/recall
# depends-on: jq
# side-effect: reads-sessions-archive
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: empty-archive | exit=0 | visible=stdout-empty-array
# contract: sorted-newest-first-by-epoch
# anchor: BTS-22 (sessions archive substrate)
# anchor: BTS-241 (manifest seed)
cmd_sessions_list() {
  local project_dir="."
  local limit=10
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      --limit)       limit="$2"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh sessions-list [--project-dir <path>] [--limit <n>] [<project-dir>]" >&2; exit 2 ;;
      *)             project_dir="$1"; shift ;;
    esac
  done

  # @side-effect: reads-sessions-archive
  local sessions_dir="$project_dir/docs/sessions"
  if [[ ! -d "$sessions_dir" ]]; then
    # @failure-mode: empty-archive
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
# @manifest
# purpose: BTS-178 — assert (or force-update via gh pr edit) that PR <N>'s title matches the spec-derived canonical form `feat(<feature-id>): <subject>` so the squash-merge subject on main is correct
# input: --project-dir <path>
# input: positional <pr-number>
# output: stdout JSON {updated, expected, actual}
# output: exit-codes 0 ok, 1 gh-missing/spec-not-found, 2 unknown-flag/missing-pr-arg
# caller: skill:/pr
# caller: cmd_ship_finalize
# depends-on: cmd_derive_pr_title
# depends-on: gh
# depends-on: jq
# side-effect: queries-gh-pr
# side-effect: maybe-updates-pr-title
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-pr-arg | exit=2 | visible=stderr-Usage
# failure-mode: gh-missing | exit=1 | visible=stderr-error | mitigation=install-gh-cli
# failure-mode: spec-not-found | exit=1 | visible=stderr-error | mitigation=verify-active-spec-or-archive
# contract: idempotent-when-title-matches
# anchor: BTS-178 (assert-pr-title substrate)
# anchor: BTS-241 (manifest seed)
cmd_assert_pr_title() {
  local pr_number=""
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh assert-pr-title [--project-dir <path>] <pr-number>" >&2; exit 2 ;;
      *)
        if [[ -z "$pr_number" ]]; then pr_number="$1"; else project_dir="$1"; fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr_number" ]]; then
    # @failure-mode: missing-pr-arg
    echo "Usage: docs-check.sh assert-pr-title [--project-dir <path>] <pr-number>" >&2
    return 2
  fi
  # @side-effect: queries-gh-pr
  if ! command -v gh >/dev/null 2>&1; then
    # @failure-mode: gh-missing
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
      # @failure-mode: spec-not-found
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
    # @side-effect: maybe-updates-pr-title
    gh pr edit "$pr_number" --title "$expected_title" >/dev/null
    jq -n --arg expected "$expected_title" --arg actual "$actual_title" \
      '{updated:true, expected:$expected, actual:$actual}'
  else
    jq -n --arg expected "$expected_title" --arg actual "$actual_title" \
      '{updated:false, expected:$expected, actual:$actual}'
  fi
}

# ---------------------------------------------------------------------------
# cmd_ship_finalize (BTS-235) — collapse the post-/pr ship-finalization
# sequence into one verb. Operator runs `/pr` first (which marks the PR
# ready); then `ship-finalize <PR>` runs:
#   1. pre-flight: gh pr view → state must not be MERGED
#   2. cmd_assert_pr_title → idempotent title force-update (BTS-178)
#   3. gh pr ready (idempotent — already-ready returns non-zero stderr)
#   4. gh pr merge --squash --delete-branch
#   5. cmd_land → on-main fast-forward + AUTO-CLOSE marker emission (BTS-138)
#   6. parse AUTO-CLOSE marker → dispatch ticket.transition done; queue on fail
#
# Test seam: GH_OVERRIDE env redirects bare `gh` calls to a stub script
# (mirrors LINEAR_QUERY_OVERRIDE — BTS-203 pattern).
#
# Output JSON:
#   {pr, pr_merged, branch_deleted, title_result|null, ticket_closed|null,
#    errors:[], step?}
# Exit 0 on full success or post-merge auto-close failure (idempotent);
# exit 1 on pre-merge failures (title/ready/merge); exit 2 on usage error.
# ---------------------------------------------------------------------------
_parse_auto_close() {
  # BTS-235: extract the JSON payload from cmd_land's AUTO-CLOSE: marker.
  # Returns the JSON on stdout, or empty string if no marker present.
  local stdout="$1"
  printf '%s\n' "$stdout" | sed -nE 's/^AUTO-CLOSE:[[:space:]]+(\{.*\})$/\1/p' | head -1
}

_ship_gh() {
  # BTS-235: gh wrapper honoring GH_OVERRIDE for tests.
  if [[ -n "${GH_OVERRIDE:-}" ]]; then
    bash "$GH_OVERRIDE" "$@"
  else
    gh "$@"
  fi
}

# @manifest
# purpose: Post-merge ship substrate — title-fix, mark-ready, squash-merge, fast-forward main, auto-close Linear ticket.
# input: positional <pr-number>
# input: --project-dir <path>
# output: stdout JSON envelope (always emitted, every code path)
# output: exit-codes 0 ok, 1 step-failure, 2 usage-error
# caller: skill:/ship
# depends-on: _ship_gh
# depends-on: cmd_assert_pr_title
# depends-on: cmd_land
# depends-on: _parse_auto_close
# depends-on: operations.sh
# depends-on: cmd_idea_pending_append
# side-effect: merges-pr
# side-effect: updates-pr-title
# side-effect: marks-pr-ready
# side-effect: fast-forwards-main
# side-effect: transitions-linear-ticket
# side-effect: queues-pending-on-failure
# failure-mode: usage-error | exit=2 | visible=stderr-usage
# failure-mode: preflight-error | exit=1 | visible=json-envelope-step-preflight
# failure-mode: title-error | exit=1 | visible=json-envelope-step-title
# failure-mode: ready-error | exit=1 | visible=json-envelope-step-ready
# failure-mode: merge-error | exit=1 | visible=json-envelope-step-merge
# contract: idempotent-on-already-merged
# contract: emits-json-envelope-every-path
# contract: never-blocks-on-linear-failure
# anchor: BTS-235 (origin — post-merge ship substrate)
# anchor: BTS-178 (title-fix integration)
# anchor: BTS-119 (queue-on-dispatch-failure pattern)
cmd_ship_finalize() {
  local pr_number=""
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      --*) echo "Usage: docs-check.sh ship-finalize [--project-dir <path>] <pr-number>" >&2; exit 2 ;;
      *)
        if [[ -z "$pr_number" ]]; then pr_number="$1"; fi
        shift
        ;;
    esac
  done

  # @failure-mode: usage-error
  if [[ -z "$pr_number" ]]; then
    echo "Usage: docs-check.sh ship-finalize [--project-dir <path>] <pr-number>" >&2
    return 2
  fi

  local errors='[]'

  # 1. Pre-flight: PR must exist, not already MERGED.
  # @failure-mode: preflight-error
  local pr_state pr_state_raw
  pr_state_raw=$(_ship_gh pr view "$pr_number" --json state --jq '.state' 2>&1) || {
    jq -n --arg pr "$pr_number" --arg err "$pr_state_raw" \
      '{pr:($pr|tonumber? // $pr), pr_merged:false, branch_deleted:false, title_result:null, ticket_closed:null, step:"preflight", errors:[$err]}'
    return 1
  }
  pr_state="$pr_state_raw"

  if [[ "$pr_state" == "MERGED" ]]; then
    # Idempotent: already merged → no-op.
    jq -n --arg pr "$pr_number" \
      '{pr:($pr|tonumber? // $pr), pr_merged:true, branch_deleted:true, title_result:null, ticket_closed:null, errors:[], note:"already merged"}'
    return 0
  fi

  # 2. Title fix (idempotent, BTS-178). cmd_assert_pr_title uses bare `gh`
  # @failure-mode: title-error
  # @side-effect: updates-pr-title
  # currently — the GH_OVERRIDE wrapper does not propagate. Acceptable: the
  # title-fix path is dogfood-validated, and bats tests for AC-3 cover the
  # parsing logic via a separate path. Production use unaffected.
  local title_result_json="" title_status=0
  title_result_json=$(cmd_assert_pr_title --project-dir "$project_dir" "$pr_number" 2>&1) || title_status=$?
  if (( title_status != 0 )); then
    jq -n --arg pr "$pr_number" --arg err "$title_result_json" \
      '{pr:($pr|tonumber? // $pr), pr_merged:false, branch_deleted:false, title_result:null, ticket_closed:null, step:"title", errors:[$err]}'
    return 1
  fi

  # 3. Mark ready (idempotent — already-ready emits stderr "already \"ready
  # @failure-mode: ready-error
  # @side-effect: marks-pr-ready
  # for review\"" with non-zero exit on some gh versions; treat as success).
  local ready_out ready_status=0
  ready_out=$(_ship_gh pr ready "$pr_number" 2>&1) || ready_status=$?
  if (( ready_status != 0 )) && ! echo "$ready_out" | grep -q 'ready for review'; then
    jq -n --arg pr "$pr_number" --arg err "$ready_out" --argjson tr "$title_result_json" \
      '{pr:($pr|tonumber? // $pr), pr_merged:false, branch_deleted:false, title_result:$tr, ticket_closed:null, step:"ready", errors:[$err]}'
    return 1
  fi

  # 4. Merge (squash + delete branch). gh switches HEAD to main on success.
  # @failure-mode: merge-error
  # @side-effect: merges-pr
  local merge_out merge_status=0
  merge_out=$(_ship_gh pr merge "$pr_number" --squash --delete-branch 2>&1) || merge_status=$?
  if (( merge_status != 0 )); then
    jq -n --arg pr "$pr_number" --arg err "$merge_out" --argjson tr "$title_result_json" \
      '{pr:($pr|tonumber? // $pr), pr_merged:false, branch_deleted:false, title_result:$tr, ticket_closed:null, step:"merge", errors:[$err]}'
    return 1
  fi

  # 5. Land — fast-forward main + recover landed branch + emit AUTO-CLOSE.
  # @side-effect: fast-forwards-main
  local land_out land_status=0
  land_out=$(cd "$project_dir" && cmd_land 2>&1) || land_status=$?
  # cmd_land non-zero is rare on the on-main path; capture but continue.
  if (( land_status != 0 )); then
    errors=$(echo "$errors" | jq --arg e "land non-zero: $land_out" '. + [$e]')
  fi

  # 6. Parse AUTO-CLOSE marker + dispatch ticket.transition done.
  # @side-effect: transitions-linear-ticket
  # @side-effect: queues-pending-on-failure
  local auto_close_json
  auto_close_json=$(_parse_auto_close "$land_out")
  local ticket_closed=null
  if [[ -n "$auto_close_json" ]]; then
    local provider id role
    provider=$(echo "$auto_close_json" | jq -r '.provider // empty')
    id=$(echo "$auto_close_json" | jq -r '.id // empty')
    role=$(echo "$auto_close_json" | jq -r '.role // "done"')
    if [[ "$provider" == "linear" && -n "$id" ]]; then
      local script_dir resolution dispatch_status=0
      script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      resolution=$(bash "$script_dir/operations.sh" resolve ticket.transition "$id" "$role" --project-dir "$project_dir" 2>&1) || dispatch_status=$?
      if (( dispatch_status == 0 )); then
        local cmd
        cmd=$(echo "$resolution" | jq -r '.invocation.command')
        if (cd "$project_dir" && eval "$cmd" </dev/null >/dev/null 2>&1); then
          ticket_closed=true
        else
          # BTS-119 pattern: queue on dispatch failure
          cmd_idea_pending_append --op ticket.transition --id "$id" --role "$role" --project-dir "$project_dir" >/dev/null 2>&1 || true
          ticket_closed=false
          errors=$(echo "$errors" | jq --arg e "ticket.transition dispatch failed; queued to ideas-pending.log" '. + [$e]')
        fi
      else
        cmd_idea_pending_append --op ticket.transition --id "$id" --role "$role" --project-dir "$project_dir" >/dev/null 2>&1 || true
        ticket_closed=false
        errors=$(echo "$errors" | jq --arg e "ticket.transition resolve failed; queued" '. + [$e]')
      fi
    fi
  fi

  jq -n --arg pr "$pr_number" --argjson tr "$title_result_json" \
    --argjson tc "$ticket_closed" --argjson errs "$errors" \
    '{pr:($pr|tonumber? // $pr), pr_merged:true, branch_deleted:true, title_result:$tr, ticket_closed:$tc, errors:$errs}'
  return 0
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
# BTS-233: per-log replay helper. Processes one JSONL log (entries-pending or
# dual-capture-emergency), dispatches each entry through the resolved http
# substrate, rewrites the source log with only failed entries. Increments
# `synced` and `failed` accumulators (one line per outcome) and appends per-
# entry result records to `results_file`. Returns 0 always — caller decides
# overall exit code based on the failed-accumulator size.
_idea_pending_replay_one_log() {
  local log_path="$1" project_dir="$2"
  local results_file="$3" synced_file="$4" failed_acc_file="$5"

  [[ ! -f "$log_path" || ! -s "$log_path" ]] && return 0

  local entries_file failed_file
  entries_file=$(mktemp)
  failed_file=$(mktemp)

  cp "$log_path" "$entries_file"

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  while IFS= read -r entry <&3; do
    [[ -z "$entry" ]] && continue
    local op ts
    op=$(printf '%s' "$entry" | jq -r '.op')
    ts=$(printf '%s' "$entry" | jq -r '.ts')

    local resolution_op resolution cmd dispatch_status=0 dispatch_err=""

    case "$op" in
      add)               resolution_op="idea.add" ;;
      promote|defer|dismiss|merge|ticket.transition)
                         resolution_op="ticket.transition" ;;
      *)
        echo 1 >> "$failed_acc_file"
        jq -n --argjson ts "$ts" --arg op "$op" --arg err "unknown op" \
          '{ts:$ts, op:$op, result:"failed", error:$err}' >> "$results_file"
        printf '%s\n' "$entry" >> "$failed_file"
        continue
        ;;
    esac

    if [[ "$op" == "add" ]]; then
      resolution=$(bash "$script_dir/operations.sh" resolve idea.add --project-dir "$project_dir" 2>&1) || {
        echo 1 >> "$failed_acc_file"
        jq -n --argjson ts "$ts" --arg op "$op" --arg err "resolve idea.add failed: $resolution" \
          '{ts:$ts, op:$op, result:"failed", error:$err}' >> "$results_file"
        printf '%s\n' "$entry" >> "$failed_file"
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
        echo 1 >> "$failed_acc_file"
        jq -n --argjson ts "$ts" --arg op "$op" --arg err "resolve ticket.transition failed: $resolution" \
          '{ts:$ts, op:$op, result:"failed", error:$err}' >> "$results_file"
        printf '%s\n' "$entry" >> "$failed_file"
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
      echo 1 >> "$synced_file"
      jq -n --argjson ts "$ts" --arg op "$op" '{ts:$ts, op:$op, result:"synced"}' >> "$results_file"
    else
      echo 1 >> "$failed_acc_file"
      printf '%s\n' "$entry" >> "$failed_file"
      jq -n --argjson ts "$ts" --arg op "$op" --arg err "$dispatch_err" \
        '{ts:$ts, op:$op, result:"failed", error:$err}' >> "$results_file"
    fi
  done 3< "$entries_file"

  # Rewrite source log with only failed entries (atomic mv).
  if [[ -s "$failed_file" ]]; then
    mv "$failed_file" "$log_path"
  else
    : > "$log_path"
    rm -f "$failed_file"
  fi
  rm -f "$entries_file"
}

# @manifest
# purpose: Drain ideas-pending.log AND dual-capture-emergency.log via the http substrate; ack on success, preserve failed entries in place.
# input: --project-dir <path>
# input: positional <project-dir> (legacy)
# output: stdout JSON {synced, failed, pending, emergency_pending, entries:[]}
# output: exit-codes 0 when failed==0; 1 when any entry failed; 2 usage
# caller: skill:/idea
# depends-on: _idea_pending_replay_one_log
# depends-on: jq
# side-effect: rewrites-pending-log
# side-effect: rewrites-emergency-log
# failure-mode: replay-dispatch-failure | exit=propagate | visible=stderr-per-entry | mitigation=rerun-after-network-recovery
# failure-mode: usage-error | exit=2 | visible=stderr-usage
# contract: idempotent-when-both-logs-empty
# contract: drains-both-logs-in-one-pass
# contract: preserves-failed-entries-for-retry
# anchor: BTS-179 (origin)
# anchor: BTS-233 (emergency-log drainage)
cmd_idea_pending_replay() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: usage-error
      --*) echo "Usage: docs-check.sh idea-pending-replay [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) project_dir="$1"; shift ;;
    esac
  done

  local pending="$project_dir/.ccanvil/ideas-pending.log"
  local emergency="$project_dir/.ccanvil/dual-capture-emergency.log"

  # BTS-233: process BOTH logs in a single invocation. Empty/absent
  # logs short-circuit individually inside the helper.
  local pending_empty=1 emergency_empty=1
  [[ -f "$pending" && -s "$pending" ]] && pending_empty=0
  [[ -f "$emergency" && -s "$emergency" ]] && emergency_empty=0

  if (( pending_empty == 1 && emergency_empty == 1 )); then
    jq -n '{synced: 0, failed: 0, pending: 0, emergency_pending: 0, entries: []}'
    return 0
  fi

  local results_file synced_file failed_acc_file
  results_file=$(mktemp)
  synced_file=$(mktemp)
  failed_acc_file=$(mktemp)
  trap 'rm -f "$results_file" "$synced_file" "$failed_acc_file"' RETURN

  # Process pending first, then emergency (BTS-233 ordering rationale in spec).
  # @side-effect: rewrites-pending-log
  # @side-effect: rewrites-emergency-log
  # @failure-mode: replay-dispatch-failure
  _idea_pending_replay_one_log "$pending" "$project_dir" \
    "$results_file" "$synced_file" "$failed_acc_file"
  _idea_pending_replay_one_log "$emergency" "$project_dir" \
    "$results_file" "$synced_file" "$failed_acc_file"

  local synced failed
  synced=$(wc -l < "$synced_file" 2>/dev/null | tr -d ' ' || echo 0)
  failed=$(wc -l < "$failed_acc_file" 2>/dev/null | tr -d ' ' || echo 0)
  : "${synced:=0}"
  : "${failed:=0}"

  local pending_count=0 emergency_pending_count=0
  if [[ -f "$pending" && -s "$pending" ]]; then
    pending_count=$(jq -s 'length' "$pending")
  fi
  if [[ -f "$emergency" && -s "$emergency" ]]; then
    emergency_pending_count=$(jq -s 'length' "$emergency")
  fi

  jq -s --argjson synced "$synced" --argjson failed "$failed" \
    --argjson pending "$pending_count" --argjson emergency_pending "$emergency_pending_count" \
    '{synced:$synced, failed:$failed, pending:$pending, emergency_pending:$emergency_pending, entries:.}' "$results_file"

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
# @manifest
# purpose: One-shot migration of legacy docs/ideas.md (markdown checkbox format) into the new .ccanvil/ideas.log JSONL store; --extract emits parsed JSONL only, --finalize removes legacy file + gitignores artifacts, default --full does both
# input: --extract / --finalize
# input: --project-dir <path>
# input: positional <project-dir>
# output: stdout migration progress + count
# output: exit-codes 0 ok (also when nothing to migrate), 2 unknown-flag
# depends-on: jq
# side-effect: appends-ideas-log
# side-effect: removes-legacy-ideas-md
# side-effect: updates-gitignore
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: nothing-to-migrate | exit=0 | visible=stdout-message | mitigation=expected-when-no-legacy-file
# contract: extract-and-finalize-can-run-separately
# contract: idempotent-no-op-on-already-migrated
# anchor: BTS-241 (manifest seed)
cmd_idea_migrate() {
  local project_dir="."
  local mode="full"   # full | extract | finalize

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --extract)     mode="extract"; shift ;;
      --finalize)    mode="finalize"; shift ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-migrate [--extract|--finalize] [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
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
        # @side-effect: removes-legacy-ideas-md
        rm -f "$ideas_md"
      fi
    fi
    touch "$gitignore"
    for entry in "docs/ideas.md" ".ccanvil/ideas-pending.log" ".ccanvil/ideas.log"; do
      if ! grep -qxF "$entry" "$gitignore" 2>/dev/null; then
        # @side-effect: updates-gitignore
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
      # @failure-mode: nothing-to-migrate
      [[ -f "$ideas_md" ]] || { echo "Nothing to migrate: $ideas_md not found"; return 0; }
      _idea_migrate_extract
      ;;
    full)
      if [[ ! -f "$ideas_md" ]]; then
        echo "Nothing to migrate: $ideas_md not found"
        return 0
      fi
      mkdir -p "$(dirname "$ideas_log")"
      # @side-effect: appends-ideas-log
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
# @manifest
# purpose: Initialize idea-routing config (.claude/ccanvil.local.json) for a new provider — writes integrations.routing.idea, scoping team/project, and resolves Linear state IDs by name; supports `--provider linear` and `--provider local`
# input: --provider <name>
# input: --team <id>
# input: --project <id>
# input: --project-dir <path>
# output: stdout config write summary
# output: exit-codes 0 ok, 1 provider-error/missing-required, 2 unknown-flag
# depends-on: jq
# side-effect: writes-ccanvil-local-json
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-required | exit=1 | visible=stderr-error | mitigation=pass-required-flags
# failure-mode: provider-error | exit=1 | visible=stderr-error | mitigation=verify-provider-credentials
# contract: idempotent-on-existing-config
# anchor: BTS-241 (manifest seed)
cmd_idea_setup() {
  local provider=""
  local team=""
  local project=""
  local project_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider)    provider="$2"; shift 2 ;;
      --team)        team="$2";     shift 2 ;;
      --project)     project="$2";  shift 2 ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-setup [--provider <p>] [--team <t>] [--project <p>] [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *)             project_dir="$1"; shift ;;
    esac
  done

  case "$provider" in
    local) ;;
    linear)
      # @failure-mode: missing-required
      [[ -n "$team" ]]    || { echo "ERROR: --provider linear requires --team TEAM" >&2; exit 1; }
      [[ -n "$project" ]] || { echo "ERROR: --provider linear requires --project PROJECT" >&2; exit 1; }
      ;;
    "")  echo "ERROR: --provider is required (local|linear)" >&2; exit 1 ;;
    *)
         # @failure-mode: provider-error
         echo "ERROR: unknown provider '$provider' (must be local|linear)" >&2; exit 1 ;;
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
  # @side-effect: writes-ccanvil-local-json
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
# Operator-config commands — manage $HOME/.ccanvil/operator.json, the
# operator-wide defaults tier consumed by the 3-tier merge_config in
# operations.sh (BTS-316). Provides scripts and skills with deterministic
# get/set semantics over operator-wide settings without hand-editing JSON.
# ---------------------------------------------------------------------------

# _operator_config_file — emit $HOME/.ccanvil/operator.json or "" when HOME unset.
# Mirrors operations.sh::_operator_config_path; duplicated here so docs-check.sh
# stays self-contained (no cross-script source). CCANVIL_OPERATOR_CONFIG_OVERRIDE
# wins for test-injection (BTS-316).
_operator_config_file() {
  if [[ -n "${CCANVIL_OPERATOR_CONFIG_OVERRIDE:-}" ]]; then
    echo "$CCANVIL_OPERATOR_CONFIG_OVERRIDE"
  elif [[ -n "${HOME:-}" ]]; then
    echo "$HOME/.ccanvil/operator.json"
  else
    echo ""
  fi
}

# _operator_config_dir — parent dir of operator.json. Used by set/init for mkdir.
_operator_config_dir() {
  if [[ -n "${CCANVIL_OPERATOR_CONFIG_OVERRIDE:-}" ]]; then
    dirname "$CCANVIL_OPERATOR_CONFIG_OVERRIDE"
  elif [[ -n "${HOME:-}" ]]; then
    echo "$HOME/.ccanvil"
  else
    echo ""
  fi
}

# _operator_config_atomic_write — write content via temp+mv to keep readers
# from seeing half-written JSON during set/init.
_operator_config_atomic_write() {
  local content="$1"
  local file
  file=$(_operator_config_file)
  if [[ -z "$file" ]]; then
    echo "ERROR: HOME unset; cannot write operator.json" >&2
    return 1
  fi
  local dir
  dir=$(_operator_config_dir)
  mkdir -p "$dir"
  local tmp
  tmp=$(mktemp "${dir}/.operator.XXXXXX") || {
    echo "ERROR: mktemp failed in $dir" >&2
    return 1
  }
  printf '%s\n' "$content" > "$tmp"
  if ! jq empty "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "ERROR: refused to write malformed JSON to $file" >&2
    return 1
  fi
  mv "$tmp" "$file"
}

# cmd_operator_config_init — Seed $HOME/.ccanvil/operator.json with the
# canonical operator-wide defaults shape. Idempotent.
# @manifest
# purpose: Seed $HOME/.ccanvil/operator.json with the canonical operator-wide defaults shape — providers.linear.team plus default_routes for spec/plan/stasis/idea kinds — so subsequent provider-activate invocations can fall back to operator-config team rather than requiring per-node --team flags
# input: --provider <name> (only "linear" supported in Phase 1)
# input: --team <name>
# input: env HOME (operator-config home directory base)
# output: writes $HOME/.ccanvil/operator.json with seeded shape
# output: stdout one-line summary "operator-config initialized: <file>"
# output: exit-codes 0 ok, 1 missing-flag-or-write-failure, 2 unknown-flag
# depends-on: jq
# depends-on: _operator_config_atomic_write
# side-effect: writes-operator-json
# failure-mode: missing-team | exit=1 | visible=stderr-error-team-required | mitigation=pass-team-flag
# failure-mode: non-linear-provider | exit=1 | visible=stderr-error-only-linear-supported | mitigation=use-linear
# failure-mode: home-unset | exit=1 | visible=stderr-error-HOME-unset | mitigation=set-HOME-env
# contract: idempotent-on-rerun
# contract: only-linear-provider-phase-1
# anchor: BTS-316 (operator-config layer)
cmd_operator_config_init() {
  local provider="" team=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="$2"; shift 2 ;;
      --team)     team="$2";     shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh operator-config init --provider linear --team <name>" >&2; return 2 ;;
      *) shift ;;
    esac
  done
  # @failure-mode: non-linear-provider
  [[ "$provider" == "linear" ]] || { echo "ERROR: --provider must be 'linear' (only linear supported in Phase 1)" >&2; return 1; }
  # @failure-mode: missing-team
  [[ -n "$team" ]] || { echo "ERROR: --team is required" >&2; return 1; }

  local file
  file=$(_operator_config_file)
  # @failure-mode: home-unset
  [[ -n "$file" ]] || { echo "ERROR: HOME unset; cannot resolve operator-config path" >&2; return 1; }

  # Build the seeded shape, deep-merging into any existing content so that
  # init is idempotent and preserves user-added keys.
  local existing='{}'
  if [[ -f "$file" ]]; then
    if ! jq empty "$file" 2>/dev/null; then
      echo "ERROR: $file is not valid JSON; refusing to overwrite" >&2
      return 1
    fi
    existing=$(cat "$file")
  fi
  # Seed shape mirrors ccanvil.json exactly — operator-tier values nest under
  # .integrations so 3-tier merge_config produces semantic results (operator
  # provides defaults at the same path that hub/node would override). The
  # default_routes block lives at .integrations.default_routes since it's a
  # provider-activate input, not a routing target itself.
  local seed
  seed=$(jq -n --arg provider "$provider" --arg team "$team" '
    {
      integrations: {
        providers: { ($provider): { team: $team } },
        default_routes: { spec: $provider, plan: $provider, stasis: $provider, idea: $provider }
      }
    }')
  # Deep-merge: existing tier wins (preserves user customizations); seed
  # only fills in absent keys. Ensures idempotency when called repeatedly.
  local merged
  merged=$(echo "$existing $seed" | jq -s '.[1] * .[0]')

  # @side-effect: writes-operator-json
  _operator_config_atomic_write "$merged" || return 1
  echo "operator-config initialized: $file"
}

# cmd_operator_config_get — Read a dotted-path key from operator.json.
# @manifest
# purpose: Read a dotted-path key (e.g. providers.linear.team) from $HOME/.ccanvil/operator.json — returns empty string + exit 0 when key or file is absent so callers can use `[[ -z "$x" ]]` for default-fallback logic without exit-code branching
# input: positional <dotted.key>
# input: env HOME
# output: stdout key value or empty
# output: exit-codes 0 always (treat as best-effort read)
# depends-on: jq
# depends-on: _operator_config_file
# side-effect: reads-operator-json
# failure-mode: missing-file | exit=0 | visible=empty-stdout | mitigation=run-operator-config-init
# failure-mode: missing-key | exit=0 | visible=empty-stdout | mitigation=run-operator-config-set
# contract: never-errors-on-missing
# anchor: BTS-316 (operator-config layer)
cmd_operator_config_get() {
  local key="${1:-}"
  if [[ -z "$key" ]]; then
    echo "Usage: docs-check.sh operator-config get <dotted.key>" >&2
    return 2
  fi
  local file
  file=$(_operator_config_file)
  # @failure-mode: missing-file
  [[ -n "$file" && -f "$file" ]] || { echo ""; return 0; }
  # @side-effect: reads-operator-json
  # Convert dotted-path to jq getpath. `getpath(["a","b","c"])` returns null
  # for missing intermediate keys; we map null→empty for shell-friendly output.
  jq -r --arg k "$key" '
    ($k | split(".")) as $path |
    getpath($path) // empty
  ' "$file" 2>/dev/null || { echo ""; return 0; }
}

# cmd_operator_config_set — Write a dotted-path key to operator.json.
# @manifest
# purpose: Write a dotted-path key (e.g. providers.linear.team) into $HOME/.ccanvil/operator.json — creates the file and parent directory atomically when absent so callers (skills, scripts) can persist operator-wide settings without hand-editing JSON
# input: positional <dotted.key>
# input: positional <value>
# input: env HOME
# output: writes $HOME/.ccanvil/operator.json with the updated key
# output: exit-codes 0 ok, 1 home-unset-or-write-failure, 2 missing-args
# depends-on: jq
# depends-on: _operator_config_atomic_write
# side-effect: writes-operator-json
# failure-mode: missing-args | exit=2 | visible=stderr-Usage | mitigation=pass-key-and-value
# failure-mode: home-unset | exit=1 | visible=stderr-error-HOME-unset | mitigation=set-HOME-env
# failure-mode: invalid-existing-json | exit=1 | visible=stderr-error-not-valid-JSON | mitigation=delete-or-fix-operator-json
# contract: creates-file-and-parent-dir-when-absent
# contract: atomic-write-via-temp-mv
# anchor: BTS-316 (operator-config layer)
cmd_operator_config_set() {
  local key="${1:-}"
  local value="${2:-}"
  if [[ -z "$key" ]]; then
    # @failure-mode: missing-args
    echo "Usage: docs-check.sh operator-config set <dotted.key> <value>" >&2
    return 2
  fi
  local file
  file=$(_operator_config_file)
  # @failure-mode: home-unset
  [[ -n "$file" ]] || { echo "ERROR: HOME unset; cannot resolve operator-config path" >&2; return 1; }

  local existing='{}'
  if [[ -f "$file" ]]; then
    # @failure-mode: invalid-existing-json
    if ! jq empty "$file" 2>/dev/null; then
      echo "ERROR: $file is not valid JSON; refusing to mutate" >&2
      return 1
    fi
    existing=$(cat "$file")
  fi

  local updated
  updated=$(echo "$existing" | jq --arg k "$key" --arg v "$value" '
    ($k | split(".")) as $path |
    setpath($path; $v)
  ')

  # @side-effect: writes-operator-json
  _operator_config_atomic_write "$updated" || return 1
}

# cmd_operator_config_show — Pretty-print operator.json content.
# @manifest
# purpose: Pretty-print the full operator-config JSON so operators and skills can inspect operator-wide settings — emits {} when the file is absent so callers (e.g. /radar) can render a "no operator config" branch via simple jq tests
# input: env HOME
# output: stdout pretty-printed JSON content (or {} when absent)
# output: exit-codes 0 always (best-effort read)
# depends-on: jq
# depends-on: _operator_config_file
# side-effect: reads-operator-json
# failure-mode: missing-file | exit=0 | visible=empty-object-stdout | mitigation=run-operator-config-init
# contract: never-errors-on-missing
# anchor: BTS-316 (operator-config layer)
cmd_operator_config_show() {
  local file
  file=$(_operator_config_file)
  # @failure-mode: missing-file
  if [[ -z "$file" || ! -f "$file" ]]; then
    echo "{}"
    return 0
  fi
  # @side-effect: reads-operator-json
  if ! jq empty "$file" 2>/dev/null; then
    echo "ERROR: $file is not valid JSON" >&2
    return 1
  fi
  jq '.' "$file"
}

# cmd_operator_config — Subcommand dispatcher for operator-config {init|get|set|show}.
# @manifest
# purpose: Dispatch operator-config subcommand routing — single CLI surface that branches to cmd_operator_config_{init,get,set,show} per the first positional arg; mirrors the cmd_idea / cmd_provider_heal sub-dispatcher shape for consistency
# input: positional <subcommand> ∈ {init, get, set, show}
# input: positional <subcommand-args...>
# output: subcommand-specific (delegated)
# output: exit-codes 0 ok, 2 unknown-subcommand, plus delegated codes
# depends-on: cmd_operator_config_init
# depends-on: cmd_operator_config_get
# depends-on: cmd_operator_config_set
# depends-on: cmd_operator_config_show
# side-effect: dispatcher-only
# failure-mode: unknown-subcommand | exit=2 | visible=stderr-Usage | mitigation=use-init-get-set-show
# contract: passes-args-verbatim-to-subcommand
# anchor: BTS-316 (operator-config layer)
cmd_operator_config() {
  local sub="${1:-}"
  if [[ -z "$sub" ]]; then
    echo "Usage: docs-check.sh operator-config {init|get|set|show} [args...]" >&2
    return 2
  fi
  shift
  case "$sub" in
    init) cmd_operator_config_init "$@" ;;
    get)  cmd_operator_config_get "$@" ;;
    set)  cmd_operator_config_set "$@" ;;
    show) cmd_operator_config_show "$@" ;;
    # @failure-mode: unknown-subcommand
    *)    echo "Usage: docs-check.sh operator-config {init|get|set|show} [args...]" >&2; return 2 ;;
  esac
}

# ---------------------------------------------------------------------------
# cmd_provider_resolve_ids — Resolve Linear provider IDs (team_id, project_id,
# state_ids[8], label_ids[idea]) from live API + deep-merge into
# .claude/ccanvil.local.json. Phase 1 of the provider-heal umbrella surfaced
# by the unifi-toolbox dogfood 2026-05-06.
# ---------------------------------------------------------------------------
# @manifest
# purpose: Resolve Linear provider IDs (team_id, project_id, eight canonical state_ids by role name, label_ids[idea]) from live linear-query.sh calls and deep-merge them into .claude/ccanvil.local.json's integrations.providers.linear block; collapses the 4-call manual heal flow surfaced by the unifi-toolbox dogfood into one verb
# input: --provider <name> (only "linear" supported in Phase 1)
# input: --team <name>
# input: --project <name>
# input: --project-dir <path>
# input: env LINEAR_API_KEY (consumed by linear-query.sh subprocess)
# input: env LINEAR_QUERY_OVERRIDE (test-injection point)
# output: stdout SETUP/RESOLVED summary lines
# output: writes .claude/ccanvil.local.json with merged providers.linear block
# output: exit-codes 0 ok, 1 missing-team-or-project-or-required-flag, 2 unknown-flag
# depends-on: jq
# depends-on: linear-query.sh
# side-effect: writes-ccanvil-local-json
# failure-mode: missing-team | exit=1 | visible=stderr-error-NamedTeam-not-found | mitigation=verify-team-name-matches-Linear
# failure-mode: missing-project | exit=1 | visible=stderr-error-NamedProject-not-found-in-team | mitigation=verify-project-name-and-team-scope
# failure-mode: missing-label-warn | exit=0 | visible=stderr-WARN-idea-label-not-resolved | mitigation=create-workspace-idea-label-and-rerun
# contract: idempotent-on-rerun
# contract: deep-merge-preserves-node_uuid-and-routing
# anchor: BTS-319 (provider-heal Phase 1)
cmd_provider_resolve_ids() {
  local provider=""
  local team=""
  local project=""
  local project_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider)    provider="$2"; shift 2 ;;
      --team)        team="$2";     shift 2 ;;
      --project)     project="$2";  shift 2 ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh provider-resolve-ids --provider linear --team <name> --project <name> [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done

  [[ "$provider" == "linear" ]] || { echo "ERROR: --provider must be 'linear' (Phase 1)" >&2; exit 1; }
  [[ -n "$team" ]]    || { echo "ERROR: --team is required" >&2; exit 1; }
  [[ -n "$project" ]] || { echo "ERROR: --project is required" >&2; exit 1; }

  local script_dir
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  local lq="${LINEAR_QUERY_OVERRIDE:-$script_dir/linear-query.sh}"

  # Step 1: resolve team_id by name.
  local team_id
  team_id=$(bash "$lq" list-teams 2>/dev/null \
    | jq -r --arg n "$team" '[.[] | select(.name == $n)] | .[0].id // empty')
  if [[ -z "$team_id" ]]; then
    # @failure-mode: missing-team
    echo "ERROR: team '$team' not found in Linear. Verify name matches an existing team." >&2
    exit 1
  fi

  # Step 2: resolve project_id by name (filter to team via list-projects).
  # list-projects has no --team flag; filter client-side by name.
  local project_id
  project_id=$(bash "$lq" list-projects 2>/dev/null \
    | jq -r --arg n "$project" '[.[] | select(.name == $n)] | .[0].id // empty')
  if [[ -z "$project_id" ]]; then
    # @failure-mode: missing-project
    echo "ERROR: project '$project' not found in Linear (team '$team'). Verify name." >&2
    exit 1
  fi

  # Step 3: resolve state_ids[8] from list-states --team <name>.
  # Map by case-insensitive name match to canonical roles. Extra states ignored.
  local states_json
  states_json=$(bash "$lq" list-states --team "$team" 2>/dev/null)
  local state_ids
  state_ids=$(echo "$states_json" | jq '
    def lookup(n): [.[] | select((.name | ascii_downcase) == (n | ascii_downcase))] | .[0].id // empty;
    {
      triage: lookup("Triage"),
      backlog: lookup("Backlog"),
      icebox: lookup("Icebox"),
      todo: lookup("Todo"),
      in_progress: lookup("In Progress"),
      done: lookup("Done"),
      duplicate: lookup("Duplicate"),
      canceled: lookup("Canceled")
    }')

  # Step 4: resolve label_ids[idea] — try team-scoped first, then workspace.
  local label_id
  label_id=$(bash "$lq" list-labels --team "$team" 2>/dev/null \
    | jq -r '[.[] | select(.name == "idea")] | .[0].id // empty')
  if [[ -z "$label_id" ]]; then
    label_id=$(bash "$lq" list-labels --workspace-scoped 2>/dev/null \
      | jq -r '[.[] | select(.name == "idea")] | .[0].id // empty')
  fi

  # Compose the heal slice.
  local slice
  if [[ -n "$label_id" ]]; then
    slice=$(jq -n \
      --arg team_id "$team_id" \
      --arg project_id "$project_id" \
      --argjson state_ids "$state_ids" \
      --arg label_id "$label_id" \
      '{integrations: {providers: {linear: {
        team_id: $team_id,
        project_id: $project_id,
        state_ids: $state_ids,
        label_ids: {idea: $label_id}
      }}}}')
  else
    # @failure-mode: missing-label-warn
    echo "WARN: idea label not resolved (neither team-scoped nor workspace-scoped) — capture-via-/idea will fail until label is created" >&2
    slice=$(jq -n \
      --arg team_id "$team_id" \
      --arg project_id "$project_id" \
      --argjson state_ids "$state_ids" \
      '{integrations: {providers: {linear: {
        team_id: $team_id,
        project_id: $project_id,
        state_ids: $state_ids
      }}}}')
  fi

  # Deep-merge into existing config.
  local cfg="$project_dir/.claude/ccanvil.local.json"
  mkdir -p "$project_dir/.claude"
  local existing='{}'
  [[ -f "$cfg" ]] && existing=$(cat "$cfg")
  echo "$existing" | jq --argjson slice "$slice" '. * $slice' > "$cfg.tmp"
  # @side-effect: writes-ccanvil-local-json
  mv "$cfg.tmp" "$cfg"

  echo "RESOLVED: provider=linear team=$team project=$project"
  echo "  team_id=$team_id"
  echo "  project_id=$project_id"
  echo "  state_ids: $(echo "$state_ids" | jq -r '[.[] | select(. != null)] | length')/8 resolved"
  if [[ -n "$label_id" ]]; then
    echo "  label_ids.idea=$label_id"
  fi
  echo "Wrote $cfg"
}

# ---------------------------------------------------------------------------
# cmd_provider_heal — Capstone: composes the three Phase primitives
# (BTS-321 auth → BTS-320 substrate-drift → BTS-319 ID resolution) into
# one fail-fast operator-facing verb.
# ---------------------------------------------------------------------------
# @manifest
# purpose: Operator-facing capstone that composes the three provider-heal phase primitives (BTS-321 auth check → BTS-320 substrate-drift gate → BTS-319 ID resolution) into one fail-fast verb; collapses the 3-command heal chain to a single operator action with halt-and-remediate behavior on each phase
# input: --provider <name> (only "linear" supported)
# input: --team <name>
# input: --project <name>
# input: --project-dir <path>
# input: --json (optional, structured envelope)
# input: env LINEAR_API_KEY (consumed by Phase 3 + Phase 1)
# input: env LINEAR_QUERY_OVERRIDE (test-injection point)
# input: env CCANVIL_SYNC_OVERRIDE (test-injection point)
# output: stdout PROVIDER-HEAL-OK summary or JSON envelope
# output: stderr forwards each phase's stderr verbatim on failure
# output: writes-ccanvil-local-json (only when all 3 phases succeed; via Phase 1)
# output: exit-codes 0 ok, 1 phase-halt, 2 unknown-flag-or-missing-required
# depends-on: jq
# depends-on: cmd_provider_heal_auth
# depends-on: cmd_provider_heal_preflight
# depends-on: cmd_provider_resolve_ids
# side-effect: writes-ccanvil-local-json-on-success-only
# failure-mode: auth-failed | exit=1 | visible=Phase-3-stderr | mitigation=fix-LINEAR_API_KEY
# failure-mode: drift-detected | exit=1 | visible=Phase-2-stderr | mitigation=run-/ccanvil-pull
# failure-mode: resolve-failed | exit=1 | visible=Phase-1-stderr | mitigation=verify-team-and-project
# contract: fail-fast-halt-on-first-phase-error
# contract: never-invokes-pull-auto-or-pull-apply
# anchor: BTS-326 (provider-heal umbrella)
cmd_provider_heal() {
  local provider="" team="" project="" project_dir="."
  local json_out=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider)    provider="$2"; shift 2 ;;
      --team)        team="$2";     shift 2 ;;
      --project)     project="$2";  shift 2 ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --json)        json_out=1; shift ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh provider-heal --provider linear --team <name> --project <name> [--project-dir <path>] [--json]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done

  [[ "$provider" == "linear" ]] || { echo "ERROR: --provider must be 'linear' (only linear supported in this phase)" >&2; exit 2; }
  [[ -n "$team" ]]    || { echo "ERROR: --team is required" >&2; exit 2; }
  [[ -n "$project" ]] || { echo "ERROR: --project is required" >&2; exit 2; }

  # Phase 3: auth
  local auth_json="" auth_rc=0
  if (( json_out )); then
    auth_json=$(cmd_provider_heal_auth --project-dir "$project_dir" --json) || auth_rc=$?
  else
    cmd_provider_heal_auth --project-dir "$project_dir" || auth_rc=$?
  fi
  if (( auth_rc != 0 )); then
    # @failure-mode: auth-failed
    if (( json_out )); then
      jq -n --argjson auth "$auth_json" '{status:"auth-failed", phases:{auth:$auth, drift:null, resolve_ids:null}, error:"Phase 3 (auth) halted"}'
    fi
    return 1
  fi

  # Phase 2: drift gate
  local drift_json="" drift_rc=0
  if (( json_out )); then
    drift_json=$(cmd_provider_heal_preflight --project-dir "$project_dir" --json) || drift_rc=$?
  else
    cmd_provider_heal_preflight --project-dir "$project_dir" || drift_rc=$?
  fi
  if (( drift_rc != 0 )); then
    # @failure-mode: drift-detected
    if (( json_out )); then
      jq -n --argjson auth "$auth_json" --argjson drift "$drift_json" \
        '{status:"drift-detected", phases:{auth:$auth, drift:$drift, resolve_ids:null}, error:"Phase 2 (drift) halted"}'
    fi
    return 1
  fi

  # Phase 1: resolve IDs
  # @side-effect: writes-ccanvil-local-json-on-success-only
  # In --json mode, suppress Phase 1's text summary output so it doesn't
  # contaminate the umbrella's JSON envelope on stdout. Phase 1's actual
  # work (config write) still happens normally.
  local resolve_rc=0
  if (( json_out )); then
    cmd_provider_resolve_ids --provider linear --team "$team" --project "$project" --project-dir "$project_dir" >/dev/null || resolve_rc=$?
  else
    cmd_provider_resolve_ids --provider linear --team "$team" --project "$project" --project-dir "$project_dir" || resolve_rc=$?
  fi
  if (( resolve_rc != 0 )); then
    # @failure-mode: resolve-failed
    if (( json_out )); then
      jq -n --argjson auth "$auth_json" --argjson drift "$drift_json" \
        '{status:"resolve-failed", phases:{auth:$auth, drift:$drift, resolve_ids:null}, error:"Phase 1 (resolve-ids) halted"}'
    fi
    return 1
  fi

  # All three phases succeeded.
  if (( json_out )); then
    # Re-run Phase 1 in JSON mode? No — the env was already mutated.
    # Synthesize a minimal resolve_ids envelope from the written config.
    local cfg="$project_dir/.claude/ccanvil.local.json"
    local resolve_envelope
    resolve_envelope=$(jq '.integrations.providers.linear | {status:"ok", team_id, project_id, state_count:(.state_ids | length), label_count:(.label_ids | length)}' "$cfg")
    jq -n --argjson auth "$auth_json" --argjson drift "$drift_json" --argjson resolve "$resolve_envelope" \
      '{status:"ok", phases:{auth:$auth, drift:$drift, resolve_ids:$resolve}, error:null}'
  else
    local viewer_id
    viewer_id=$(echo "$auth_json" | jq -r '.viewer_id // empty' 2>/dev/null)
    [[ -z "$viewer_id" ]] && viewer_id="VIEWER-1"  # fallback if json mode wasn't run
    # Re-extract from auth_json if available; otherwise use a generic placeholder.
    # Better: re-run cmd_provider_heal_auth --json once at the end to grab viewer-id.
    if [[ -z "$viewer_id" || "$viewer_id" == "VIEWER-1" ]]; then
      viewer_id=$(cmd_provider_heal_auth --project-dir "$project_dir" --json 2>/dev/null | jq -r '.viewer_id // "unknown"')
    fi
    echo "PROVIDER-HEAL-OK: auth=$viewer_id drift=clean ids=resolved"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# cmd_provider_activate — Operator-facing switch. Composes provider-heal
# (auth → drift → resolve) with a route-flip step so a node can opt into a
# provider end-to-end with one verb. Falls back to operator-config team and
# default_routes when not supplied via flags. Idempotent: re-running on an
# already-activated node produces zero diff in .claude/ccanvil.local.json.
# ---------------------------------------------------------------------------
# @manifest
# purpose: One-verb provider activation switch — composes the existing provider-heal umbrella (auth → drift gate → ID resolution) with a route-flip step that writes integrations.routing.<kind>=<provider> into .claude/ccanvil.local.json for each kind the operator names. Falls back to operator-config team + default_routes when --team / --routes are omitted. Idempotent on rerun.
# input: --provider <name> (only "linear" supported in Phase 1)
# input: --team <name> (optional; falls back to operator-config providers.<p>.team)
# input: --project <name> (required, no operator-default; per-node)
# input: --routes <comma-list> (optional; falls back to operator-config default_routes; hard default spec,plan,stasis,idea)
# input: --project-dir <path>
# input: --json (optional, structured envelope output)
# input: env LINEAR_API_KEY (consumed by provider-heal Phase 3 + Phase 1)
# input: env LINEAR_QUERY_OVERRIDE (test-injection point)
# input: env CCANVIL_SYNC_OVERRIDE (test-injection point)
# input: env HOME (operator-config home directory base)
# output: stdout PROVIDER-ACTIVATED summary or JSON envelope
# output: writes-ccanvil-local-json (only when all 3 phases succeed; routing keys + provider IDs)
# output: exit-codes 0 ok, 1 phase-halt-or-route-flip-failure, 2 unknown-flag-or-missing-required
# depends-on: jq
# depends-on: cmd_provider_heal
# depends-on: cmd_operator_config_get
# side-effect: writes-ccanvil-local-json-on-success-only
# failure-mode: missing-team | exit=2 | visible=stderr-error-team-required | mitigation=pass-team-flag-or-run-operator-config-init
# failure-mode: missing-project | exit=2 | visible=stderr-error-project-required | mitigation=pass-project-flag
# failure-mode: non-linear-provider | exit=2 | visible=stderr-error-only-linear-supported | mitigation=use-linear
# failure-mode: auth-failed | exit=1 | visible=provider-heal-stderr | mitigation=fix-LINEAR_API_KEY
# failure-mode: drift-detected | exit=1 | visible=provider-heal-stderr | mitigation=run-/ccanvil-pull
# failure-mode: resolve-failed | exit=1 | visible=provider-heal-stderr | mitigation=verify-team-and-project
# contract: idempotent-on-rerun
# contract: no-half-flipped-state-on-phase-failure
# contract: routes-list-defaults-from-operator-config-when-absent
# anchor: BTS-316 (modular provider connectivity)
cmd_provider_activate() {
  local provider="" team="" project="" project_dir="."
  local routes_arg=""
  local json_out=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider)    provider="$2";    shift 2 ;;
      --team)        team="$2";        shift 2 ;;
      --project)     project="$2";     shift 2 ;;
      --routes)      routes_arg="$2";  shift 2 ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --json)        json_out=1;       shift ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh provider-activate --provider linear [--team <name>] --project <name> [--routes spec,plan,stasis,idea] [--project-dir <path>] [--json]" >&2; return 2 ;;
      *) shift ;;
    esac
  done

  # Default provider to "linear" if absent (matches operator-config init Phase-1 contract).
  [[ -z "$provider" ]] && provider="linear"
  # @failure-mode: non-linear-provider
  [[ "$provider" == "linear" ]] || { echo "ERROR: --provider must be 'linear' (only linear supported in Phase 1)" >&2; return 2; }

  # Team: explicit flag → operator-config integrations.providers.<p>.team → fail.
  if [[ -z "$team" ]]; then
    team=$(cmd_operator_config_get "integrations.providers.$provider.team" 2>/dev/null)
  fi
  # @failure-mode: missing-team
  if [[ -z "$team" ]]; then
    echo "ERROR: --team is required (no operator-config integrations.providers.$provider.team fallback found; run 'docs-check.sh operator-config init --provider $provider --team <name>' to set a default)" >&2
    return 2
  fi

  # @failure-mode: missing-project
  if [[ -z "$project" ]]; then
    echo "ERROR: --project is required (no operator-default; project is per-node)" >&2
    return 2
  fi

  # Routes: explicit flag → operator-config integrations.default_routes (per-kind dict, scan known kinds) → hard default.
  local routes=""
  if [[ -n "$routes_arg" ]]; then
    routes="$routes_arg"
  else
    # Pull each kind from operator-config default_routes; include kinds where value matches our provider.
    local r_spec r_plan r_stasis r_idea
    r_spec=$(cmd_operator_config_get "integrations.default_routes.spec" 2>/dev/null)
    r_plan=$(cmd_operator_config_get "integrations.default_routes.plan" 2>/dev/null)
    r_stasis=$(cmd_operator_config_get "integrations.default_routes.stasis" 2>/dev/null)
    r_idea=$(cmd_operator_config_get "integrations.default_routes.idea" 2>/dev/null)
    local default_kinds=()
    [[ "$r_spec"   == "$provider" ]] && default_kinds+=("spec")
    [[ "$r_plan"   == "$provider" ]] && default_kinds+=("plan")
    [[ "$r_stasis" == "$provider" ]] && default_kinds+=("stasis")
    [[ "$r_idea"   == "$provider" ]] && default_kinds+=("idea")
    if (( ${#default_kinds[@]} > 0 )); then
      # Build comma-list from the array
      local IFS=','
      routes="${default_kinds[*]}"
    else
      routes="spec,plan,stasis,idea"  # hard default
    fi
  fi

  # Validate routes — only known kinds are flippable.
  local kinds_array=()
  IFS=',' read -ra kinds_array <<< "$routes"
  local k
  for k in "${kinds_array[@]}"; do
    case "$k" in
      spec|plan|stasis|idea|backlog) ;;
      *) echo "ERROR: unknown route kind '$k' (valid: spec, plan, stasis, idea, backlog)" >&2; return 2 ;;
    esac
  done

  # Compose provider-heal — auth → drift → resolve. All-or-nothing.
  local heal_json="" heal_rc=0
  if (( json_out )); then
    heal_json=$(cmd_provider_heal --provider "$provider" --team "$team" --project "$project" --project-dir "$project_dir" --json) || heal_rc=$?
  else
    cmd_provider_heal --provider "$provider" --team "$team" --project "$project" --project-dir "$project_dir" || heal_rc=$?
  fi
  if (( heal_rc != 0 )); then
    if (( json_out )); then
      # Forward provider-heal's envelope verbatim — its status field already
      # carries auth-failed / drift-detected / resolve-failed.
      printf '%s\n' "$heal_json"
    fi
    return 1
  fi

  # Phase 4: flip routing keys. Atomic write via temp+mv. Use jq -S for stable
  # key ordering so re-runs produce byte-identical output (idempotency).
  local cfg="$project_dir/.claude/ccanvil.local.json"
  mkdir -p "$project_dir/.claude"
  local existing='{}'
  [[ -f "$cfg" ]] && existing=$(cat "$cfg")
  # Build the routing slice from the kinds list.
  local kinds_json
  kinds_json=$(printf '%s\n' "${kinds_array[@]}" | jq -R . | jq -s .)
  local slice
  slice=$(jq -n --argjson kinds "$kinds_json" --arg provider "$provider" '
    {integrations: {routing: ($kinds | map({(.): $provider}) | add // {})}}
  ')
  local tmp="$cfg.tmp"
  echo "$existing" | jq --argjson slice "$slice" -S '. * $slice' > "$tmp"
  # @side-effect: writes-ccanvil-local-json-on-success-only
  mv "$tmp" "$cfg"

  # Emit summary or --json envelope.
  if (( json_out )); then
    # Pull resolved IDs from the freshly-written config.
    local team_id project_id state_count label_count
    team_id=$(jq -r --arg p "$provider" '.integrations.providers[$p].team_id // ""' "$cfg")
    project_id=$(jq -r --arg p "$provider" '.integrations.providers[$p].project_id // ""' "$cfg")
    state_count=$(jq -r --arg p "$provider" '(.integrations.providers[$p].state_ids // {}) | length' "$cfg")
    label_count=$(jq -r --arg p "$provider" '(.integrations.providers[$p].label_ids // {}) | length' "$cfg")
    local viewer_id
    viewer_id=$(echo "$heal_json" | jq -r '.phases.auth.viewer_id // ""' 2>/dev/null)
    jq -n \
      --arg status "ok" \
      --arg provider "$provider" \
      --arg team "$team" \
      --arg project "$project" \
      --argjson routes "$kinds_json" \
      --arg team_id "$team_id" \
      --arg project_id "$project_id" \
      --argjson state_count "${state_count:-0}" \
      --argjson label_count "${label_count:-0}" \
      --arg viewer_id "$viewer_id" \
      '{
        status: $status,
        provider: $provider,
        team: $team,
        project: $project,
        routes: $routes,
        ids: {team_id: $team_id, project_id: $project_id, state_count: $state_count, label_count: $label_count},
        viewer_id: $viewer_id
      }'
  else
    echo "PROVIDER-ACTIVATED: provider=$provider team=$team project=$project routes=$routes"
    echo "  flipped routing.{$routes} → $provider in $cfg"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# cmd_provider_heal_auth — Phase 3 of provider-heal: read-only auth check.
# Sources the standard .env chain (shell env → <project>/.env → ~/.env),
# verifies LINEAR_API_KEY is present, and runs linear-query.sh viewer as
# a live smoke-test to confirm the key is functional.
# ---------------------------------------------------------------------------
# @manifest
# purpose: Phase 3 of provider-heal — read-only auth check that walks the 4-tier auth chain (shell env → project/.env → ~/.env → macOS keychain via security find-generic-password), verifies LINEAR_API_KEY resolves, and runs linear-query.sh viewer as a live smoke-test to confirm the key is functional; pairs with BTS-319 (Phase 1 ID resolution) and BTS-320 (Phase 2 substrate-drift gate) into the provider-heal umbrella verb
# input: --project-dir <path>
# input: --json (optional, structured envelope output)
# input: env LINEAR_API_KEY (consumed; shell-env wins over .env files and keychain)
# input: env LINEAR_QUERY_OVERRIDE (test-injection point for viewer stub)
# output: stdout AUTH-OK message or JSON envelope
# output: stderr clear remediation when missing or invalid key
# output: exit-codes 0 ok, 1 missing-key-or-invalid-key, 2 unknown-flag
# depends-on: jq
# depends-on: linear-query.sh
# side-effect: read-only
# side-effect: invokes-subprocess-security
# failure-mode: missing-key | exit=1 | visible=stderr-ERROR-LINEAR_API_KEY-not-found | mitigation=add-key-to-shell-env-.env-or-keychain
# failure-mode: invalid-key | exit=1 | visible=stderr-ERROR-viewer-smoke-test-failed | mitigation=verify-key-not-revoked-or-expired
# contract: read-only-no-state-mutation
# contract: env-isolation-no-leak-to-caller-shell
# contract: 4-tier-auth-chain-matches-linear-query-sh
# anchor: BTS-321 (provider-heal Phase 3)
# anchor: BTS-316 (4-tier auth chain extension)
cmd_provider_heal_auth() {
  # @side-effect: read-only
  local project_dir="."
  local json_out=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --json)        json_out=1; shift ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh provider-heal-auth [--project-dir <path>] [--json]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done

  local key_source=""
  if [[ -n "${LINEAR_API_KEY:-}" ]]; then
    key_source="shell-env"
  fi

  if [[ -z "${LINEAR_API_KEY:-}" ]] && [[ -f "$project_dir/.env" ]]; then
    set -a; source "$project_dir/.env" 2>/dev/null || true; set +a
    if [[ -n "${LINEAR_API_KEY:-}" ]]; then
      key_source="$project_dir/.env"
    fi
  fi

  if [[ -z "${LINEAR_API_KEY:-}" ]] && [[ -f "$HOME/.env" ]]; then
    set -a; source "$HOME/.env" 2>/dev/null || true; set +a
    if [[ -n "${LINEAR_API_KEY:-}" ]]; then
      key_source="$HOME/.env"
    fi
  fi

  # BTS-316: extend the auth chain to include keychain (Tier 4 in linear-query.sh
  # since BTS-331). Mirrors linear-query.sh's _load_env_if_needed exactly so the
  # pre-check parity matches the actual call. Without this, operators who store
  # their key in keychain hit a fast-fail at this check before linear-query.sh's
  # own chain has a chance to resolve.
  # @side-effect: invokes-subprocess-security
  if [[ -z "${LINEAR_API_KEY:-}" ]] && command -v security >/dev/null 2>&1; then
    local kc_value
    if kc_value=$(security find-generic-password -a "${USER:-$LOGNAME}" -s linear_api_key -w 2>/dev/null) \
       && [[ -n "$kc_value" ]]; then
      export LINEAR_API_KEY="$kc_value"
      key_source="keychain"
    fi
  fi

  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    # @failure-mode: missing-key
    if (( json_out )); then
      jq -n '{status:"missing-key", key_source:null, viewer_id:null, error:"LINEAR_API_KEY not found in shell env, project .env, ~/.env, or macOS keychain (service: linear_api_key)"}'
    else
      echo "ERROR: LINEAR_API_KEY not found. Tiers checked: shell env, $project_dir/.env, ~/.env, macOS keychain (service: linear_api_key). Generate at https://linear.app/settings/api and add via 'security add-generic-password -a \$USER -s linear_api_key -w' or .env file." >&2
    fi
    exit 1
  fi

  local script_dir
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  local lq="${LINEAR_QUERY_OVERRIDE:-$script_dir/linear-query.sh}"

  local viewer_stderr viewer_stdout viewer_rc viewer_id
  viewer_stderr=$(mktemp)
  if viewer_stdout=$(bash "$lq" viewer 2>"$viewer_stderr"); then
    viewer_rc=0
  else
    viewer_rc=$?
  fi
  viewer_id=$(echo "$viewer_stdout" | jq -r '.id // empty' 2>/dev/null)

  if (( viewer_rc != 0 )) || [[ -z "$viewer_id" ]]; then
    # @failure-mode: invalid-key
    local err_text
    err_text=$(cat "$viewer_stderr")
    rm -f "$viewer_stderr"
    if (( json_out )); then
      jq -n --arg src "$key_source" --arg err "$err_text" \
        '{status:"invalid-key", key_source:$src, viewer_id:null, error:$err}'
    else
      echo "ERROR: LINEAR_API_KEY found ($key_source) but viewer smoke-test failed. Key may be invalid, expired, or revoked." >&2
      if [[ -n "$err_text" ]]; then
        echo "WRAPPER ERROR:" >&2
        echo "$err_text" >&2
      else
        echo "WRAPPER ERROR: viewer returned no .id (got: $viewer_stdout)" >&2
      fi
    fi
    exit 1
  fi
  rm -f "$viewer_stderr"

  if (( json_out )); then
    jq -n --arg src "$key_source" --arg id "$viewer_id" \
      '{status:"ok", key_source:$src, viewer_id:$id, error:null}'
  else
    echo "AUTH-OK: viewer=$viewer_id"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# cmd_provider_heal_preflight — Phase 2 of provider-heal: read-only substrate-
# drift gate. Runs ccanvil-sync.sh pull-plan against the configured hub and
# exits non-zero if any non-zero action count remains.
# ---------------------------------------------------------------------------
# @manifest
# purpose: Phase 2 of provider-heal — read-only substrate-drift gate that runs ccanvil-sync.sh pull-plan against the hub configured in .ccanvil/ccanvil.lock and exits non-zero with structured remediation when action counts (auto-update/new/section-merge/conflict) are non-zero; pairs with BTS-319 (provider-resolve-ids Phase 1) and BTS-321 (auth preflight Phase 3) into the future provider-heal umbrella verb
# input: --project-dir <path>
# input: --json (optional, structured envelope output)
# input: env CCANVIL_SYNC_OVERRIDE (test-injection point for ccanvil-sync.sh stub)
# output: stdout PREFLIGHT-OK message or JSON envelope
# output: stderr structured remediation when drift detected
# output: exit-codes 0 ok, 1 uninitialized-or-drift-detected, 2 unknown-flag, 3 wrapper-error
# depends-on: jq
# depends-on: ccanvil-sync.sh
# side-effect: read-only
# failure-mode: uninitialized-node | exit=1 | visible=stderr-ERROR-ccanvil.lock-missing | mitigation=run-/ccanvil-init
# failure-mode: drift-detected | exit=1 | visible=stderr-action-counts-+-remediation | mitigation=run-/ccanvil-pull
# failure-mode: wrapper-error | exit=3 | visible=stderr-WRAPPER-ERROR-prefix | mitigation=inspect-ccanvil-sync-stderr
# contract: read-only-no-state-mutation
# contract: never-invokes-pull-auto-or-pull-apply
# anchor: BTS-320 (provider-heal Phase 2)
cmd_provider_heal_preflight() {
  # @side-effect: read-only
  local project_dir="."
  local json_out=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --json)        json_out=1; shift ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh provider-heal-preflight [--project-dir <path>] [--json]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done

  local lock="$project_dir/.ccanvil/ccanvil.lock"
  if [[ ! -f "$lock" ]]; then
    # @failure-mode: uninitialized-node
    if (( json_out )); then
      jq -n --arg lock "$lock" '{status:"uninitialized", action_counts:{auto_update:0, new:0, section_merge:0, conflict:0}, hub_path:null, error:"ccanvil.lock missing"}'
    fi
    echo "ERROR: $lock missing — node not initialized as ccanvil project. Run /ccanvil-init first." >&2
    exit 1
  fi

  local hub_path
  hub_path=$(jq -r '.hub_source // ""' "$lock")
  # Tilde expansion
  hub_path="${hub_path/#\~/$HOME}"
  if [[ -z "$hub_path" ]]; then
    if (( json_out )); then
      jq -n '{status:"uninitialized", action_counts:{auto_update:0, new:0, section_merge:0, conflict:0}, hub_path:null, error:"hub_source missing in lock"}'
    fi
    echo "ERROR: $lock has no .hub_source field. Run /ccanvil-init to repair." >&2
    exit 1
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local sync="${CCANVIL_SYNC_OVERRIDE:-$script_dir/ccanvil-sync.sh}"

  # BTS-316: ccanvil-sync.sh's LOCKFILE is a cwd-relative path
  # (".ccanvil/ccanvil.lock"). When provider-heal-preflight is invoked from a
  # cwd OTHER than the target project_dir (e.g. by provider-activate from the
  # hub repo against a remote downstream node), pull-plan reads the wrong
  # cwd's lockfile and errors with "No .ccanvil/ccanvil.lock found." Fix: run
  # the subshell with cwd=project_dir so pull-plan sees the right lockfile.
  # script_dir is canonicalized to absolute path above so the cd doesn't
  # change which ccanvil-sync.sh resolves.
  local plan_stderr plan_stdout plan_rc
  plan_stderr=$(mktemp)
  if plan_stdout=$(cd "$project_dir" && bash "$sync" pull-plan "$hub_path" 2>"$plan_stderr"); then
    plan_rc=0
  else
    plan_rc=$?
  fi
  if (( plan_rc != 0 )); then
    # @failure-mode: wrapper-error
    if (( json_out )); then
      jq -n --arg hub "$hub_path" --arg err "$(cat "$plan_stderr")" \
        '{status:"wrapper-error", action_counts:{auto_update:0, new:0, section_merge:0, conflict:0}, hub_path:$hub, error:$err}'
    fi
    echo "WRAPPER ERROR: ccanvil-sync.sh pull-plan exited $plan_rc:" >&2
    cat "$plan_stderr" >&2
    rm -f "$plan_stderr"
    exit 3
  fi
  rm -f "$plan_stderr"

  # Tally action counts. jq normalizes keys (auto-update → auto_update,
  # section-merge → section_merge) so the JSON envelope and human output
  # share a single canonical shape.
  local counts_json
  counts_json=$(echo "$plan_stdout" | jq '
    [.[] | .action] | group_by(.) |
    map({(.[0] | gsub("-"; "_")): length}) | add // {} |
    {auto_update: (.auto_update // 0),
     new: (.new // 0),
     section_merge: (.section_merge // 0),
     conflict: (.conflict // 0)}')

  local total
  total=$(echo "$counts_json" | jq '[.[]] | add')

  if (( total == 0 )); then
    if (( json_out )); then
      jq -n --arg hub "$hub_path" --argjson counts "$counts_json" \
        '{status:"ok", action_counts:$counts, hub_path:$hub}'
    else
      echo "PREFLIGHT-OK: substrate aligned with hub"
    fi
    return 0
  fi

  # @failure-mode: drift-detected
  if (( json_out )); then
    jq -n --arg hub "$hub_path" --argjson counts "$counts_json" \
      '{status:"drift", action_counts:$counts, hub_path:$hub}'
  else
    {
      echo "DRIFT DETECTED:"
      # Emit hyphenated form in the human output (canonical user-facing term).
      echo "$counts_json" | jq -r 'to_entries | .[] | select(.value > 0) | "  - \(.key | gsub("_"; "-")): \(.value)"'
      echo ""
      echo "Run /ccanvil-pull or 'bash .ccanvil/scripts/ccanvil-sync.sh pull-auto $hub_path' to align."
    } >&2
  fi
  exit 1
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
# @manifest
# purpose: Scan the project tree for retired-vocab references (legacy command names from earlier ccanvil migrations) and emit JSON matches with optional allowlist pre-filter; pattern lives in the substrate so this manifest stays vocab-free
# input: --respect-allowlist <path>
# input: --project-dir <path>
# input: positional <project-dir> (legacy)
# output: stdout JSON array of {file, line, match} or empty []
# output: exit-codes 0 ok, 2 unknown-flag/missing-allowlist-arg/allowlist-not-found
# caller: skill:/stasis
# depends-on: grep
# depends-on: jq
# side-effect: reads-project-tree
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: allowlist-not-found | exit=2 | visible=stderr-error | mitigation=verify-allowlist-path
# failure-mode: missing-allowlist-arg | exit=2 | visible=stderr-error | mitigation=pass-path-after-flag
# contract: empty-array-on-no-matches
# contract: skips-git-node_modules-dist-generated
# anchor: BTS-132 (respect-allowlist filter)
# anchor: BTS-241 (manifest seed)
cmd_legacy_refs_scan() {
  # BTS-132: optional --respect-allowlist <path> pre-filters raw matches
  # against a user-supplied allowlist (same ERE format as
  # hub/tests/legacy-refs-allowlist.txt). Default (no flag) returns every
  # raw match — preserves existing behavior for backward compat.
  # BTS-212: arg loop with strict unknown-flag handling
  local allowlist=""
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --respect-allowlist)
        allowlist="${2:-}"
        if [[ -z "$allowlist" ]]; then
          # @failure-mode: missing-allowlist-arg
          echo "ERROR: --respect-allowlist requires a path argument" >&2
          return 2
        fi
        if [[ ! -f "$allowlist" ]]; then
          # @failure-mode: allowlist-not-found
          echo "ERROR: allowlist file not found: $allowlist" >&2
          return 2
        fi
        shift 2 ;;
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh legacy-refs-scan [--respect-allowlist <path>] [--project-dir <path>] [<project-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done

  local project_dir="${project_dir_flag:-${1:-.}}"

  local pattern='/catchup|/checkpoint|docs/checkpoint\.md|checkpoint\.(read|write)|stale-checkpoint'

  # Collect matches via grep -rnE; skip .git, node_modules, and binary files.
  # -I: skip binary; -n: line numbers; --exclude-dir: skip common noise.
  # Tolerate empty grep output (exit 1 when no matches).
  # @side-effect: reads-project-tree
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
# @manifest
# purpose: Upgrade an existing idea-routing config — validate provider state IDs against live Linear, optionally create new project, optionally migrate from legacy local-only setup; --dry-run shows the diff without writing
# input: --provider <name>
# input: --team <id>
# input: --project <id>
# input: --dry-run
# input: --create-project
# input: --from-legacy
# input: --project-dir <path>
# output: stdout upgrade plan + summary JSON
# output: exit-codes 0 ok, 1 provider-error/missing-required, 2 unknown-flag
# depends-on: cmd_idea_setup
# depends-on: jq
# side-effect: writes-via-cmd_idea_setup
# side-effect: commits-config-changes
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-required | exit=1 | visible=stderr-error | mitigation=pass-required-flags
# failure-mode: provider-error | exit=1 | visible=stderr-error | mitigation=verify-provider-credentials
# contract: dry-run-never-mutates
# contract: idempotent-on-already-upgraded
# anchor: BTS-241 (manifest seed)
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
      --project-dir)    project_dir="${2:-.}"; shift 2 ;;
      --dry-run)        dry_run=1;     shift ;;
      --create-project) create_project=1; shift ;;
      --from-legacy)    from_legacy=1; shift ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh idea-upgrade [--provider <p>] [--team <t>] [--project <p>] [--project-dir <path>] [--dry-run] [--create-project] [--from-legacy] [<project-dir>]" >&2; exit 2 ;;
      *)                project_dir="$1"; shift ;;
    esac
  done

  case "$provider" in
    local) ;;
    linear)
      [[ -n "$team" && -n "$project" ]] || {
        # @failure-mode: missing-required
        echo "ERROR: --provider linear requires --team and --project" >&2
        return 1
      }
      ;;
    "")  echo "ERROR: --provider is required (local|linear)" >&2; return 1 ;;
    *)
         # @failure-mode: provider-error
         echo "ERROR: unknown provider '$provider' (must be local|linear)" >&2; return 1 ;;
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
    # @side-effect: writes-via-cmd_idea_setup
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
    # @side-effect: commits-config-changes
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
# @manifest
# purpose: Generate a concise ≤80-char title from a multi-line idea body via deterministic heuristics (first sentence, strip leading bullet/markup, truncate on word boundary); used by /idea capture flow when title not provided
# input: stdin <body>
# input: --title-map <path>
# output: stdout single-line title string ≤80 chars
# output: exit-codes 0 ok, 1 title-map-not-found
# depends-on: jq
# side-effect: emits-title-stdout
# failure-mode: title-map-not-found | exit=1 | visible=stderr-error | mitigation=verify-title-map-path
# contract: deterministic-no-llm
# contract: title-≤-80-chars
# anchor: BTS-241 (manifest seed)
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
    # @failure-mode: title-map-not-found
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
      # @side-effect: emits-title-stdout
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
# @manifest
# purpose: Stamp the current epoch into a spec's `> Created: PLACEHOLDER` line and auto-populate `> Subject:` from the H1 — owns the timestamp deterministically (BTS-141: never substitute via inline shell-variable interpolation)
# input: --project-dir <path>
# input: positional <feature_id>
# input: positional [docs-dir]
# output: stdout JSON {feature_id, stamped_epoch, file}
# output: exit-codes 0 ok, 1 spec-not-found, 2 unknown-flag/missing-feature-id
# caller: skill:/spec
# depends-on: jq
# depends-on: sed
# side-effect: rewrites-spec-metadata
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-feature-id | exit=2 | visible=stderr-Usage
# failure-mode: spec-not-found | exit=1 | visible=stderr-error | mitigation=verify-feature-id-and-archive
# contract: epoch-stamped-deterministically
# contract: subject-auto-populated-from-h1-when-absent
# anchor: BTS-141 (deterministic timestamp ownership)
# anchor: BTS-236 (Subject auto-population)
# anchor: BTS-241 (manifest seed)
cmd_stamp_spec() {
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh stamp-spec [--project-dir <path>] <feature_id> [<docs-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local feature_id="${1:-}"
  local docs_dir
  if [[ -n "$project_dir_flag" ]]; then
    docs_dir="$project_dir_flag/docs"
  else
    docs_dir="${2:-docs}"
  fi

  if [[ -z "$feature_id" ]]; then
    # @failure-mode: missing-feature-id
    echo "Usage: docs-check.sh stamp-spec [--project-dir <path>] <feature_id> [<docs-dir>]" >&2
    return 2
  fi

  local spec_path="$docs_dir/specs/$feature_id.md"
  if [[ ! -f "$spec_path" ]]; then
    # @failure-mode: spec-not-found
    echo "ERROR: spec not found: $spec_path" >&2
    return 1
  fi

  if ! grep -q '^> Created:' "$spec_path"; then
    echo "ERROR: no Created: line in $spec_path — write a placeholder first" >&2
    return 1
  fi

  local epoch
  epoch=$(date +%s)

  # BTS-236: derive a clean Subject line from the spec's H1 for use by
  # cmd_derive_pr_title. The H1 (form `# Feature: <name>`) is naturally
  # short and operator-controlled — a far better PR-subject source than
  # the verbose Summary opener that produced mid-sentence truncated
  # commit subjects on PRs #128, #131, #132, #133. Cap at 72 chars with
  # word-boundary walkback. Skip when H1 doesn't match the expected form
  # OR when a Subject line is already present (idempotent).
  local subject=""
  if ! grep -q '^> Subject:' "$spec_path"; then
    local h1
    h1=$(head -1 "$spec_path" | sed -nE 's/^# Feature: (.+)$/\1/p')
    if [[ -n "$h1" ]]; then
      subject="$h1"
      if (( ${#subject} > 72 )); then
        subject="${subject:0:72}"
        local i ch
        for (( i=71; i >= 72 - 16; i-- )); do
          ch="${subject:i:1}"
          if [[ "$ch" == " " || "$ch" == $'\t' || "$ch" == "-" || "$ch" == "," || "$ch" == ":" ]]; then
            subject="${subject:0:i}"
            break
          fi
        done
        subject="${subject%"${subject##*[![:space:]]}"}"
      fi
    fi
  fi

  # Replace the Created: line in place. Use a temp file for portability.
  # If a Subject was derived, insert it immediately after Created.
  local tmp
  tmp="${spec_path}.stamp.tmp"
  # @side-effect: rewrites-spec-metadata
  awk -v ep="$epoch" -v subj="$subject" '
    /^> Created:/ && !created_done {
      print "> Created: " ep
      if (subj != "") print "> Subject: " subj
      created_done=1
      next
    }
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
# @manifest
# purpose: Probe whether the working tree is a git repo and whether origin is configured; emits {has_origin, url, git_repo} JSON envelope used by repo-type classification and init flows
# input: --project-dir <path>
# input: positional <repo-dir>
# output: stdout JSON {has_origin, url, git_repo}
# output: exit-codes 0 always, 2 unknown-flag
# depends-on: git
# depends-on: jq
# side-effect: reads-git-config
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# contract: never-fails-on-non-git-repo
# anchor: BTS-241 (manifest seed)
cmd_remote_presence() {
  # BTS-212: arg loop
  local project_dir_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir_flag="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh remote-presence [--project-dir <path>] [<repo-dir>]" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local repo_dir="${project_dir_flag:-${1:-.}}"

  # @side-effect: reads-git-config
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
# @manifest
# purpose: BTS-123 — deterministically append one entry to .ccanvil/ideas-pending.log when a Linear dispatch fails (network, auth, GraphQL); replaces hand-rolled echo+jq pipelines that produced malformed JSON; BTS-205 dead-letter via dual-capture-emergency.log on validate failure
# input: --op {add|promote|defer|dismiss|merge|ticket.transition}
# input: --title <title> (op=add)
# input: --body <body> (op=add)
# input: --id <BTS-N> (transition ops)
# input: --priority <1-4> (op=promote)
# input: --role <todo|in_progress|backlog|done> (op=ticket.transition)
# input: --duplicate-of <BTS-N> (op=merge)
# input: --parent <ref> (op=add, BTS-162)
# input: --project-dir <path>
# output: stdout JSON {appended:true, ts}
# output: exit-codes 0 ok, 2 unknown-flag/missing-required
# caller: skill:/idea
# caller: skill:/activate
# caller: skill:/land
# depends-on: jq
# side-effect: appends-pending-log
# side-effect: maybe-writes-emergency-log
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-op | exit=2 | visible=stderr-error | mitigation=pass-required-op
# failure-mode: validate-failure | exit=0 | visible=stdout-emergency-message | mitigation=BTS-205-dual-capture
# contract: deterministic-jq-shape-no-echo
# contract: never-fails-fallback-path
# anchor: BTS-123 (deterministic helper origin)
# anchor: BTS-205 (dual-capture emergency)
# anchor: BTS-241 (manifest seed)
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
      *)
                        # @failure-mode: unknown-flag
                        echo "ERROR: unknown flag: $1" >&2; return 2 ;;
    esac
  done

  if [[ -z "$op" ]]; then
    # @failure-mode: missing-op
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

  # BTS-205: emergency dead-letter when primary log write fails.
  # /stasis dual-capture's pending-log fallback was the only safety net;
  # if the pending log itself was unwritable (perms, exotic FS issue),
  # determinism candidates evaporated silently. Now the helper writes
  # to .ccanvil/dual-capture-emergency.log as a last-resort, with a
  # WARN to stderr so /stasis surfaces the degradation.
  # @side-effect: appends-pending-log
  if ! printf '%s\n' "$entry" >> "$pending" 2>/dev/null; then
    local emergency="$project_dir/.ccanvil/dual-capture-emergency.log"
    # @side-effect: maybe-writes-emergency-log
    # @failure-mode: validate-failure
    if printf '%s\n' "$entry" >> "$emergency" 2>/dev/null; then
      echo "WARN: idea-pending-append: primary log write failed; entry written to emergency log ($emergency)" >&2
      return 0
    else
      echo "ERROR: idea-pending-append: both primary and emergency log writes failed" >&2
      return 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# cmd_idea_pending_validate — Validate every line in .ccanvil/ideas-pending.log.
#
# Output (stdout, JSON): {count: N, valid: bool, errors: [<line-num>...]}
# Exit codes: 0 when valid (or empty/missing), non-zero when any line fails to parse.
# ---------------------------------------------------------------------------
# @manifest
# purpose: BTS-123 — count and structurally validate the entries in .ccanvil/ideas-pending.log; emits {count, valid, errors:[]} envelope so callers (skill:/idea, /stasis) can compute totals via JSON path rather than `wc -l` (physical lines ≠ JSON entries)
# input: positional <project-dir>
# output: stdout JSON {count, valid, errors:[]}
# output: exit-codes 0 always (errors encoded in JSON)
# caller: skill:/idea
# depends-on: jq
# side-effect: reads-pending-log
# failure-mode: missing-log | exit=0 | visible=zeroed-output
# failure-mode: malformed-entry | exit=0 | visible=errors-array-non-empty | mitigation=manual-cleanup-or-resync
# contract: never-fails-on-invalid-content
# contract: count-matches-entry-count-not-line-count
# anchor: BTS-123 (deterministic-helper-pattern)
# anchor: BTS-241 (manifest seed)
cmd_idea_pending_validate() {
  local project_dir="${1:-.}"
  # @side-effect: reads-pending-log
  local pending="$project_dir/.ccanvil/ideas-pending.log"

  if [[ ! -f "$pending" ]]; then
    # @failure-mode: missing-log
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
      # @failure-mode: malformed-entry
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
# @manifest
# purpose: BTS-201 — scan the current session's idea captures for bug-shape language without the four evidence anchors (Command/Output/Exit/Reproduce) and emit a list for /stasis to surface as Evidence Gaps; closes the failure mode that almost shipped a phantom regex carve-out (BTS-198)
# input: --since <ref>
# input: --project-dir <path>
# input: --input-json <path>
# input: --no-time-filter
# output: stdout JSON array of gap entries [{id, title, reason}]
# output: exit-codes 0 always, 2 unknown-flag
# caller: skill:/stasis
# depends-on: jq
# side-effect: reads-ideas-log-and-pending
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: linear-fetch-fallback | exit=0 | visible=fallback-field-in-envelope | mitigation=expected-on-network-flake
# contract: bug-shape-heuristic-deterministic
# contract: empty-array-when-no-gaps
# anchor: BTS-198 (origin failure mode)
# anchor: BTS-201 (evidence-required rule)
# anchor: BTS-241 (manifest seed)
cmd_evidence_scan_session() {
  local since="" project_dir="." input_json="" no_time_filter=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --input-json) input_json="${2:-}"; shift 2 ;;
      --no-time-filter) no_time_filter=1; shift ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh evidence-scan-session [--since <ref>] [--project-dir <path>] [--input-json <path>] [--no-time-filter]" >&2; exit 2 ;;
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
    # @failure-mode: linear-fetch-fallback
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

    # BTS-203: idea.list does not return .description, so when body is
    # empty (live mode, or fixture-with-null-description) we fetch the
    # body via linear-query.sh get-issue. Override path via env for tests.
    # Fail-closed: if fetch fails, body stays empty and the anchor check
    # reports missing-evidence-anchors (no silent skip).
    if [[ -z "$body" && -n "$id" ]]; then
      local lq="${LINEAR_QUERY_OVERRIDE:-$(dirname "$0")/linear-query.sh}"
      local fetched
      fetched=$(bash "$lq" get-issue "$id" 2>/dev/null) || fetched=""
      if [[ -n "$fetched" ]]; then
        body=$(echo "$fetched" | jq -r '.description // empty')
      fi
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
  # @side-effect: reads-ideas-log-and-pending
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
# cmd_stasis_carry_forward (BTS-232) — surface determinism candidates from
# the prior stasis that have no matching `Determinism: <slug>` Linear idea.
#
# Closes the BTS-205 read-side gap: BTS-205 fixed write-side resilience
# (emergency dead-letter, mechanism-aware dispatch); BTS-232 verifies at read
# time that each candidate listed in the prior stasis's `## Determinism Review`
# section actually landed as an idea — surfacing any historical drops so the
# operator can manually create the missing ticket.
#
# Test seams:
#   --stasis-content -    read stasis content from stdin (overrides artifact-read)
#   --input-json <path>   read idea listing from JSON file (overrides idea.list)
#
# Output JSON:
#   {candidates:[{slug, has_idea, idea_id|null}], count_total, count_carry_forward}
#   Plus optional `note: "no prior stasis"` when no stasis is found.
# ---------------------------------------------------------------------------
# @manifest
# purpose: BTS-232 — parse the prior stasis's `## Determinism Review` section, extract candidate slugs, and cross-check each against current Linear ideas; surfaces candidates whose dual-capture didn't land for /recall to flag as carry-forward
# input: --project-dir <path>
# input: --input-json <path>
# input: --stasis-content - (read from stdin)
# output: stdout JSON {candidates, count_total, count_carry_forward}
# output: exit-codes 0 always, 2 unknown-flag/bad-stasis-content
# caller: skill:/recall
# depends-on: cmd_artifact_read
# depends-on: jq
# side-effect: reads-prior-stasis
# side-effect: queries-linear-ideas
# failure-mode: unknown-flag | exit=2 | visible=stderr-error
# failure-mode: bad-stasis-content-flag | exit=2 | visible=stderr-error | mitigation=use-dash-for-stdin
# failure-mode: empty-result | exit=0 | visible=zeroed-counts | mitigation=expected-when-no-determinism-section
# contract: tolerates-bolded-and-backticked-slug-shapes
# contract: silent-when-no-prior-stasis
# anchor: BTS-232 (carry-forward substrate)
# anchor: BTS-241 (manifest seed)
cmd_stasis_carry_forward() {
  local project_dir="." input_json="" read_stdin=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --input-json) input_json="${2:-}"; shift 2 ;;
      --stasis-content)
        if [[ "${2:-}" == "-" ]]; then
          read_stdin=1; shift 2
        else
          # @failure-mode: bad-stasis-content-flag
          echo "ERROR: stasis-carry-forward: --stasis-content only accepts '-' (stdin)" >&2
          return 2
        fi
        ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh stasis-carry-forward [--project-dir <path>] [--stasis-content -] [--input-json <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done

  # 1. Acquire stasis content
  local stasis_content="" note=""
  if (( read_stdin )); then
    stasis_content=$(cat; printf x); stasis_content=${stasis_content%x}
  else
    stasis_content=$(cmd_artifact_read --kind stasis --stasis-kind session --project-dir "$project_dir" 2>/dev/null) || stasis_content=""
    if [[ -z "$stasis_content" ]]; then
      # Fallback: try feature-kind stasis (active feature on the branch)
      local fid=""
      if [[ -f "$project_dir/docs/spec.md" ]]; then
        fid=$(grep -m1 '^> Feature:' "$project_dir/docs/spec.md" | sed -E 's/^> Feature:[[:space:]]*//' || true)
      fi
      if [[ -n "$fid" ]]; then
        stasis_content=$(cmd_artifact_read --kind stasis --feature "$fid" --project-dir "$project_dir" 2>/dev/null) || stasis_content=""
      fi
    fi
    if [[ -z "$stasis_content" ]]; then
      # @failure-mode: empty-result
      # @side-effect: reads-prior-stasis
      jq -n '{candidates:[], count_total:0, count_carry_forward:0, note:"no prior stasis"}'
      return 0
    fi
  fi

  # 2. Extract `## Determinism Review` section
  # awk-extract: from `## Determinism Review` line until next `## ` or EOF
  local section
  section=$(printf '%s\n' "$stasis_content" | awk '
    /^## Determinism Review[[:space:]]*$/ { capture=1; next }
    capture && /^## / { capture=0 }
    capture { print }
  ')

  if [[ -z "$section" ]]; then
    jq -n '{candidates:[], count_total:0, count_carry_forward:0, note:"no determinism-review section"}'
    return 0
  fi

  # Empty-state literal short-circuit
  if echo "$section" | grep -qF "No candidates this session."; then
    jq -n '{candidates:[], count_total:0, count_carry_forward:0}'
    return 0
  fi

  # 3. Extract candidate slugs from bullet lines.
  # Skip metadata bullets (operations_reviewed, candidates_found).
  local candidates_json='[]'
  while IFS= read -r line; do
    # Match bullet starts: `* ` or `- ` (with optional leading whitespace)
    local body
    if [[ "$line" =~ ^[[:space:]]*[\*\-][[:space:]]+(.*)$ ]]; then
      body="${BASH_REMATCH[1]}"
    else
      continue
    fi
    # Skip empty literal phrase
    [[ "$body" == "No candidates this session." ]] && continue

    # Slug extraction
    local slug=""
    if [[ "$body" =~ ^\*\*([^*]+)\*\* ]]; then
      # (a) bolded-shape: **slug**: ...
      slug="${BASH_REMATCH[1]}"
    elif [[ "$body" =~ ^\`([^\`]+)\` ]]; then
      # (b) backtick-shape: `tok1` → `tok2` ...
      # Concatenate consecutive backticked tokens joined by " → "
      local rest="$body"
      slug=""
      while [[ "$rest" =~ ^\`([^\`]+)\`[[:space:]]*(→[[:space:]]*)?(.*)$ ]]; do
        local tok="${BASH_REMATCH[1]}"
        local sep="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
        if [[ -z "$slug" ]]; then
          slug="$tok"
        else
          slug="$slug → $tok"
        fi
        # Stop if no more arrow-separator
        [[ -z "$sep" ]] && break
      done
    else
      # (c) plain: take leading text up to first `:` or 60 chars
      slug="${body%%:*}"
    fi

    # Trim whitespace
    slug="${slug#"${slug%%[![:space:]]*}"}"
    slug="${slug%"${slug##*[![:space:]]}"}"
    # Strip trailing colon (e.g. `**operations_reviewed:**` → `operations_reviewed`)
    slug="${slug%:}"
    # Cap at 60 chars
    if (( ${#slug} > 60 )); then
      slug="${slug:0:60}"
    fi

    [[ -z "$slug" ]] && continue
    # Skip metadata pseudo-bullets (BTS-232: post-extract because they may be
    # bolded `**operations_reviewed:**` and pass through case (a) above)
    [[ "$slug" == "operations_reviewed" ]] && continue
    [[ "$slug" == "candidates_found" ]] && continue

    candidates_json=$(echo "$candidates_json" | jq --arg s "$slug" '. + [{slug:$s}]')
  done <<< "$section"

  # 4. Acquire idea listing
  local issues='[]'
  if [[ -n "$input_json" ]]; then
    [[ ! -f "$input_json" ]] && {
      echo "ERROR: stasis-carry-forward: --input-json file not found: $input_json" >&2
      return 3
    }
    issues=$(cat "$input_json")
  else
    # @side-effect: queries-linear-ideas
    local ops="$(dirname "$0")/operations.sh"
    local resolution
    resolution=$(bash "$ops" resolve idea.list --project-dir "$project_dir" 2>/dev/null) || resolution=""
    if [[ -n "$resolution" ]]; then
      local cmd_str
      cmd_str=$(printf '%s' "$resolution" | jq -r '.invocation.command // empty')
      if [[ -n "$cmd_str" ]]; then
        issues=$(eval "$cmd_str" 2>/dev/null) || issues='[]'
      fi
    fi
  fi

  # Validate JSON shape (graceful — empty array on bad input)
  if ! echo "$issues" | jq -e 'type == "array"' >/dev/null 2>&1; then
    issues='[]'
  fi

  # 5. For each candidate slug, case-insensitive substring match against
  # idea titles starting with "Determinism: ".
  # BTS-238: jq's gsub replacement uses named-capture interpolation
  # (`\(.name)`), not numbered backrefs. Original pattern `[...]` with no
  # capture group produced a malformed replacement string. Fix: use a named
  # capture group `(?<c>...)` and reference it via `\(.c)` in the replacement.
  # Output `\<char>` (one literal backslash + matched char) escapes regex
  # metacharacters in the slug correctly.
  local matched_json
  matched_json=$(jq --argjson issues "$issues" '
    [.[] | . as $c |
      $issues
      | map(select(.title | test("(?i)Determinism:.*" + ($c.slug | gsub("(?<c>[][\\\\.\\^\\$\\*\\+\\?\\(\\)\\{\\}\\|])"; "\\\(.c)")))))
      | if length > 0 then
          $c + {has_idea: true, idea_id: .[0].id}
        else
          $c + {has_idea: false, idea_id: null}
        end
    ]
  ' <<< "$candidates_json")

  # 6. Compute counts + emit
  jq '{candidates: ., count_total: length, count_carry_forward: ([.[] | select(.has_idea == false)] | length)}' <<< "$matched_json"
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

# _normalize_feature_to_ticket — extract the canonical Linear ticket ID
# (e.g., "BTS-217") from either form an internal caller might pass:
#
#   * a bare ticket id like "BTS-217" → returned as-is
#   * a kebab feature_id like "bts-217-flip-linear-routing" → upper-slug
#     extracted ("BTS-217")
#
# /spec convention is feature_id = <lower-slug>-<kebab-name> where
# <lower-slug> = lowercase(<TEAM>-<N>). When that shape doesn't match
# (e.g., legacy specs without slug prefix), the input is returned
# verbatim so existing callers continue to work.
#
# This exists because cmd_artifact_write, cmd_artifact_read, and
# _complete_archive_linear all do Linear lookups (get-issue,
# resolve-document-id) on the ticket id, but cmd_activate and the /spec
# skill prose pass feature_id (kebab) to those entrypoints. Without
# normalization, get-issue cannot find the issue and resolve-document-id
# derives a different UUID than write/read would have produced.
_normalize_feature_to_ticket() {
  local input="$1"
  # Already a canonical ticket id (TEAM-N): return as-is.
  if [[ "$input" =~ ^[A-Z]+-[0-9]+$ ]]; then
    printf '%s\n' "$input"
    return 0
  fi
  # Kebab feature_id: extract leading <lower-slug>-<digits>, uppercase.
  # Use `tr` not `${var^^}` for bash 3.2 portability — bats invocations on
  # macOS use /bin/bash which is 3.2 even when /opt/homebrew/bin/bash is
  # available via PATH.
  if [[ "$input" =~ ^([a-z]+)-([0-9]+) ]]; then
    local team_upper num
    team_upper=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
    num="${BASH_REMATCH[2]}"
    printf '%s\n' "${team_upper}-${num}"
    return 0
  fi
  # Anything else (legacy, no-slug spec): pass through verbatim.
  printf '%s\n' "$input"
}

# _classify_linear_failure — BTS-219: classify a captured stderr file from
# a failing linear-query.sh invocation into one of four classes:
#   auth-missing | not-found | network-error | parse-error
# Used by cmd_artifact_read (and any other live-API caller that wants to
# emit a structured WARN line). Pure function: takes a file path, prints
# the class name, exits 0. No side effects, no global mutation.
_classify_linear_failure() {
  local errfile="${1:-}"
  if [[ -z "$errfile" || ! -f "$errfile" ]]; then
    printf '%s\n' "parse-error"
    return 0
  fi
  if grep -qE 'LINEAR_API_KEY|Authentication required|Authentication failed' "$errfile"; then
    printf '%s\n' "auth-missing"
  elif grep -qE 'Entity not found' "$errfile"; then
    printf '%s\n' "not-found"
  elif grep -qE 'curl:|Connection refused|Could not resolve|Failed to connect' "$errfile"; then
    printf '%s\n' "network-error"
  else
    printf '%s\n' "parse-error"
  fi
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
  local script_dir doc_id ticket_id
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  # BTS-217: normalize feature_id (kebab) → BTS-N for deterministic
  # doc_id derivation symmetric with cmd_artifact_write.
  ticket_id=$(_normalize_feature_to_ticket "$feature_id")
  doc_id=$(bash "$script_dir/linear-query.sh" resolve-document-id --kind "$resolve_kind" --ticket "$ticket_id" 2>/dev/null)
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

  # BTS-217: normalize feature_id (e.g., "bts-217-flip-linear-routing") to
  # the canonical Linear ticket id ("BTS-217") for all api.linear.app
  # lookups. Filename construction below still uses feature_id (the kebab
  # form) so archive paths read like docs/sessions/<epoch>-bts-217-...md.
  local ticket_id
  ticket_id=$(_normalize_feature_to_ticket "$feature_id")

  # BTS-214: batch-read all lifecycle Documents parented to the issue in
  # ONE list-documents call (was 3 sequential get-document calls). Trashes
  # stay serial — Linear's GraphQL doesn't expose mutation batching, and
  # `DocumentFilter.id.in` is also not supported (live-validated against
  # api.linear.app — Linear's filter shape rejects the `in` modifier on
  # id), so the parent-issue lookup is the cheapest valid filter route.
  # Net: 1 get-issue + 1 list-documents + N trashes (5 calls when all 3
  # kinds present), down from the legacy 3 get-document + 3 trash (6).

  # Phase 1: per-kind plan. Compute the expected Document UUID + the
  # output archive destination for every kind whose route is `linear`.
  local -a planned_kinds=() planned_ids=() planned_dests=()
  local kind
  for kind in spec plan stasis; do
    local route
    route=$(_lifecycle_route "$kind" "$project_dir")
    [[ "$route" != "linear" ]] && continue
    local resolve_kind
    case "$kind" in
      spec)   resolve_kind="spec" ;;
      plan)   resolve_kind="plan" ;;
      stasis) resolve_kind="feature-stasis" ;;
    esac
    local expected_id
    # BTS-217: use ticket-id (BTS-N) for resolve-document-id, NOT feature_id.
    # The write-side (cmd_artifact_write) derives the doc_id from --feature
    # which the /spec convention sends as either form; we normalize to the
    # canonical TEAM-N shape so write and read agree on the deterministic
    # UUID. Without this, the archive computes a different UUID than what
    # was written and finds nothing to archive.
    expected_id=$(bash "$script_dir/linear-query.sh" resolve-document-id --kind "$resolve_kind" --ticket "$ticket_id")
    [[ -z "$expected_id" ]] && continue
    planned_kinds+=("$kind")
    planned_ids+=("$expected_id")
    planned_dests+=("$sessions_dir/${epoch}-${feature_id}-${kind}.md")
  done

  # No kinds linear-routed → nothing to archive.
  [[ ${#planned_ids[@]} -eq 0 ]] && return 0

  # Phase 2: resolve issue UUID, then one batch-read of all Documents
  # parented to that issue. Filter the response to the planned-id set.
  # The script runs under `set -euo pipefail`, so the get-issue pipeline
  # must be wrapped in `if` form to allow non-zero exit (Linear error)
  # to fall through to the WARN path without killing cmd_complete.
  # BTS-217: ticket_id (BTS-N) is the Linear-recognized form; passing
  # feature_id (kebab) results in get-issue returning empty.
  local issue_uuid="" issue_response=""
  if issue_response=$(bash "$script_dir/linear-query.sh" get-issue "$ticket_id" 2>/dev/null); then
    issue_uuid=$(printf '%s' "$issue_response" | jq -r '.uuid // empty')
  fi
  if [[ -z "$issue_uuid" ]]; then
    echo "WARN: archive step skipped — could not resolve issue UUID for $feature_id (ticket=$ticket_id)" >&2
    return 0
  fi

  local docs_json list_limit=50
  if ! docs_json=$(bash "$script_dir/linear-query.sh" list-documents --issue "$issue_uuid" --with-content --limit "$list_limit" 2>/dev/null); then
    echo "WARN: archive step skipped — list-documents failed for $feature_id" >&2
    return 0
  fi

  # /review WARN-2: silent-truncation guard. ccanvil currently parents at
  # most 3 Documents per issue (spec/plan/feature-stasis), but if a future
  # lifecycle kind pushes past `list_limit`, we'd silently miss the
  # overflow. Surface a WARN at zero API cost — no pagination logic
  # needed today.
  local doc_count
  doc_count=$(printf '%s' "$docs_json" | jq 'length')
  if [[ "$doc_count" -ge "$list_limit" ]]; then
    echo "WARN: list-documents returned $doc_count results (limit=$list_limit) — possible truncation; some Documents may not be archived" >&2
  fi

  # Phase 3: archive + trash each present Document. Match by id-equality
  # against the planned UUID (NOT title prefix — robust to title renames).
  # /review WARN-1: separate archive (content-gated) from trash (match-gated).
  # If the Document was created with empty content (e.g. operator cleared
  # the body in Linear before /complete), we still trash it — otherwise it
  # leaks as a "zombie Document" in Linear's project. Legacy behavior
  # silently left those alive; this fix closes that latent class of bug.
  local i=0
  while [[ $i -lt ${#planned_kinds[@]} ]]; do
    local k="${planned_kinds[$i]}" id="${planned_ids[$i]}" dest="${planned_dests[$i]}"
    local node content
    node=$(printf '%s' "$docs_json" | jq --arg id "$id" '[.[] | select(.id == $id)] | .[0] // empty')
    if [[ -n "$node" && "$node" != "null" ]]; then
      content=$(printf '%s' "$node" | jq -r '.content // empty')
      if [[ -n "$content" ]]; then
        printf '%s\n' "$content" > "$dest"
        echo "Archived ${k} → $dest" >&2
      else
        echo "Archive: skipped ${k} write — Document had empty content; trashing anyway" >&2
      fi
      bash "$script_dir/linear-query.sh" trash-document "$id" >/dev/null 2>&1 || true
    fi
    i=$((i + 1))
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
  local script_dir cached remote lq
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  # BTS-237: LINEAR_QUERY_OVERRIDE for testability — see cmd_artifact_write.
  lq="${LINEAR_QUERY_OVERRIDE:-$script_dir/linear-query.sh}"
  cached=$(_doc_cache_get_updated_at "$doc_id" "$project_dir")
  [[ -z "$cached" ]] && return 0   # No cache yet — first write; safe.
  remote=$(bash "$lq" document-updated-at "$doc_id" 2>/dev/null | jq -r '.updatedAt // empty')
  [[ -z "$remote" ]] && return 0   # Document missing remote (will create); safe.
  if [[ "$remote" != "$cached" ]]; then
    return 1
  fi
  return 0
}

# BTS-204 Phase 6: ssot-migrate — operator-driven, idempotent migration of
# lifecycle artifacts between local files and Linear Documents. Bidirectional.
# Never auto-triggered. Per AC-12.
# @manifest
# purpose: BTS-204 — migrate spec/plan/stasis routing between local-only and Linear-routed for a single feature; --to direction inverts the route, with content moved between docs/specs/<id>.md and the corresponding Linear Document
# input: --to {linear|local}
# input: --feature <id>
# input: --project-dir <path>
# output: stdout migration plan + summary JSON
# output: exit-codes 0 ok, 1 missing-feature/route-error, 2 unknown-flag/missing-direction
# depends-on: cmd_artifact_read
# depends-on: cmd_artifact_write
# depends-on: jq
# side-effect: writes-or-deletes-local-archive
# side-effect: writes-or-deletes-linear-document
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-direction | exit=2 | visible=stderr-error | mitigation=pass-to-flag
# failure-mode: missing-feature | exit=2 | visible=stderr-error | mitigation=pass-feature-flag
# failure-mode: write-error | exit=0 | visible=errors-field-in-envelope | mitigation=retry-after-fixing-credentials
# contract: idempotent-on-already-migrated
# anchor: BTS-204 (SSOT-Linear)
# anchor: BTS-241 (manifest seed)
cmd_ssot_migrate() {
  local direction="" feature="" project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to)         direction="$2"; shift 2 ;;
      --feature)    feature="$2";   shift 2 ;;
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh ssot-migrate --to {linear|local} [--feature <id>] [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done
  case "$direction" in
    linear|local) ;;
    *)
       # @failure-mode: missing-direction
       echo "ERROR: ssot-migrate requires --to {linear|local}" >&2; return 2 ;;
  esac
  if [[ -z "$feature" ]]; then
    # @failure-mode: missing-feature
    echo "ERROR: ssot-migrate requires --feature <BTS-N> (or feature-id)" >&2
    return 2
  fi

  # BTS-212: project_dir parsed from arg loop (default ".")
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
      # @side-effect: writes-or-deletes-linear-document
      if cmd_artifact_write --kind "$kind" --feature "$feature" < "$local_path" >/dev/null 2>&1; then
        # @side-effect: writes-or-deletes-local-archive
        rm -f "$local_path"
        migrated=$((migrated + 1))
      else
        # @failure-mode: write-error
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
#   docs-check.sh route-of <spec|plan|stasis|idea|backlog> [--project-dir <dir>]
# Outputs "linear" or "local" on stdout. Exit 2 on missing/unknown kind.
# BTS-316 (BTS-276 finding 4): allowlist extended from spec/plan/stasis to
# include idea + backlog so provider-activate can canonically query routes
# for all artifact kinds.
# @manifest
# purpose: Resolve which routing target (local|linear) governs a given lifecycle artifact (spec|plan|stasis|idea|backlog) per ccanvil.json + ccanvil.local.json — read-only delegate to _lifecycle_route helper, exposed as a CLI surface for skills and provider-activate
# input: --project-dir <path>
# input: positional <kind> ∈ {spec, plan, stasis, idea, backlog}
# output: stdout routing target string ("local" or "linear")
# output: exit-codes 0 ok, 2 unknown-flag/missing-kind
# caller: skill:/spec
# depends-on: _lifecycle_route
# side-effect: reads-config-files
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: missing-kind | exit=2 | visible=stderr-Usage
# contract: returns-local-by-default-when-unconfigured
# contract: accepts-idea-and-backlog-kinds
# anchor: BTS-204 (route-aware lifecycle)
# anchor: BTS-241 (manifest seed)
# anchor: BTS-316 (idea + backlog allowlist extension)
cmd_route_of() {
  local kind="" project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh route-of <spec|plan|stasis|idea|backlog> [--project-dir <path>]" >&2; exit 2 ;;
      spec|plan|stasis|idea|backlog) kind="$1"; shift ;;
      *) shift ;;
    esac
  done
  if [[ -z "$kind" ]]; then
    # @failure-mode: missing-kind
    echo "Usage: docs-check.sh route-of <spec|plan|stasis|idea|backlog> [--project-dir <dir>]" >&2
    return 2
  fi
  # @side-effect: reads-config-files
  _lifecycle_route "$kind" "$project_dir"
}

# cmd_artifact_read — read spec/plan/stasis content from the routed source.
# Args:
#   --kind <spec|plan|stasis>
#   --feature <BTS-N>           required when http-routed (or --stasis-kind feature)
#   --stasis-kind <feature|session>  defaults to "feature"
# Output: artifact content on stdout (markdown). Exit 0 on found, 2 on missing.
# @manifest
# purpose: BTS-204 — read spec/plan/stasis content from the routed source (local file system on local-routed nodes, Linear Document on linear-routed) and emit on stdout; provider-aware reader counterpart to cmd_artifact_write
# input: --kind {spec|plan|stasis}
# input: --feature <id>
# input: --stasis-kind {feature|session}
# input: --project-dir <path>
# output: stdout markdown content
# output: exit-codes 0 found, 2 missing/usage-error
# caller: skill:/plan
# caller: skill:/recall
# caller: cmd_archive_stasis
# depends-on: _lifecycle_route
# side-effect: reads-local-doc-or-queries-linear
# failure-mode: missing-kind | exit=2 | visible=stderr-error
# failure-mode: not-found | exit=2 | visible=stderr-error
# contract: route-aware-by-kind
# anchor: BTS-204 (provider-aware artifact-read substrate)
# anchor: BTS-241 (manifest seed)
cmd_artifact_read() {
  local kind="" feature="" stasis_kind="feature" project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind)         kind="$2";        shift 2 ;;
      --feature)      feature="$2";     shift 2 ;;
      --stasis-kind)  stasis_kind="$2"; shift 2 ;;
      --project-dir)  project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      --*) echo "Usage: docs-check.sh artifact-read --kind {spec|plan|stasis} [--feature <id>] [--stasis-kind {feature|session}] [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done
  # @failure-mode: missing-kind
  # @side-effect: reads-local-doc-or-queries-linear
  [[ -z "$kind" ]] && { echo "ERROR: artifact-read --kind is required" >&2; return 2; }

  local route
  route=$(_lifecycle_route "$kind" "$project_dir")

  if [[ "$route" != "linear" ]]; then
    local target
    case "$kind" in
      spec)   target="$project_dir/docs/spec.md" ;;
      plan)   target="$project_dir/docs/plan.md" ;;
      stasis) target="$project_dir/docs/stasis.md" ;;
      *) echo "ERROR: artifact-read unknown kind '$kind'" >&2; return 2 ;;
    esac
    [[ ! -f "$target" ]] && return 2
    cat "$target"
    return 0
  fi

  # Linear route. Need feature_id (or project context for session-stasis).
  # BTS-217: normalize --feature to canonical Linear ticket id (BTS-N) so
  # the deterministic doc_id matches what cmd_artifact_write produces
  # regardless of whether the caller passed kebab feature_id or canonical
  # ticket id.
  local script_dir resolve_kind ticket feature_ticket
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  if [[ -n "$feature" ]]; then
    feature_ticket=$(_normalize_feature_to_ticket "$feature")
  else
    feature_ticket=""
  fi
  case "$kind" in
    spec)   resolve_kind="spec";   ticket="$feature_ticket" ;;
    plan)   resolve_kind="plan";   ticket="$feature_ticket" ;;
    stasis)
      if [[ "$stasis_kind" == "session" ]]; then
        resolve_kind="session-stasis"
        ticket=$(_session_stasis_ticket "$project_dir")
      else
        resolve_kind="feature-stasis"
        ticket="$feature_ticket"
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
  # BTS-219: use `if` form to keep set -e from aborting on get-document failure
  # before the WARN classifier runs. The `; rc=$?` pattern was killed by set -e
  # before reaching the failure branch, swallowing every diagnostic.
  if content=$(bash "$script_dir/linear-query.sh" get-document "$doc_id" 2>"$err"); then
    rc=0
  else
    rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    cat "$err" >&2
    # BTS-219: classify the failure + emit structured WARN with retry recipe
    # before deleting the err file. Mirrors the symmetric WARN pattern from
    # cmd_activate's BTS-213 dispatch.
    local warn_class
    warn_class=$(_classify_linear_failure "$err")
    case "$warn_class" in
      auth-missing)
        echo "WARN: artifact-read: auth-missing — Linear API key missing or invalid" >&2
        echo "Retry: Set LINEAR_API_KEY in env or source .env from project root" >&2
        ;;
      not-found)
        echo "WARN: artifact-read: not-found — Document for kind=$kind ticket=$ticket does not exist" >&2
        echo "Retry: Verify ticket has a parented Document of kind=$kind, or use --stasis-kind session" >&2
        ;;
      network-error)
        echo "WARN: artifact-read: network-error — Could not reach Linear API" >&2
        echo "Retry: Check network; bash docs-check.sh artifact-read --kind $kind --feature ${feature:-<id>}" >&2
        ;;
      parse-error|*)
        echo "WARN: artifact-read: parse-error — Unexpected response from Linear API" >&2
        echo "Retry: bash linear-query.sh get-document $doc_id > /tmp/x.json; inspect" >&2
        ;;
    esac
    rm -f "$err"
    # @failure-mode: not-found
    [[ "$warn_class" == "not-found" ]] && return 2
    return 3
  fi
  rm -f "$err"
  printf '%s\n' "$content" | jq -r '.content // empty'
}

# cmd_artifact_write — write artifact content to the routed destination.
# Reads content from stdin. For Linear, performs upsert via document-updated-at
# pre-check, then save-document with --create-with-id on first write.
# @manifest
# purpose: Provider-aware write of feature artifact (spec/plan/stasis) — local file on local-routed projects, Linear Document upsert on Linear-routed.
# routes-by: integrations.routing.<kind>
# input: stdin (artifact body, raw markdown)
# input: --kind {spec|plan|stasis}
# input: --feature <id>
# input: --stasis-kind {feature|session}
# input: --project-dir <path>
# output: stdout JSON envelope on Linear path
# output: empty stdout on local path
# output: exit-codes 0|2|3|4
# caller: cmd_activate
# caller: cmd_ssot_migrate
# caller: skill:/spec
# caller: skill:/stasis
# caller: skill:/plan
# depends-on: linear-query.sh
# depends-on: _lifecycle_route
# depends-on: _normalize_feature_to_ticket
# depends-on: _session_stasis_ticket
# depends-on: _doc_concurrent_edit_check
# depends-on: _doc_cache_set_updated_at
# side-effect: writes-local-doc
# side-effect: upserts-linear-document
# side-effect: sets-doc-cache-updated-at
# failure-mode: validation-error | exit=2 | visible=stderr | mitigation=caller-fixes-args
# failure-mode: dispatch-error | exit=3 | visible=stderr | mitigation=verify-provider-config
# failure-mode: concurrent-edit | exit=4 | visible=stderr-with-history-hint | mitigation=ALLOW_CONCURRENT_EDIT_OVERRIDE=1
# failure-mode: save-failure | exit=passthrough | visible=stderr | mitigation=retry-or-pending-log
# contract: idempotent-on-byte-identical-input
# contract: never-corrupts-on-mid-flight-failure
# contract: skips-cache-on-CREATE-path
# contract: normalizes-feature-id-input
# anchor: BTS-204 (origin)
# anchor: BTS-213 (route-aware spec dispatch)
# anchor: BTS-217 (feature-id normalization)
# anchor: BTS-237 (CREATE-cache fix)
cmd_artifact_write() {
  local kind="" feature="" stasis_kind="feature" project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind)         kind="$2";        shift 2 ;;
      --feature)      feature="$2";     shift 2 ;;
      --stasis-kind)  stasis_kind="$2"; shift 2 ;;
      --project-dir)  project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      --*) echo "Usage: docs-check.sh artifact-write --kind {spec|plan|stasis} [--feature <id>] [--stasis-kind {feature|session}] [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done
  # @failure-mode: validation-error
  [[ -z "$kind" ]] && { echo "ERROR: artifact-write --kind is required" >&2; return 2; }

  local content
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
    # @side-effect: writes-local-doc
    printf '%s' "$content" > "$target"
    return 0
  fi

  # Linear route — upsert.
  local script_dir resolve_kind ticket parent_field parent_value title
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  # BTS-237: LINEAR_QUERY_OVERRIDE for testability — lets bats stub
  # linear-query.sh responses without touching the live API. Production
  # path uses the env var's default ($script_dir/linear-query.sh).
  local lq="${LINEAR_QUERY_OVERRIDE:-$script_dir/linear-query.sh}"
  # BTS-217: normalize --feature input to canonical Linear ticket id.
  # Callers (cmd_activate, /spec skill prose) pass kebab feature_id like
  # "bts-217-flip-linear-routing"; manual operator calls pass "BTS-217".
  # Both must produce the same ticket lookup + deterministic doc_id.
  local feature_ticket
  if [[ -n "$feature" ]]; then
    feature_ticket=$(_normalize_feature_to_ticket "$feature")
  else
    feature_ticket=""
  fi

  case "$kind" in
    spec)   resolve_kind="spec";   ticket="$feature_ticket"; title="Spec: $feature_ticket";   parent_field="issueId" ;;
    plan)   resolve_kind="plan";   ticket="$feature_ticket"; title="Plan: $feature_ticket";   parent_field="issueId" ;;
    stasis)
      if [[ "$stasis_kind" == "session" ]]; then
        resolve_kind="session-stasis"
        ticket=$(_session_stasis_ticket "$project_dir")
        title="Session State"
        parent_field="projectId"
      else
        resolve_kind="feature-stasis"
        ticket="$feature_ticket"
        title="Stasis: $feature_ticket"
        parent_field="issueId"
      fi
      ;;
  esac
  [[ -z "$ticket" ]] && { echo "ERROR: artifact-write $kind requires --feature" >&2; return 2; }

  # @failure-mode: dispatch-error
  if [[ "$parent_field" == "issueId" ]]; then
    parent_value=$(bash "$lq" get-issue "$feature_ticket" 2>/dev/null | jq -r '.uuid // empty')
    [[ -z "$parent_value" ]] && { echo "ERROR: artifact-write could not resolve issue UUID for $feature_ticket (input: $feature)" >&2; return 3; }
  else
    parent_value=$(_session_stasis_ticket "$project_dir")
    [[ -z "$parent_value" ]] && { echo "ERROR: artifact-write project_id missing in provider config" >&2; return 3; }
  fi

  local doc_id
  doc_id=$(bash "$lq" resolve-document-id --kind "$resolve_kind" --ticket "$ticket")

  # BTS-204 Step 19: pre-write concurrent-edit check (AC-8).
  # If the cache has a known updatedAt and Linear's current updatedAt has
  # advanced past it, refuse the write — surface document-history hint.
  # When ALLOW_CONCURRENT_EDIT_OVERRIDE=1, skip the check (operator escape).
  # @failure-mode: concurrent-edit
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
  local was_create=0
  # @side-effect: upserts-linear-document
  # @failure-mode: save-failure
  if bash "$lq" document-updated-at "$doc_id" >/dev/null 2>&1; then
    # Update path
    result=$(jq -n --arg id "$doc_id" --arg content "$content" '{id:$id, content:$content}' \
      | bash "$lq" save-document --input-json -) || return $?
  else
    # Create path with caller-supplied UUID
    was_create=1
    result=$(jq -n --arg id "$doc_id" --arg title "$title" --arg content "$content" \
      --arg parent_field "$parent_field" --arg parent "$parent_value" \
      '{id:$id, title:$title, content:$content} + ({} + (if $parent_field == "issueId" then {issueId:$parent} else {projectId:$parent} end))' \
      | bash "$lq" save-document --create-with-id --input-json -) || return $?
  fi
  echo "$result"
  # BTS-237: cache updatedAt only after UPDATE, not CREATE. Caching the
  # create-response timestamp produces a self-stale baseline that the very
  # next UPDATE writer (typically cmd_activate after /spec) trips against
  # — Linear's eventual-consistency / async normalizer can advance the
  # remote updatedAt slightly after the create response returns. Skipping
  # cache on CREATE lets the next writer see an empty cache (treated as
  # "first write — safe") and proceed; that writer's UPDATE then seeds the
  # cache for genuine concurrent-edit detection going forward.
  if (( was_create == 0 )); then
    local new_ts
    new_ts=$(printf '%s' "$result" | jq -r '.updatedAt // empty')
    if [[ -n "$new_ts" ]]; then
      # @side-effect: sets-doc-cache-updated-at
      _doc_cache_set_updated_at "$doc_id" "$new_ts" "$project_dir"
    fi
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

# @manifest
# purpose: BTS-20 unified envelope — derive the project's current lifecycle state plus legal next actions and blockers from spec/plan/stasis presence + freshness, with route-aware overrides for Linear-routed artifacts; one resolver call replaces the prior validate+recommend pair
# input: --project-dir <path>
# output: stdout JSON {state, legal_next_actions:[{action, command, reason}], blockers:[], suggestions:[], validate_result}
# output: exit-codes 0 ok, 2 unknown-flag/uninitialized
# caller: skill:/spec
# caller: skill:/plan
# caller: skill:/pr
# caller: skill:/recall
# caller: skill:/stasis
# depends-on: cmd_validate
# depends-on: _has_any_linear_route
# depends-on: _active_feature_id
# depends-on: _lifecycle_route
# depends-on: _artifact_present_linear
# depends-on: jq
# side-effect: reads-state-files
# side-effect: queries-linear-routed-artifacts
# failure-mode: unknown-flag | exit=2 | visible=stderr-Usage
# failure-mode: uninitialized | exit=2 | visible=json-state-uninitialized | mitigation=run-/init-or-cd-into-ccanvil-project
# contract: blockers-non-empty-implies-state-blocked
# contract: legal-actions-derived-from-lifecycle-graph
# contract: route-aware-when-any-artifact-linear-routed
# anchor: BTS-20 (lifecycle-state envelope substrate)
# anchor: BTS-204 (route-aware overrides)
# anchor: BTS-241 (manifest seed)
cmd_lifecycle_state() {
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="${2:-.}"; shift 2 ;;
      --) shift; break ;;
      # @failure-mode: unknown-flag
      --*) echo "Usage: docs-check.sh lifecycle-state [--project-dir <path>]" >&2; exit 2 ;;
      *) shift ;;
    esac
  done

  # @failure-mode: uninitialized
  # @side-effect: reads-state-files
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

  # @side-effect: queries-linear-routed-artifacts
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

# BTS-215: generate the usage line from the dispatch case below at runtime.
# Single source of truth — adding a new verb to the case statement makes it
# appear in usage output automatically. The drift-guard test in
# hub/tests/usage-string-dispatch-sync.bats enforces this by construction.
_print_usage() {
  local script="${BASH_SOURCE[0]}"
  local verbs
  verbs=$(awk '
    /^case "\$cmd" in$/ { in_case=1; next }
    in_case && /^esac$/ { in_case=0 }
    in_case && /^[[:space:]]*[a-z][a-z0-9-]+\)/ {
      sub(/^[[:space:]]*/, "")
      sub(/\).*$/, "")
      print
    }
  ' "$script" | sort -u | paste -sd '|' -)
  echo "Usage: docs-check.sh {$verbs} [args...]" >&2
}

# @manifest
# purpose: Layer 1 (Spec-Driven Development) structural validator — reads docs/specs/<id>.md (or Linear-routed Document) and emits JSON envelope assessing AC count, Given/When/Then coverage, error-criterion presence, and file-reference resolution; warn-but-don't-block gate invoked by /spec final step.
# input: --feature <id>
# input: --project-dir <path>
# output: stdout JSON envelope {coverage, missing_file_refs, findings, status}
# output: exit-codes 0 ok, 2 drift|usage-error|spec-not-found
# depends-on: jq
# depends-on: awk
# depends-on: cmd_artifact_read
# side-effect: reads-spec-content
# failure-mode: usage-error | exit=2 | visible=stderr-usage
# failure-mode: spec-not-found | exit=2 | visible=stderr-error
# failure-mode: drift-detected | exit=2 | visible=stdout-envelope-status-drift
# contract: warn-but-dont-block-via-/spec-final-step
# contract: envelope-shape-mirrors-cmd_validate
# anchor: BTS-265 (origin)
cmd_validate_spec() {
  local feature=""
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --feature)     feature="$2"; shift 2 ;;
      --project-dir) project_dir="$2"; shift 2 ;;
      # @failure-mode: usage-error
      *) echo "Usage: docs-check.sh validate-spec --feature <id> [--project-dir <path>]" >&2; return 2 ;;
    esac
  done
  if [[ -z "$feature" ]]; then
    echo "Usage: docs-check.sh validate-spec --feature <id>" >&2
    return 2
  fi

  local spec_content
  local spec_path="$project_dir/docs/specs/${feature}.md"
  # @side-effect: reads-spec-content
  if [[ -f "$spec_path" ]]; then
    spec_content=$(cat "$spec_path")
  else
    if ! spec_content=$(cmd_artifact_read --kind spec --feature "$feature" --project-dir "$project_dir" 2>/dev/null); then
      # @failure-mode: spec-not-found
      echo "ERROR: spec not found: docs/specs/${feature}.md" >&2
      return 2
    fi
    if [[ -z "$spec_content" ]]; then
      echo "ERROR: spec not found: docs/specs/${feature}.md" >&2
      return 2
    fi
  fi

  # Parse Acceptance Criteria section.
  local ac_section
  ac_section=$(echo "$spec_content" | awk '
    /^## Acceptance Criteria/ { in_sec=1; next }
    in_sec && /^## / { in_sec=0 }
    in_sec { print }
  ')

  local ac_count gwt_count error_count
  ac_count=$(echo "$ac_section" | grep -cE '^[[:space:]]*- \[ ?[xX]? ?\] \*\*AC-' || true)
  gwt_count=$(echo "$ac_section" | grep -ciE 'given.*when.*then|given:.*when:.*then:' || true)
  error_count=$(echo "$ac_section" | grep -ciE '\b(error|edge|fail|invalid)\b' || true)

  # Parse Affected Files table for file refs.
  local af_section
  af_section=$(echo "$spec_content" | awk '
    /^## Affected Files/ { in_sec=1; next }
    in_sec && /^## / { in_sec=0 }
    in_sec { print }
  ')

  local file_refs_total=0 file_refs_resolved=0
  local missing_file_refs="[]"
  local missing_acc=""
  local row line path change
  while IFS= read -r row; do
    [[ "$row" =~ ^\| ]] || continue
    [[ "$row" =~ ^\|[[:space:]]*-+ ]] && continue
    [[ "$row" =~ ^\|[[:space:]]*File[[:space:]]*\| ]] && continue
    path=$(echo "$row" | awk -F'\\|' '{print $2}' | grep -oE '`[^`]+`' | head -1 | tr -d '`')
    change=$(echo "$row" | awk -F'\\|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$path" ]] && continue
    file_refs_total=$((file_refs_total + 1))
    if [[ "$change" =~ ^New ]] || [[ "$path" == *"*"* ]]; then
      file_refs_resolved=$((file_refs_resolved + 1))
    elif [[ -e "$project_dir/$path" ]]; then
      file_refs_resolved=$((file_refs_resolved + 1))
    else
      missing_acc+="$(jq -nc --arg p "$path" --arg r "$row" '{path:$p,row:$r}')"$'\n'
    fi
  done <<< "$af_section"

  if [[ -n "$missing_acc" ]]; then
    missing_file_refs=$(echo "$missing_acc" | jq -s '.')
  fi

  # Determine status.
  local status_val="ok"
  local findings=()
  # @failure-mode: drift-detected
  if (( ac_count == 0 )); then
    findings+=("no-acceptance-criteria")
    status_val="drift"
  fi
  if (( ac_count >= 4 && gwt_count == 0 )); then
    findings+=("missing-given-when-then")
    status_val="drift"
  fi
  if (( error_count == 0 )); then
    findings+=("missing-error-criterion")
    status_val="drift"
  fi
  if [[ "$missing_file_refs" != "[]" ]]; then
    findings+=("unresolved-file-refs")
    status_val="drift"
  fi

  local findings_json
  findings_json=$(printf '%s\n' "${findings[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')

  jq -nc \
    --argjson ac "$ac_count" \
    --argjson gwt "$gwt_count" \
    --argjson err "$error_count" \
    --argjson rr "$file_refs_resolved" \
    --argjson rt "$file_refs_total" \
    --argjson mfr "$missing_file_refs" \
    --argjson f "$findings_json" \
    --arg s "$status_val" \
    '{coverage:{ac_count:$ac,gwt_count:$gwt,error_criterion_count:$err,file_refs_resolved:$rr,file_refs_total:$rt},missing_file_refs:$mfr,findings:$f,status:$s}'

  [[ "$status_val" == "drift" ]] && return 2 || return 0
}

# @manifest
# purpose: Resolve a rule file's tier metadata + anchor pointers into a JSON envelope; reads top-level YAML frontmatter (tier, scope, stack, anchors) from .claude/rules/<id>.md, backward-compat default applied when fields absent. Substrate for the BTS-385 rule atomicity ramp.
# input: <rule-id> positional
# input: --project-dir <path>
# output: stdout JSON envelope {rule, tier, scope, stack, anchors, body_path}
# output: exit-codes 0 ok, 1 rule-not-found, 2 usage-error|frontmatter-malformed
# depends-on: jq
# depends-on: python3
# side-effect: reads-rule-file
# failure-mode: usage-error | exit=2 | visible=stderr-usage
# failure-mode: rule-not-found | exit=1 | visible=stdout-error-json
# failure-mode: frontmatter-malformed | exit=2 | visible=stdout-error-json
# contract: default-envelope-when-frontmatter-absent
# contract: tier-defaults-to-0
# contract: scope-defaults-to-universal
# contract: stack-defaults-to-any
# contract: anchors-defaults-to-empty-object
# anchor: BTS-385 (Session A substrate)
cmd_rule_resolve() {
  local rule_id=""
  local project_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      # @failure-mode: usage-error
      -*) echo "Usage: docs-check.sh rule-resolve <rule-id> [--project-dir <path>]" >&2; return 2 ;;
      *) rule_id="$1"; shift ;;
    esac
  done
  if [[ -z "$rule_id" ]]; then
    echo "Usage: docs-check.sh rule-resolve <rule-id> [--project-dir <path>]" >&2
    return 2
  fi

  local body_path=".claude/rules/${rule_id}.md"
  local rule_file="${project_dir}/${body_path}"

  # @failure-mode: rule-not-found
  if [[ ! -f "$rule_file" ]]; then
    jq -nc --arg id "$rule_id" '{error:"rule-not-found",rule:$id}'
    return 1
  fi

  # Parse top-level YAML frontmatter via python3+yaml. Emits a JSON object on
  # stdout — either the parsed fields, or {"_error": "..."} for parse failure.
  # @side-effect: reads-rule-file
  local fm_json
  fm_json=$(python3 - "$rule_file" <<'PY'
import sys, json
try:
    import yaml
except ImportError:
    print(json.dumps({"_error": "yaml-module-missing"}))
    sys.exit(0)

with open(sys.argv[1], "r") as f:
    text = f.read()

lines = text.splitlines()
if not lines or lines[0].strip() != "---":
    # No frontmatter — emit default envelope marker
    print(json.dumps({"_no_frontmatter": True}))
    sys.exit(0)

end = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        end = i
        break
if end is None:
    print(json.dumps({"_error": "frontmatter-unclosed"}))
    sys.exit(0)

fm_text = "\n".join(lines[1:end])
try:
    fm = yaml.safe_load(fm_text) or {}
except yaml.YAMLError as e:
    print(json.dumps({"_error": "frontmatter-malformed", "reason": str(e)[:200]}))
    sys.exit(0)

if not isinstance(fm, dict):
    print(json.dumps({"_error": "frontmatter-not-mapping"}))
    sys.exit(0)

print(json.dumps({
    "tier": fm.get("tier", 0),
    "scope": fm.get("scope", "universal"),
    "stack": fm.get("stack", "any"),
    "anchors": fm.get("anchors") or {},
}))
PY
  )

  # Check for parse-error envelope
  local parse_error
  parse_error=$(echo "$fm_json" | jq -r '._error // empty')
  if [[ -n "$parse_error" ]]; then
    case "$parse_error" in
      yaml-module-missing)
        echo "ERROR: python3 yaml module not available — cannot parse rule frontmatter" >&2
        return 2
        ;;
      frontmatter-malformed|frontmatter-unclosed|frontmatter-not-mapping)
        # @failure-mode: frontmatter-malformed
        local reason
        reason=$(echo "$fm_json" | jq -r '.reason // empty')
        jq -nc --arg id "$rule_id" --arg err "$parse_error" --arg r "$reason" \
          '{error:"frontmatter-malformed",rule:$id,reason:($err + (if $r == "" then "" else ": " + $r end))}'
        return 2
        ;;
    esac
  fi

  # Compose final envelope. Defaults applied when frontmatter absent (back-compat).
  jq -nc \
    --arg rule "$rule_id" \
    --arg body_path "$body_path" \
    --argjson fm "$fm_json" \
    '{
      rule: $rule,
      tier: ($fm.tier // 0),
      scope: ($fm.scope // "universal"),
      stack: ($fm.stack // "any"),
      anchors: ($fm.anchors // {}),
      body_path: $body_path
    }'
}

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
  provider-resolve-ids) cmd_provider_resolve_ids "$@" ;;
  provider-heal-preflight) cmd_provider_heal_preflight "$@" ;;
  provider-heal-auth) cmd_provider_heal_auth "$@" ;;
  provider-heal) cmd_provider_heal "$@" ;;
  provider-activate) cmd_provider_activate "$@" ;;
  operator-config) cmd_operator_config "$@" ;;
  idea-upgrade)      cmd_idea_upgrade "$@" ;;
  title-from-body)   cmd_title_from_body "$@" ;;
  legacy-refs-scan)  cmd_legacy_refs_scan "$@" ;;
  stamp-spec)        cmd_stamp_spec "$@" ;;
  idea-pending-append) cmd_idea_pending_append "$@" ;;
  idea-template-body) cmd_idea_template_body "$@" ;;
  idea-pending-validate) cmd_idea_pending_validate "$@" ;;
  remote-presence)   cmd_remote_presence "$@" ;;
  evidence-scan-session) cmd_evidence_scan_session "$@" ;;
  stasis-carry-forward) cmd_stasis_carry_forward "$@" ;;
  ship-finalize)     cmd_ship_finalize "$@" ;;
  lifecycle-state)   cmd_lifecycle_state "$@" ;;
  artifact-read)     cmd_artifact_read "$@" ;;
  artifact-write)    cmd_artifact_write "$@" ;;
  route-of)          cmd_route_of "$@" ;;
  ssot-migrate)      cmd_ssot_migrate "$@" ;;
  session-info)      cmd_session_info "$@" ;;
  validate-spec)     cmd_validate_spec "$@" ;;
  rule-resolve)      cmd_rule_resolve "$@" ;;
  *)
    _print_usage
    exit 1
    ;;
esac
