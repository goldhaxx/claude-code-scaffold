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
      if [[ "$seg" =~ ^exit=(.+)$ ]]; then
        local n="${BASH_REMATCH[1]}"
        if ! [[ "$n" =~ ^[0-9]+$ ]]; then
          echo "MALFORMED: $path:$lineno: failure-mode exit=$n not numeric" >&2
          return 2
        fi
      fi
    done
  fi
  return 0
}

cmd_extract() {
  local path="${1:-}"
  if [[ -z "$path" ]]; then
    echo "Usage: module-manifest.sh extract <path>" >&2
    return 2
  fi
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

cmd_query() {
  local expr="${1:-}"
  if [[ -z "$expr" ]]; then
    echo "Usage: module-manifest.sh query <key>:<value>" >&2
    return 2
  fi
  if [[ "$expr" != *":"* ]]; then
    echo "ERROR: query expression must be <key>:<value>" >&2
    return 2
  fi
  local key="${expr%%:*}"
  local val="${expr#*:}"

  local out=".ccanvil/state/manifests.json"
  _maybe_regenerate_index "$out" || return $?

  jq --arg k "$key" --arg v "$val" '
    [ to_entries[] | .value | select(
        (.[$k] | type == "string" and contains($v))
        or
        (.[$k] | type == "array" and any(.[]; contains($v)))
    ) ]
  ' "$out"
}

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
