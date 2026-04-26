#!/usr/bin/env bash
# permissions-audit.sh — Deterministic permissions auditor for Claude Code settings.
#
# Parses Bash permission entries from .claude/settings.json and
# .claude/settings.local.json, classifies each as DANGER / UNREVIEWED / REVIEWED
# based on pattern matching and a decision log.
#
# Exit codes:
#   0 — all entries REVIEWED, no DANGER
#   1 — UNREVIEWED entries exist (no DANGER)
#   2 — DANGER entries exist (or usage/parse error)
#
# Usage:
#   permissions-audit.sh check [--settings-dir DIR] [--log FILE]
#   permissions-audit.sh init  [--settings-dir DIR] [--log FILE]

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

SETTINGS_DIR=".claude"
LOG_FILE=""  # set after parsing args; defaults to SETTINGS_DIR/permissions-log.json

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

CMD=""
TEXT_MODE=false
VERBOSE=false
DECISIONS_FILE=""

usage() {
  echo "Usage: permissions-audit.sh <check|init|promote-review|apply> [--settings-dir DIR] [--log FILE] [--decisions FILE] [--text|--json] [--verbose]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    check|init|promote-review|apply)
      CMD="$1"; shift ;;
    --settings-dir)
      SETTINGS_DIR="$2"; shift 2 ;;
    --log)
      LOG_FILE="$2"; shift 2 ;;
    --decisions)
      DECISIONS_FILE="$2"; shift 2 ;;
    --text)
      TEXT_MODE=true; shift ;;
    --json)
      TEXT_MODE=false; shift ;;
    --verbose)
      VERBOSE=true; shift ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2; usage ;;
  esac
done

# Emit a JSON error envelope on stdout (when not in --text mode), then exit.
# Always echoes the human-readable message to stderr too.
emit_error_envelope() {
  local msg="$1"
  local code="$2"
  echo "ERROR: $msg" >&2
  if [[ "$TEXT_MODE" != "true" ]]; then
    jq -n --arg e "$msg" --argjson c "$code" '{error: $e, exit: $c}'
  fi
  exit "$code"
}

[[ -z "$CMD" ]] && usage

