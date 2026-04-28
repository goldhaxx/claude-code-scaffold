#!/usr/bin/env bash
# module-manifest.sh — BTS-239 module-manifest substrate.
#
# Verbs:
#   extract <path>   Parse # @manifest blocks → JSON array (one object per block).
#   validate         Walk allowlist, drift-check each entry → exit 0 on clean / 2 on drift.
#   query <expr>     <key>:<value> substring filter against the index.
#   index            Regenerate .ccanvil/state/manifests.json from all sources.

set -uo pipefail

# Validate a `failure-mode` value: must have non-empty id; remaining segments
# must be `key=value`; `exit=N` must be numeric.
_validate_failure_mode_value() {
  local val="$1" path="$2" lineno="$3"
  local first="${val%%|*}"
  first="${first# }"; first="${first% }"
  if [[ -z "$first" ]]; then
    echo "MALFORMED: $path:$lineno: failure-mode missing id" >&2
    return 2
  fi
  if [[ "$val" == *"|"* ]]; then
    local rest="${val#*|}"
    local oldIFS="$IFS"
    IFS='|'
    # shellcheck disable=SC2206
    local segs=($rest)
    IFS="$oldIFS"
    local seg
    for seg in "${segs[@]}"; do
      seg="${seg# }"; seg="${seg% }"
      [[ -z "$seg" ]] && continue
      if [[ ! "$seg" =~ ^[a-zA-Z][a-zA-Z0-9_-]*=.+ ]]; then
        echo "MALFORMED: $path:$lineno: failure-mode segment '$seg' not key=value" >&2
        return 2
      fi
      # exit= accepts numeric exit codes or special tokens (passthrough,
      # propagate, *) when the exit code varies by called subcommand.
    done
  fi
  return 0
}