# Default log file location
[[ -z "$LOG_FILE" ]] && LOG_FILE="$SETTINGS_DIR/permissions-log.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Collect all permission entries from a settings file into a jq-compatible format.
# Outputs JSON array of {permission, source} objects.
parse_settings_file() {
  local file="$1"
  local source_name="$2"

  if [[ ! -f "$file" ]]; then
    echo "[]"
    return
  fi

  jq -r --arg src "$source_name" '
    [
      (.permissions.allow // [] | .[] | {permission: ., source: $src, type: "allow"}),
      (.permissions.deny // [] | .[] | {permission: ., source: $src, type: "deny"})
    ]
  ' "$file"
}

# ---------------------------------------------------------------------------
# Dangerous pattern detection
# ---------------------------------------------------------------------------

# Each pattern: "label|regex"
# The regex is matched against the inner command (after stripping Bash(...) wrapper).
# Order matters — first match wins.
DANGER_PATTERNS=(
  # Broad command wildcards — grants access to entire command namespace
  "broad-wildcard|^(echo|cat|find|bash|env|sort|rm|cp|mv|chmod|chown):\*$"
  # Compound operators — bypass allow-list matching
  "compound-operator|;|&&|[|][|]"
  # Redirect operators — can overwrite arbitrary files (excludes 2>&1 stderr redirect)
  "redirect| [^2][^>]*>[^&]| >>|^>"
  # Env-prefix commands — execute arbitrary commands with modified environment
  "env-prefix|^[A-Z_]+="
  # find -exec / find -delete — arbitrary command execution via find
  "find-exec|find .* -exec|find .* -delete"
  # Loop primitives — shell control flow shouldn't be in permissions
  "loop-primitive|^for |^do |^done"
  # Arbitrary execution — run arbitrary commands
  "arbitrary-exec|xargs -I|^env "
  # File mutation — destructive git operations or file overwrites
  "file-mutation|sort -o|git branch -[Dd]|git tag -d|git push.*--force|git reset --hard"
)

# Extract the inner command from a permission string.
# "Bash(git status:*)" → "git status:*"
# "Bash(rm -rf /)*" → "rm -rf /)*"  (deny entries may have trailing pattern)
strip_bash_wrapper() {
  local perm="$1"
  # Remove leading "Bash(" and trailing ")" if present
  perm="${perm#Bash(}"
  # Remove trailing ) only if it's the last char
  if [[ "$perm" == *")" ]]; then
    perm="${perm%)}"
  fi
  echo "$perm"
}

# BTS-154: bash control-flow keywords are grammar tokens, not executable
# commands. Bare `Bash(<keyword>)` and `Bash(<keyword>:*)` shapes carry no
# risk surface — exempt them BEFORE running DANGER patterns. Word-anchored
# (^...$) so substring shapes like `Bash(done-something)` / `Bash(fish)` /
# `Bash(forever)` fall through to the normal classifier path.
BASH_KEYWORD_REGEX='^(for|while|until|if|then|else|elif|fi|do|done|case|esac|in|function|select|time)(:\*)?$'

is_safe_bash_keyword() {
  local inner="$1"
  echo "$inner" | grep -qE "$BASH_KEYWORD_REGEX"
}

# Check if a permission matches any dangerous pattern.
# Returns the pattern label if matched, empty string if safe.
# Note: bash control-flow keyword exemption (BTS-154) is enforced one
# layer up in the main classify loop — entries that match the keyword
# regex never reach check_danger.
check_danger() {
  local inner="$1"

  for pattern_entry in "${DANGER_PATTERNS[@]}"; do
    local label="${pattern_entry%%|*}"
    local regex="${pattern_entry#*|}"

    if echo "$inner" | grep -qE "$regex"; then
      echo "$label"
      return 0
    fi
  done

  echo ""
  return 1
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_check() {
  local settings_file="$SETTINGS_DIR/settings.json"
  local settings_local_file="$SETTINGS_DIR/settings.local.json"

  # settings.json must exist
  if [[ ! -f "$settings_file" ]]; then
    emit_error_envelope "$settings_file not found" 2
  fi

  # Parse both files
  local entries_main entries_local all_entries
  entries_main=$(parse_settings_file "$settings_file" "settings.json")
  entries_local=$(parse_settings_file "$settings_local_file" "settings.local.json")

  # Merge and deduplicate: group by permission, collect sources into arrays
  all_entries=$(jq -n --argjson a "$entries_main" --argjson b "$entries_local" '
    ($a + $b) | group_by(.permission) | map({
      permission: .[0].permission,
      source: [.[].source] | unique
    })
  ')

  # Load permissions log if available
  local log_data="{}"
  local log_missing=false
  if [[ ! -f "$LOG_FILE" ]]; then
    log_missing=true
    echo "NOTE: $LOG_FILE not found — run permissions-audit.sh init" >&2
  elif ! jq empty "$LOG_FILE" 2>/dev/null; then
    emit_error_envelope "$LOG_FILE is not valid JSON" 2
  else
    log_data=$(jq '.entries // {}' "$LOG_FILE")
  fi

  # Classify each entry
  local classified danger_count=0 unreviewed_count=0 reviewed_count=0
  classified="[]"

  local entry_count
  entry_count=$(echo "$all_entries" | jq 'length')

  for (( i=0; i<entry_count; i++ )); do
    local perm sources
    perm=$(echo "$all_entries" | jq -r ".[$i].permission")
    sources=$(echo "$all_entries" | jq -c ".[$i].source")

    # Skip non-Bash entries — out of scope per spec
    if [[ "$perm" != Bash\(* ]]; then
      unreviewed_count=$((unreviewed_count + 1))
      classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
        '. + [{permission: $p, source: $s, status: "UNREVIEWED"}]')
      continue
    fi

    local inner matched_pattern
    inner=$(strip_bash_wrapper "$perm")

    # BTS-154: bash control-flow keywords classify as REVIEWED with a
    # built-in rationale. Short-circuits both DANGER and UNREVIEWED paths,
    # so operators don't need accept_danger overrides for grammar tokens.
    if is_safe_bash_keyword "$inner"; then
      reviewed_count=$((reviewed_count + 1))
      classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
        '. + [{permission: $p, source: $s, status: "REVIEWED", rationale: "bash control-flow keyword (BTS-154 grammar exemption)"}]')
      continue
    fi

    matched_pattern=$(check_danger "$inner" || true)

    if [[ -n "$matched_pattern" ]]; then
      # BTS-143: check for explicit accept_danger override before DANGER classification.
      # When the log entry has accept_danger:true AND all four required fields are filled,
      # reclassify as REVIEWED with risk_accepted:true preserved for the audit trail.
      # Otherwise, DANGER takes precedence (preserves prior behavior for log entries
      # without accept_danger or with stub fields).
      local log_entry override
      log_entry=$(echo "$log_data" | jq -c --arg p "$perm" '.[$p] // null')
      override=$(echo "$log_entry" | jq '
        if . == null then false
        elif .accept_danger != true then false
        elif .risk == "" or .risk == "TODO" then false
        elif .rationale == "" or .rationale == "TODO" then false
        elif .efficiency_justification == "" or .efficiency_justification == "TODO" then false
        elif .reviewer == "" or .reviewer == "TODO" then false
        else true
        end
      ')

      if [[ "$override" == "true" ]]; then
        reviewed_count=$((reviewed_count + 1))
        local risk rationale
        risk=$(echo "$log_entry" | jq -r '.risk')
        rationale=$(echo "$log_entry" | jq -r '.rationale')
        classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
          --arg mp "$matched_pattern" --arg risk "$risk" --arg rationale "$rationale" \
          '. + [{permission: $p, source: $s, status: "REVIEWED", matched_pattern: $mp, risk: $risk, rationale: $rationale, risk_accepted: true}]')
      else
        danger_count=$((danger_count + 1))
        classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" --arg mp "$matched_pattern" \
          '. + [{permission: $p, source: $s, status: "DANGER", matched_pattern: $mp}]')
      fi
    else
      # Check log for review status
      local log_entry is_reviewed
      log_entry=$(echo "$log_data" | jq -c --arg p "$perm" '.[$p] // null')
      is_reviewed=$(echo "$log_entry" | jq '
        if . == null then false
        elif .risk == "" or .risk == "TODO" then false
        elif .rationale == "" or .rationale == "TODO" then false
        elif .efficiency_justification == "" or .efficiency_justification == "TODO" then false
        elif .reviewer == "" or .reviewer == "TODO" then false
        else true
        end
      ')

      if [[ "$is_reviewed" == "true" ]]; then
        reviewed_count=$((reviewed_count + 1))
        local risk rationale
        risk=$(echo "$log_entry" | jq -r '.risk')
        rationale=$(echo "$log_entry" | jq -r '.rationale')
        classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
          --arg risk "$risk" --arg rationale "$rationale" \
          '. + [{permission: $p, source: $s, status: "REVIEWED", risk: $risk, rationale: $rationale}]')
      else
        unreviewed_count=$((unreviewed_count + 1))
        classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
          '. + [{permission: $p, source: $s, status: "UNREVIEWED"}]')
      fi
    fi
  done

  # Output
  if [[ "$TEXT_MODE" == "true" ]]; then
    print_text_report "$classified" "$danger_count" "$unreviewed_count" "$reviewed_count"
  else
    jq -n --argjson entries "$classified" \
      --argjson d "$danger_count" --argjson u "$unreviewed_count" --argjson r "$reviewed_count" \
      '{entries: $entries, danger: $d, unreviewed: $u, reviewed: $r}'
  fi

  # Exit codes: 2 = DANGER, 1 = UNREVIEWED, 0 = all REVIEWED
  if [[ "$danger_count" -gt 0 ]]; then
    return 2
  elif [[ "$unreviewed_count" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Text output
# ---------------------------------------------------------------------------

print_text_report() {
  local entries="$1"
  local danger_count="$2"
  local unreviewed_count="$3"
  local reviewed_count="$4"

  echo "Permissions Audit"
  echo "================="
  echo ""
  echo "Summary: $danger_count DANGER, $unreviewed_count UNREVIEWED, $reviewed_count REVIEWED"
  echo ""

  # DANGER entries first
  if [[ "$danger_count" -gt 0 ]]; then
    echo "--- DANGER ---"
    echo "$entries" | jq -r '
      [.[] | select(.status == "DANGER")] | .[] |
      "  \(.permission)  [\(.matched_pattern)]  (from: \(.source | join(", ")))"
    '
    echo ""
  fi

  # UNREVIEWED entries
  if [[ "$unreviewed_count" -gt 0 ]]; then
    echo "--- UNREVIEWED ---"
    echo "$entries" | jq -r '
      [.[] | select(.status == "UNREVIEWED")] | .[] |
      "  \(.permission)  (from: \(.source | join(", ")))"
    '
    echo ""
  fi

  # REVIEWED entries — risk-accepted always visible (BTS-143), clean entries verbose-only
  local has_risk_accepted
  has_risk_accepted=$(echo "$entries" | jq '[.[] | select(.status == "REVIEWED" and .risk_accepted == true)] | length > 0')
  if [[ "$has_risk_accepted" == "true" ]]; then
    echo "--- REVIEWED (risk-accepted) ---"
    echo "$entries" | jq -r '
      [.[] | select(.status == "REVIEWED" and .risk_accepted == true)] | .[] |
      "  \(.permission)  [\(.matched_pattern)] [risk-accepted] \(.rationale // "")  (from: \(.source | join(", ")))"
    '
    echo ""
  fi
  if [[ "$VERBOSE" == "true" && "$reviewed_count" -gt 0 ]]; then
    echo "--- REVIEWED ---"
    echo "$entries" | jq -r '
      [.[] | select(.status == "REVIEWED" and (.risk_accepted // false) == false)] | .[] |
      "  \(.permission)  [\(.risk // "?")] \(.rationale // "")  (from: \(.source | join(", ")))"
    '
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Init command
# ---------------------------------------------------------------------------

cmd_init() {
  local settings_file="$SETTINGS_DIR/settings.json"
  local settings_local_file="$SETTINGS_DIR/settings.local.json"

  # settings.json must exist
  if [[ ! -f "$settings_file" ]]; then
    echo "ERROR: $settings_file not found" >&2
    exit 2
  fi

  # Parse both files to get all permission strings
  local entries_main entries_local all_perms
  entries_main=$(parse_settings_file "$settings_file" "settings.json")
  entries_local=$(parse_settings_file "$settings_local_file" "settings.local.json")

  # Get unique permission strings
  all_perms=$(jq -n --argjson a "$entries_main" --argjson b "$entries_local" '
    ($a + $b) | [.[].permission] | unique
  ')

  # Load existing log or start fresh
  local existing="{}"
  if [[ -f "$LOG_FILE" ]]; then
    if ! jq empty "$LOG_FILE" 2>/dev/null; then
      echo "ERROR: $LOG_FILE is not valid JSON" >&2
      exit 2
    fi
    existing=$(jq '.entries // {}' "$LOG_FILE")
  fi

  # Merge: keep existing reviewed entries, add stubs for new ones
  local stub='{"risk":"","rationale":"TODO","efficiency_justification":"","reviewer":"","reviewed_epoch":0}'
  local merged
  merged=$(jq -n --argjson perms "$all_perms" --argjson existing "$existing" --argjson stub "$stub" '
    reduce $perms[] as $p (
      {};
      . + {($p): ($existing[$p] // $stub)}
    )
  ')

  # Write the log file
  jq -n --argjson entries "$merged" '{entries: $entries}' > "$LOG_FILE"

  local total
  total=$(echo "$all_perms" | jq 'length')
  local existing_count
  existing_count=$(echo "$existing" | jq 'length')
  local new_count=$((total - existing_count))
  if [[ "$new_count" -lt 0 ]]; then
    new_count=0
  fi

  echo "Initialized $LOG_FILE: $total entries ($new_count new stubs, rest preserved)"
}

# ---------------------------------------------------------------------------
# Promote-review command (BTS-144)
#
# Lists settings.local.json entries not in settings.json and classifies each
# deterministically: DELETE (redundant covered by broader, dead-path, or
# env-prefix one-shot) or TRIAGE (needs human judgment). PROMOTE is reserved
# for the future --apply flow.
#
# Output: JSON {candidates: [...], counts: {delete, promote, triage, total}}
# Exit: always 0 (read-only review tooling).
# ---------------------------------------------------------------------------

cmd_promote_review() {
  local main_file="$SETTINGS_DIR/settings.json"
  local local_file="$SETTINGS_DIR/settings.local.json"

  # Empty/missing local file → empty output.
  if [[ ! -f "$local_file" ]]; then
    jq -n '{candidates: [], counts: {delete: 0, promote: 0, triage: 0, total: 0}}'
    return 0
  fi

  # Both files must exist for delta. Treat missing main as empty allow list.
  local main_entries local_entries
  if [[ -f "$main_file" ]]; then
    main_entries=$(parse_settings_file "$main_file" "settings.json")
  else
    main_entries="[]"
  fi
  local_entries=$(parse_settings_file "$local_file" "settings.local.json")

  # Filter local entries to those NOT in main (string equality).
  local main_set
  main_set=$(echo "$main_entries" | jq -c '[.[].permission]')
  local candidates_raw
  candidates_raw=$(jq -nc --argjson l "$local_entries" --argjson m "$main_set" \
    '$l | map(select(.permission as $p | $m | index($p) | not))')

  # Pre-extract main wildcard list (Bash(<word>:*)) for AC-3.
  local main_wildcards
  main_wildcards=$(echo "$main_entries" | jq -r '.[].permission | select(test("^Bash\\(([^:)]+):\\*\\)$"))')

  local classified="[]"
  local d_count=0 t_count=0

  local n
  n=$(echo "$candidates_raw" | jq 'length')
  local i
  for ((i=0; i<n; i++)); do
    local perm rec reason
    perm=$(echo "$candidates_raw" | jq -r ".[$i].permission")
    rec="TRIAGE"
    reason="manual review required"

    # AC-3: redundant — broader Bash(<word>:*) wildcard in main covers this entry.
    # Regex stored in vars to dodge bash's = ~ + paren parsing weirdness.
    local broader=""
    local _wildcard_re='^Bash\(([^:)]+):\*\)$'
    if [[ -n "$main_wildcards" ]]; then
      while IFS= read -r main_p; do
        [[ -z "$main_p" ]] && continue
        if [[ "$main_p" =~ $_wildcard_re ]]; then
          local word="${BASH_REMATCH[1]}"
          if [[ "$perm" == "Bash($word "* || "$perm" == "Bash($word:"* ]]; then
            broader="$main_p"
            break
          fi
        fi
      done <<< "$main_wildcards"
    fi

    local _envprefix_re='^Bash\(ALLOW_[A-Z_]+=1 (bash|rm|cp|mv|chmod|chown) '
    if [[ -n "$broader" ]]; then
      rec="DELETE"
      reason="redundant: covered by '$broader' in settings.json"
    elif [[ "$perm" == *"preset/"* ]]; then
      # AC-4: dead path — pre-BTS-67 preset/ directory removed during flatten.
      rec="DELETE"
      reason="dead path: pre-BTS-67 preset/ structure removed"
    elif [[ "$perm" =~ $_envprefix_re ]]; then
      # AC-5: env-prefix one-shot — underlying verb broadly allowed in main.
      local verb="${BASH_REMATCH[1]}"
      if echo "$main_entries" | jq -e --arg v "Bash($verb:*)" '.[] | select(.permission == $v)' >/dev/null 2>&1; then
        rec="DELETE"
        reason="one-shot bypass: underlying command now broadly allowed"
      fi
    fi

    classified=$(echo "$classified" | jq --arg p "$perm" --arg r "$rec" --arg rs "$reason" \
      '. + [{permission: $p, source: ["settings.local.json"], recommendation: $r, reason: $rs}]')

    if [[ "$rec" == "DELETE" ]]; then
      d_count=$((d_count + 1))
    else
      t_count=$((t_count + 1))
    fi
  done

  if [[ "$TEXT_MODE" == "true" ]]; then
    if [[ "$d_count" -eq 0 && "$t_count" -eq 0 ]]; then
      echo "No promote-review candidates."
      return 0
    fi
    if [[ "$d_count" -gt 0 ]]; then
      echo "--- DELETE ---"
      echo "$classified" | jq -r '
        [.[] | select(.recommendation == "DELETE")] | .[] |
        "  \(.permission)  — \(.reason)"
      '
      echo ""
    fi
    if [[ "$t_count" -gt 0 ]]; then
      echo "--- TRIAGE ---"
      echo "$classified" | jq -r '
        [.[] | select(.recommendation == "TRIAGE")] | .[] |
        "  \(.permission)  — \(.reason)"
      '
      echo ""
    fi
    echo "Summary: $d_count DELETE, $t_count TRIAGE"
  else
    jq -n --argjson c "$classified" --argjson d "$d_count" --argjson t "$t_count" \
      '{candidates: $c, counts: {delete: $d, promote: 0, triage: $t, total: ($c | length)}}'
  fi
}

# ---------------------------------------------------------------------------
# BTS-149 — apply --decisions <jsonl>: interactive triage substrate
# ---------------------------------------------------------------------------

# Globals used by the ERR trap installed during cmd_apply's mutation pass.
# Set immediately before mutations start so the trap can restore from .bak
# on any failure mid-stream (AC-4 atomicity).
_APPLY_LOCAL_FILE=""
_APPLY_MAIN_FILE=""

apply_restore_and_exit() {
  [[ -n "$_APPLY_LOCAL_FILE" && -f "$_APPLY_LOCAL_FILE.bak" ]] && mv "$_APPLY_LOCAL_FILE.bak" "$_APPLY_LOCAL_FILE"
  [[ -n "$_APPLY_MAIN_FILE"  && -f "$_APPLY_MAIN_FILE.bak"  ]] && mv "$_APPLY_MAIN_FILE.bak"  "$_APPLY_MAIN_FILE"
  exit 3
}

cmd_apply() {
  if [[ -z "$DECISIONS_FILE" ]]; then
    emit_error_envelope "apply requires --decisions <file>" 2
  fi
  if [[ ! -f "$DECISIONS_FILE" ]]; then
    emit_error_envelope "decisions file not found: $DECISIONS_FILE" 2
  fi

  # Pre-flight validation: parse every non-blank line as JSON, check for
  # required `permission` field, and verify `decision` is in the known set.
  # Any error → exit 2 BEFORE any backup or mutation. AC-2: no partial
  # mutation on validation errors.
  local line_no=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no+1))
    [[ -z "$line" ]] && continue

    if ! echo "$line" | jq -e . >/dev/null 2>&1; then
      emit_error_envelope "decisions:$line_no: malformed JSON" 2
    fi

    local perm dec
    perm=$(echo "$line" | jq -r '.permission // ""')
    dec=$(echo "$line" | jq -r '.decision // ""')

    if [[ -z "$perm" ]]; then
      emit_error_envelope "decisions:$line_no: missing 'permission' field" 2
    fi

    case "$dec" in
      delete|promote|keep-local) ;;
      accept-danger)
        # AC-5: all 4 required fields must be non-empty and not "TODO".
        local _f
        for _f in risk rationale efficiency_justification reviewer; do
          local _v
          _v=$(echo "$line" | jq -r --arg k "$_f" '.[$k] // ""')
          if [[ -z "$_v" || "$_v" == "TODO" ]]; then
            emit_error_envelope "decisions:$line_no: accept-danger requires non-empty '$_f' (got empty or 'TODO')" 2
          fi
        done
        ;;
      "")
        emit_error_envelope "decisions:$line_no: missing 'decision' field" 2 ;;
      *)
        emit_error_envelope "decisions:$line_no: unknown decision '$dec' (expected delete|promote|keep-local|accept-danger)" 2 ;;
    esac
  done < "$DECISIONS_FILE"

  # Determine which target files need backup based on decision verbs.
  local local_file="$SETTINGS_DIR/settings.local.json"
  local main_file="$SETTINGS_DIR/settings.json"
  local needs_local_bak=0 needs_main_bak=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    local dec
    dec=$(echo "$line" | jq -r '.decision')
    case "$dec" in
      delete)  needs_local_bak=1 ;;
      promote) needs_local_bak=1; needs_main_bak=1 ;;
    esac
  done < "$DECISIONS_FILE"

  # Refuse to run if stale .bak files exist (recovery from previous
  # failed apply). Investigate manually rather than silently overwrite.
  if [[ "$needs_local_bak" -eq 1 && -f "$local_file.bak" ]]; then
    emit_error_envelope "$local_file.bak exists — recovery file from previous failed apply; investigate and remove manually" 3
  fi
  if [[ "$needs_main_bak" -eq 1 && -f "$main_file.bak" ]]; then
    emit_error_envelope "$main_file.bak exists — recovery file from previous failed apply; investigate and remove manually" 3
  fi

  # Create backups for the files we're about to mutate. Skip if the
  # source file doesn't exist (no need to back up nothing). Install the
  # ERR trap BEFORE the cp commands so a partial-backup failure (e.g.,
  # second cp fails after first succeeds) is restored, not orphaned.
  _APPLY_LOCAL_FILE="$local_file"
  _APPLY_MAIN_FILE="$main_file"
  trap apply_restore_and_exit ERR
  if [[ "$needs_local_bak" -eq 1 && -f "$local_file" ]]; then
    cp "$local_file" "$local_file.bak"
  fi
  if [[ "$needs_main_bak" -eq 1 && -f "$main_file" ]]; then
    cp "$main_file" "$main_file.bak"
  fi

  # Execution pass. delete is implemented in step 4; promote/accept-danger
  # land in steps 5-6.
  local applied=0 skipped=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    local dec perm
    dec=$(echo "$line" | jq -r '.decision')
    perm=$(echo "$line" | jq -r '.permission')
    case "$dec" in
      keep-local)
        skipped=$((skipped+1))
        ;;
      delete)
        if [[ ! -f "$local_file" ]]; then
          skipped=$((skipped+1))
          continue
        fi
        # Skip if the permission isn't actually present in local.
        if ! jq -e --arg p "$perm" '.permissions.allow | index($p) != null' "$local_file" >/dev/null 2>&1; then
          skipped=$((skipped+1))
          continue
        fi
        local tmp
        tmp=$(mktemp)
        jq --arg p "$perm" '.permissions.allow |= map(select(. != $p))' "$local_file" > "$tmp"
        mv "$tmp" "$local_file"
        applied=$((applied+1))
        ;;
      promote)
        local tmp_main tmp_local already_main
        # Append to main if not already present (idempotent).
        if [[ -f "$main_file" ]]; then
          already_main=$(jq --arg p "$perm" '.permissions.allow | index($p) != null' "$main_file")
          if [[ "$already_main" != "true" ]]; then
            tmp_main=$(mktemp)
            jq --arg p "$perm" '.permissions.allow += [$p]' "$main_file" > "$tmp_main"
            mv "$tmp_main" "$main_file"
          fi
        else
          tmp_main=$(mktemp)
          jq -n --arg p "$perm" '{permissions:{allow:[$p]}}' > "$tmp_main"
          mv "$tmp_main" "$main_file"
        fi
        # Remove from local if present.
        if [[ -f "$local_file" ]]; then
          tmp_local=$(mktemp)
          jq --arg p "$perm" '.permissions.allow |= map(select(. != $p))' "$local_file" > "$tmp_local"
          mv "$tmp_local" "$local_file"
        fi
        applied=$((applied+1))
        ;;
      accept-danger)
        # AC-3: write log entry with accept_danger:true and the four
        # required fields (already validated pre-flight). Merge into
        # .entries; existing entries are overwritten by design (re-running
        # accept-danger updates the rationale).
        local _risk _rat _eff _rev tmp_log
        _risk=$(echo "$line" | jq -r '.risk')
        _rat=$(echo "$line" | jq -r '.rationale')
        _eff=$(echo "$line" | jq -r '.efficiency_justification')
        _rev=$(echo "$line" | jq -r '.reviewer')
        if [[ ! -f "$LOG_FILE" ]]; then
          jq -n '{entries:{}}' > "$LOG_FILE"
        fi
        tmp_log=$(mktemp)
        jq --arg p "$perm" --arg risk "$_risk" --arg rat "$_rat" \
           --arg eff "$_eff" --arg rev "$_rev" \
           '.entries[$p] = {risk: $risk, rationale: $rat, efficiency_justification: $eff, reviewer: $rev, accept_danger: true}' \
           "$LOG_FILE" > "$tmp_log"
        mv "$tmp_log" "$LOG_FILE"
        applied=$((applied+1))
        ;;
    esac
  done < "$DECISIONS_FILE"

  # Cleanup backups on success.
  trap - ERR
  [[ -f "$local_file.bak" ]] && rm "$local_file.bak"
  [[ -f "$main_file.bak"  ]] && rm "$main_file.bak"

  jq -n --argjson a "$applied" --argjson s "$skipped" \
    '{applied: $a, skipped: $s, errors: []}'
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$CMD" in
  check)          cmd_check ;;
  init)           cmd_init ;;
  promote-review) cmd_promote_review ;;
  apply)          cmd_apply ;;
  *)              usage ;;
esac