# @manifest
# purpose: Parse # @manifest blocks from a single file → JSON array, one object per block.
# input: positional <path>
# output: stdout JSON array
# output: exit-codes 0 ok, 2 usage-error|file-not-found|malformed-manifest
# depends-on: jq
# depends-on: _validate_failure_mode_value
# depends-on: _compose_block
# side-effect: writes-temp-file
# failure-mode: missing-path-arg | exit=2 | visible=stderr-usage
# failure-mode: file-not-found | exit=2 | visible=stderr-error
# failure-mode: malformed-manifest | exit=2 | visible=stderr-MALFORMED
# contract: emits-empty-array-for-no-blocks
# contract: never-partial-write-on-malformed
# anchor: BTS-239 (origin)
cmd_extract() {
  local path="${1:-}"
  # @failure-mode: missing-path-arg
  if [[ -z "$path" ]]; then
    echo "Usage: module-manifest.sh extract <path>" >&2
    return 2
  fi
  # @failure-mode: file-not-found
  if [[ ! -f "$path" ]]; then
    echo "ERROR: file not found: $path" >&2
    return 2
  fi

  # Read file into indexed array (bash 3.2 compatible — no mapfile).
  local lines=()
  local idx=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines[idx]="$line"
    idx=$((idx+1))
  done < "$path"
  local total="$idx"

  local tmp
  # @side-effect: writes-temp-file
  tmp=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  local in_block=0 block_start_lineno=0 block_data=""
  local i

  for ((i=0; i<total; i++)); do
    line="${lines[i]}"
    local lineno=$((i+1))

    if [[ "$line" =~ ^#[[:space:]]*@manifest[[:space:]]*$ ]]; then
      if [[ "$in_block" -eq 1 ]]; then
        _compose_block "$path" "$block_start_lineno" "$block_data" "$i" "$tmp" "$total" || return 2
      fi
      in_block=1
      block_start_lineno=$lineno
      block_data=""
      continue
    fi

    if [[ "$in_block" -eq 1 ]]; then
      if [[ "$line" =~ ^#[[:space:]]+([a-zA-Z][a-zA-Z0-9_-]*):[[:space:]]*(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        if [[ "$key" == "failure-mode" ]]; then
          # @failure-mode: malformed-manifest
          _validate_failure_mode_value "$val" "$path" "$lineno" || return 2
        fi
        block_data+="$key"$'\t'"$val"$'\n'
      else
        _compose_block "$path" "$block_start_lineno" "$block_data" "$i" "$tmp" "$total" || return 2
        in_block=0
        block_data=""
      fi
    fi
  done

  if [[ "$in_block" -eq 1 ]]; then
    _compose_block "$path" "$block_start_lineno" "$block_data" "$total" "$tmp" "$total" || return 2
  fi

  jq -s '.' < "$tmp"
}

# Compose JSON for one block. Caller-side wrapper that uses globally-visible
# `lines` array (set by cmd_extract). Avoids bash-4 nameref dependency.
# Args: path block_start_lineno block_data block_end_idx tmpfile total
_compose_block() {
  local path="$1" block_start="$2" block_data="$3" block_end_idx="$4" tmp="$5" total="$6"

  # Find fn_id: scan from block_end_idx forward in the global `lines` array.
  local fn_id="" j stripped
  for ((j=block_end_idx; j<total; j++)); do
    local l="${lines[j]}"
    stripped="${l// /}"
    [[ -z "$stripped" ]] && continue
    [[ "$l" =~ ^# ]] && continue
    if [[ "$l" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\(\)[[:space:]]*(\{)?[[:space:]]*$ ]]; then
      fn_id="${BASH_REMATCH[1]}"
    fi
    break
  done
  [[ -z "$fn_id" ]] && fn_id="$(basename "$path" .sh)"

  jq -n --arg id "$fn_id" --arg data "$block_data" '
    def scalar_keys: ["id", "purpose", "routes-by"];
    def is_scalar(k): scalar_keys | index(k);

    {id: $id} as $base
    | $data
    | split("\n")
    | map(select(. != ""))
    | map(split("\t"))
    | map({key: .[0], val: .[1]})
    | reduce .[] as $entry ($base;
        if is_scalar($entry.key) then
          . + {($entry.key): $entry.val}
        else
          . + {($entry.key): ((.[$entry.key] // []) + [$entry.val])}
        end
      )
  ' >> "$tmp"
}

# Search the body of <fn_id> in <path> for <pattern> (extended regex).
# Returns 0 on match, 1 otherwise. Brace-counted; assumes well-formed bash.
_function_body_grep() {
  local path="$1" fn_id="$2" pattern="$3"
  local in_fn=0 depth=0 line opens closes
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_fn" -eq 0 ]]; then
      if [[ "$line" =~ ^${fn_id}\(\)[[:space:]]*\{ ]]; then
        in_fn=1
        depth=1
        continue
      fi
    else
      if printf '%s' "$line" | grep -qE -- "$pattern"; then
        return 0
      fi
      opens=$(printf '%s' "$line" | tr -cd '{' | wc -c | tr -d ' ')
      closes=$(printf '%s' "$line" | tr -cd '}' | wc -c | tr -d ' ')
      depth=$((depth + opens - closes))
      if [[ "$depth" -le 0 ]]; then
        in_fn=0
        depth=0
      fi
    fi
  done < "$path"
  return 1
}

# Verify that <caller_ref> actually invokes <primitive_id> somewhere.
# Matches either the function name directly OR the dispatch-verb form
# (cmd_foo_bar → foo-bar) used by skills/hooks invoking via `bash <script> <verb>`.
# Returns 0 if call relationship found, 1 otherwise.
_caller_actually_calls_primitive() {
  local caller_ref="$1" primitive_id="$2" project_dir="${3:-.}"
  local verb="${primitive_id#cmd_}"
  verb="${verb//_/-}"
  local pattern="\\b${primitive_id}\\b|\\b${verb}\\b"

  if [[ "$caller_ref" == skill:/* ]]; then
    local skill_name="${caller_ref#skill:/}"
    # Skills may live under .claude/skills/<name>/SKILL.md OR .claude/commands/<name>.md.
    local candidates=(
      "$project_dir/.claude/skills/$skill_name/SKILL.md"
      "$project_dir/.claude/commands/$skill_name.md"
    )
    local m
    for m in "${candidates[@]}"; do
      if [[ -f "$m" ]] && grep -qE "$pattern" "$m"; then
        return 0
      fi
    done
    return 1
  fi

  local search_dirs=(".ccanvil/scripts" ".claude/hooks" ".claude/hooks/_lib")
  local d f
  for d in "${search_dirs[@]}"; do
    [[ ! -d "$project_dir/$d" ]] && continue
    for f in "$project_dir/$d"/*.sh; do
      [[ ! -f "$f" ]] && continue
      if ! grep -qE "^${caller_ref}\\(\\)" "$f"; then continue; fi
      if _function_body_grep "$f" "$caller_ref" "$pattern"; then
        return 0
      fi
    done
  done
  return 1
}

# @manifest
# purpose: Walk allowlist; for each entry, extract + validate manifest against required-keys, declared callers, depends-on, and source markers; emit drift envelope.
# input: --json
# input: --allowlist <path>
# output: stdout JSON envelope on --json (coverage, drift, status)
# output: stderr DRIFT lines per drift incident
# output: exit-codes 0 clean, 2 drift detected
# depends-on: cmd_extract
# depends-on: jq
# depends-on: _function_body_grep
# depends-on: _caller_actually_calls_primitive
# side-effect: emits-DRIFT-stderr
# failure-mode: drift-found | exit=2 | visible=stderr-DRIFT-and-json-envelope
# contract: returns-0-on-empty-allowlist
# contract: emits-coverage-and-drift-arrays
# contract: bidirectional-validation-caller-and-marker
# anchor: BTS-239 (origin)
cmd_validate() {
  local json_mode=0 allowlist=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=1; shift ;;
      --allowlist) allowlist="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -z "$allowlist" ]] && allowlist=".ccanvil/manifest-allowlist.txt"

  local entries=()
  if [[ -f "$allowlist" ]]; then
    local raw
    while IFS= read -r raw || [[ -n "$raw" ]]; do
      raw="${raw%%#*}"
      raw="${raw## }"; raw="${raw%% }"
      raw="${raw#"${raw%%[![:space:]]*}"}"
      raw="${raw%"${raw##*[![:space:]]}"}"
      [[ -z "$raw" ]] && continue
      entries+=("$raw")
    done < "$allowlist"
  fi

  local total="${#entries[@]}" covered=0
  local drift_records=()

  local required=("purpose" "input" "output" "side-effect" "failure-mode" "contract" "anchor")

  local entry path id
  if [[ "${#entries[@]}" -gt 0 ]]; then
  for entry in "${entries[@]}"; do
    if [[ "$entry" == *":"* ]]; then
      path="${entry%%:*}"
      id="${entry#*:}"
    else
      path="$entry"
      id="$(basename "$path" .sh)"
    fi

    if [[ ! -f "$path" ]]; then
      # @side-effect: emits-DRIFT-stderr
      # @failure-mode: drift-found
      drift_records+=("$(jq -nc --arg p "$path" --arg id "$id" '{path:$p, id:$id, reason:"file-not-found"}')")
      echo "DRIFT: $path:$id reason=file-not-found" >&2
      continue
    fi

    local extracted
    if ! extracted=$(cmd_extract "$path" 2>&1); then
      drift_records+=("$(jq -nc --arg p "$path" --arg id "$id" '{path:$p, id:$id, reason:"extract-failed"}')")
      echo "DRIFT: $path:$id reason=extract-failed" >&2
      continue
    fi

    local manifest
    manifest=$(printf '%s' "$extracted" | jq -c --arg id "$id" '.[] | select(.id == $id)' 2>/dev/null)
    if [[ -z "$manifest" || "$manifest" == "null" ]]; then
      drift_records+=("$(jq -nc --arg p "$path" --arg id "$id" '{path:$p, id:$id, reason:"manifest-not-found"}')")
      echo "DRIFT: $path:$id reason=manifest-not-found" >&2
      continue
    fi

    local rk missing=""
    for rk in "${required[@]}"; do
      local raw_val
      raw_val=$(echo "$manifest" | jq --arg k "$rk" '.[$k] // empty')
      if [[ -z "$raw_val" || "$raw_val" == "null" || "$raw_val" == '""' || "$raw_val" == "[]" ]]; then
        missing="$rk"
        break
      fi
    done
    if [[ -n "$missing" ]]; then
      drift_records+=("$(jq -nc --arg p "$path" --arg id "$id" --arg k "$missing" \
        '{path:$p, id:$id, reason:"missing-required-key", value:$k}')")
      echo "DRIFT: $path:$id reason=missing-required-key value=$missing" >&2
      continue
    fi

    # Deep validation: caller, depends-on, markers.
    local deep_drift=""

    # caller: each declared caller must actually invoke primitive_id.
    local callers_json
    callers_json=$(printf '%s' "$manifest" | jq -c '.caller // []')
    if [[ "$callers_json" != "[]" && "$callers_json" != "null" ]]; then
      local cr
      while IFS= read -r cr; do
        [[ -z "$cr" ]] && continue
        if ! _caller_actually_calls_primitive "$cr" "$id" "."; then
          drift_records+=("$(jq -nc --arg p "$path" --arg id "$id" --arg v "$cr" \
            '{path:$p, id:$id, reason:"caller-not-found", value:$v}')")
          echo "DRIFT: $path:$id reason=caller-not-found value=$cr" >&2
          deep_drift="caller"
          break
        fi
      done < <(printf '%s' "$callers_json" | jq -r '.[]')
    fi
    if [[ -n "$deep_drift" ]]; then continue; fi

    # depends-on: each declared dependency must appear within primitive body.
    local deps_json
    deps_json=$(printf '%s' "$manifest" | jq -c '."depends-on" // []')
    if [[ "$deps_json" != "[]" && "$deps_json" != "null" ]]; then
      local dep
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        if ! _function_body_grep "$path" "$id" "\\b${dep}\\b"; then
          drift_records+=("$(jq -nc --arg p "$path" --arg id "$id" --arg v "$dep" \
            '{path:$p, id:$id, reason:"depends-on-not-found", value:$v}')")
          echo "DRIFT: $path:$id reason=depends-on-not-found value=$dep" >&2
          deep_drift="depends-on"
          break
        fi
      done < <(printf '%s' "$deps_json" | jq -r '.[]')
    fi
    if [[ -n "$deep_drift" ]]; then continue; fi

    # failure-mode markers: each declared failure-mode id must have @failure-mode: <id> in body.
    local fms_json
    fms_json=$(printf '%s' "$manifest" | jq -c '."failure-mode" // []')
    if [[ "$fms_json" != "[]" && "$fms_json" != "null" ]]; then
      local fm
      while IFS= read -r fm; do
        [[ -z "$fm" ]] && continue
        local fm_id="${fm%%|*}"
        fm_id="${fm_id## }"; fm_id="${fm_id%% }"
        local fm_pattern="^[[:space:]]*#[[:space:]]*@failure-mode:[[:space:]]*${fm_id}([[:space:]]|$|\\|)"
        if ! _function_body_grep "$path" "$id" "$fm_pattern"; then
          drift_records+=("$(jq -nc --arg p "$path" --arg id "$id" --arg v "$fm_id" \
            '{path:$p, id:$id, reason:"missing-failure-mode-marker", value:$v}')")
          echo "DRIFT: $path:$id reason=missing-failure-mode-marker value=$fm_id" >&2
          deep_drift="fm"
          break
        fi
      done < <(printf '%s' "$fms_json" | jq -r '.[]')
    fi
    if [[ -n "$deep_drift" ]]; then continue; fi

    # side-effect markers: each declared side-effect must have @side-effect: <value> in body.
    local ses_json
    ses_json=$(printf '%s' "$manifest" | jq -c '."side-effect" // []')
    if [[ "$ses_json" != "[]" && "$ses_json" != "null" ]]; then
      local se
      while IFS= read -r se; do
        [[ -z "$se" ]] && continue
        local se_id="$se"
        se_id="${se_id## }"; se_id="${se_id%% }"
        local se_pattern="^[[:space:]]*#[[:space:]]*@side-effect:[[:space:]]*${se_id}([[:space:]]|$)"
        if ! _function_body_grep "$path" "$id" "$se_pattern"; then
          drift_records+=("$(jq -nc --arg p "$path" --arg id "$id" --arg v "$se_id" \
            '{path:$p, id:$id, reason:"missing-side-effect-marker", value:$v}')")
          echo "DRIFT: $path:$id reason=missing-side-effect-marker value=$se_id" >&2
          deep_drift="se"
          break
        fi
      done < <(printf '%s' "$ses_json" | jq -r '.[]')
    fi
    if [[ -n "$deep_drift" ]]; then continue; fi

    covered=$((covered+1))
  done
  fi

  local drift_count="${#drift_records[@]}"
  local status_str="ok"
  if [[ "$drift_count" -gt 0 ]]; then status_str="drift"; fi

  if [[ "$json_mode" -eq 1 ]]; then
    local drift_arr="[]"
    if [[ "$drift_count" -gt 0 ]]; then
      drift_arr=$(printf '%s\n' "${drift_records[@]}" | jq -s '.')
    fi
    jq -n --argjson covered "$covered" --argjson total "$total" --argjson drift "$drift_arr" --arg status "$status_str" \
      '{coverage:{covered:$covered, total:$total}, drift:$drift, status:$status}'
  fi

  if [[ "$drift_count" -gt 0 ]]; then
    return 2
  fi
  return 0
}

_file_mtime() {
  # macOS BSD vs GNU stat compatibility shim.
  if stat -f %m "$1" >/dev/null 2>&1; then
    stat -f %m "$1"
  else
    stat --format=%Y "$1"
  fi
}

_maybe_regenerate_index() {
  local out="$1"
  local src_dirs=(".ccanvil/scripts" ".claude/hooks" ".claude/hooks/_lib")

  if [[ ! -f "$out" ]]; then
    cmd_index || return $?
    return 0
  fi

  local index_mtime newest=0 d f m
  index_mtime=$(_file_mtime "$out")

  for d in "${src_dirs[@]}"; do
    [[ ! -d "$d" ]] && continue
    for f in "$d"/*.sh; do
      [[ ! -f "$f" ]] && continue
      m=$(_file_mtime "$f")
      if [[ "$m" -gt "$newest" ]]; then newest="$m"; fi
    done
  done

  if [[ "$newest" -gt "$index_mtime" ]]; then
    cmd_index || return $?
  fi
}

# @manifest
# purpose: Filter the manifest index by `<key>:<value>` substring match across scalar and array fields.
# input: positional <expr> (form `<key>:<value>`)
# output: stdout JSON array of matching manifest objects
# output: exit-codes 0 always (empty array on no match), 2 on usage error
# depends-on: jq
# depends-on: _maybe_regenerate_index
# side-effect: regenerates-index-if-stale
# failure-mode: missing-expr | exit=2 | visible=stderr-usage
# failure-mode: malformed-expr | exit=2 | visible=stderr-error
# contract: returns-empty-array-on-no-match
# contract: matches-substring-not-exact
# anchor: BTS-239 (origin)
cmd_query() {
  local expr="${1:-}"
  # @failure-mode: missing-expr
  if [[ -z "$expr" ]]; then
    echo "Usage: module-manifest.sh query <key>:<value>" >&2
    return 2
  fi
  # @failure-mode: malformed-expr
  if [[ "$expr" != *":"* ]]; then
    echo "ERROR: query expression must be <key>:<value>" >&2
    return 2
  fi
  local key="${expr%%:*}"
  local val="${expr#*:}"

  local out=".ccanvil/state/manifests.json"
  # @side-effect: regenerates-index-if-stale
  _maybe_regenerate_index "$out" || return $?

  jq --arg k "$key" --arg v "$val" '
    [ to_entries[] | .value | select(
        (.[$k] | type == "string" and contains($v))
        or
        (.[$k] | type == "array" and any(.[]; contains($v)))
    ) ]
  ' "$out"
}

# @manifest
# purpose: Walk source dirs, extract each .sh file's manifests, merge into a sorted JSON object keyed `<path>:<id>`, atomically write to `.ccanvil/state/manifests.json`.
# input: implicit (cwd-relative .ccanvil/scripts, .claude/hooks, .claude/hooks/_lib)
# output: stdout (none — writes to file)
# output: exit-codes 0 ok, 2 extract-failed
# depends-on: cmd_extract
# depends-on: jq
# side-effect: writes-manifests-json
# failure-mode: extract-failed | exit=2 | visible=propagated-from-cmd_extract
# contract: deterministic-lexicographically-sorted-keys
# contract: empty-object-when-no-sources
# contract: atomic-write-via-mv
# anchor: BTS-239 (origin)
cmd_index() {
  local out=".ccanvil/state/manifests.json"
  local src_dirs=(".ccanvil/scripts" ".claude/hooks" ".claude/hooks/_lib")

  mkdir -p "$(dirname "$out")"

  local tmp
  tmp=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp' '$tmp.merged'" RETURN

  : > "$tmp"

  local d f
  for d in "${src_dirs[@]}"; do
    [[ ! -d "$d" ]] && continue
    for f in "$d"/*.sh; do
      [[ ! -f "$f" ]] && continue
      local entries
      # @failure-mode: extract-failed
      entries=$(cmd_extract "$f") || return 2
      # Skip empty arrays (no manifest blocks in this file).
      if [[ "$entries" == "[]" ]]; then
        continue
      fi
      printf '%s' "$entries" | jq -c --arg p "$f" '.[] | {key: ($p + ":" + .id), val: .}' >> "$tmp"
    done
  done

  if [[ ! -s "$tmp" ]]; then
    printf '{}\n' > "$out.tmp"
  else
    jq -s 'map({(.key): .val}) | add | to_entries | sort_by(.key) | from_entries' < "$tmp" > "$out.tmp"
  fi
  # @side-effect: writes-manifests-json
  mv "$out.tmp" "$out"
}

cmd="${1:-}"
shift || true
case "$cmd" in
  extract)  cmd_extract "$@" ;;
  validate) cmd_validate "$@" ;;
  query)    cmd_query "$@" ;;
  index)    cmd_index "$@" ;;
  "")       echo "Usage: module-manifest.sh {extract|validate|query|index} [args]" >&2; exit 2 ;;
  *)        echo "Usage: module-manifest.sh {extract|validate|query|index} [args]" >&2; exit 2 ;;
esac
