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

  # BTS-240: markdown frontmatter branch.
  if [[ "$path" == *.md ]]; then
    _extract_markdown "$path"
    return $?
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
  if [[ -z "$fn_id" ]]; then
    # BTS-240: extension-agnostic basename fallback (handles .sh AND .md).
    local _ext="${path##*.}"
    fn_id="$(basename "$path" ".${_ext}")"
  fi

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

# BTS-240: parse YAML frontmatter `manifest:` block from a markdown file
# and emit one JSON manifest object via _compose_block. Constrained schema:
# top-level frontmatter delimited by `---`; `manifest:` key at zero indent;
# scalar values (`  key: val`) and array values (`  key:\n    - val`) only.
# Anything outside this schema → MALFORMED + exit 2.
_extract_markdown() {
  local path="$1"
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

  # No content / no frontmatter at line 0 → emit [].
  if [[ "$total" -lt 1 || "${lines[0]}" != "---" ]]; then
    jq -s '.' < "$tmp"
    return 0
  fi

  # Find the closing `---` between line 1 and EOF.
  local fm_close=-1 i
  for ((i=1; i<total; i++)); do
    if [[ "${lines[i]}" == "---" ]]; then
      fm_close="$i"
      break
    fi
  done
  if [[ "$fm_close" -lt 0 ]]; then
    echo "MALFORMED: $path: unclosed frontmatter (no closing ---)" >&2
    return 2
  fi

  # Locate `manifest:` zero-indent inside the frontmatter region.
  local mf_start=-1
  for ((i=1; i<fm_close; i++)); do
    if [[ "${lines[i]}" =~ ^manifest:[[:space:]]*$ ]]; then
      mf_start="$i"
      break
    fi
  done
  if [[ "$mf_start" -lt 0 ]]; then
    # Frontmatter present but no manifest: key → emit [].
    jq -s '.' < "$tmp"
    return 0
  fi

  # Determine end of manifest: subtree (next zero-indent non-blank line, or fm_close).
  local mf_end="$fm_close"
  for ((i=mf_start+1; i<fm_close; i++)); do
    line="${lines[i]}"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue   # YAML comments inside frontmatter — skip
    if [[ "$line" =~ ^[^[:space:]] ]]; then
      mf_end="$i"
      break
    fi
  done

  # Parse the manifest: subtree into block_data ("key\tval\n").
  local block_data=""
  local current_key="" in_array=0
  for ((i=mf_start+1; i<mf_end; i++)); do
    line="${lines[i]}"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue   # YAML comment line

    # Scalar shape: `  <key>: <value>` (2-space indent).
    if [[ "$line" =~ ^\ \ ([a-zA-Z][a-zA-Z0-9_-]*):[[:space:]]*(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      # Strip surrounding quotes.
      if [[ "$val" =~ ^\"(.*)\"$ ]]; then val="${BASH_REMATCH[1]}"; fi
      if [[ "$val" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"; fi
      if [[ -z "$val" ]]; then
        # Empty scalar → array-shape header. Subsequent `    - x` lines are children.
        current_key="$key"
        in_array=1
      else
        if [[ "$key" == "failure-mode" ]]; then
          _validate_failure_mode_value "$val" "$path" "$((i+1))" || return 2
        fi
        block_data+="$key"$'\t'"$val"$'\n'
        current_key=""
        in_array=0
      fi
      continue
    fi

    # Array element: `    - <value>` (4-space indent).
    if [[ "$line" =~ ^\ \ \ \ -[[:space:]]+(.*)$ ]]; then
      if [[ "$in_array" -ne 1 || -z "$current_key" ]]; then
        echo "MALFORMED: $path:$((i+1)): array item without parent key" >&2
        return 2
      fi
      local val="${BASH_REMATCH[1]}"
      if [[ "$val" =~ ^\"(.*)\"$ ]]; then val="${BASH_REMATCH[1]}"; fi
      if [[ "$val" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"; fi
      if [[ "$current_key" == "failure-mode" ]]; then
        _validate_failure_mode_value "$val" "$path" "$((i+1))" || return 2
      fi
      block_data+="$current_key"$'\t'"$val"$'\n'
      continue
    fi

    # Anything else inside manifest: subtree is malformed.
    echo "MALFORMED: $path:$((i+1)): unrecognized shape under manifest: ($line)" >&2
    return 2
  done

  # Compose the block. block_end_idx points past the closing `---` so the
  # _compose_block function-definition scan walks markdown body (finds nothing)
  # and falls through to the basename fallback.
  _compose_block "$path" "$((mf_start+1))" "$block_data" "$((fm_close+1))" "$tmp" "$total" || return 2

  jq -s '.' < "$tmp"
}

# Search the body of <fn_id> in <path> for <pattern> (extended regex).
# Returns 0 on match, 1 otherwise. Brace-counted; assumes well-formed bash.
_function_body_grep() {
  local path="$1" fn_id="$2" pattern="$3"
  local in_fn=0 depth=0 line opens closes fn_decl_seen=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_fn" -eq 0 ]]; then
      if [[ "$line" =~ ^${fn_id}\(\)[[:space:]]*\{ ]]; then
        in_fn=1
        depth=1
        fn_decl_seen=1
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
  # BTS-251: file-level shell fallback — when no fn() decl was found, the
  # manifest's scope is the whole file. Mirrors the markdown-body branch in
  # _target_body_grep but applies to .sh files where id == basename.
  if [[ "$fn_decl_seen" -eq 0 ]]; then
    grep -qE -- "$pattern" "$path"
    return $?
  fi
  return 1
}

# BTS-296 Phase 1.5: build a (path, id) → body-tempfile index from the
# allowlist. _target_body_grep consults the index, eliminating per-marker
# awk re-extraction (~2,800 file walks per validate run at hub scale).
#
# Index format (TSV at $MM_TARGET_BODY_INDEX):
#   <abs_path>\t<id>\t<body_tempfile_path>
# Cache files live under $MM_TARGET_BODY_DIR. On lookup miss (e.g., file-level
# shell fallback or invocation outside cmd_validate) callers fall through to
# the original awk path.
_build_target_body_index() {
  local out_index="$1" out_dir="$2" allowlist="$3"
  : > "$out_index"
  mkdir -p "$out_dir"
  [[ -f "$allowlist" ]] || return 0
  local raw path id abs body_file ctr=0
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    raw="${raw%%#*}"
    raw="${raw## }"; raw="${raw%% }"
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    [[ -z "$raw" ]] && continue

    if [[ "$raw" == *":"* ]]; then
      path="${raw%%:*}"
      id="${raw#*:}"
    else
      path="$raw"
      local _vext="${path##*.}"
      id="$(basename "$path" ".${_vext}")"
    fi

    [[ ! -f "$path" ]] && continue
    abs=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")

    ctr=$((ctr + 1))
    body_file="$out_dir/body-$ctr"

    if [[ "$path" == *.md ]]; then
      awk '
        BEGIN { fm=0; body=0 }
        /^---$/ {
          if (fm == 0) { fm=1; next }
          else if (fm == 1) { body=1; next }
        }
        body == 1 { print }
        fm == 0 { print }
      ' "$path" > "$body_file"
    else
      awk -v fn_id="$id" '
        BEGIN { in_fn=0; depth=0; fn_decl_seen=0 }
        function count_open(s,   c) { c = gsub(/\{/, "&", s); return c }
        function count_close(s,   c) { c = gsub(/\}/, "&", s); return c }
        {
          if (in_fn == 0) {
            if (match($0, "^"fn_id"\\(\\)[ \t]*\\{")) {
              fn_decl_seen=1
              in_fn=1
              print
              depth = count_open($0) - count_close($0)
              if (depth <= 0) exit
              next
            }
          } else {
            print
            depth = depth + count_open($0) - count_close($0)
            if (depth <= 0) exit
          }
        }
      ' "$path" > "$body_file"
    fi

    if [[ ! -s "$body_file" ]]; then
      rm -f "$body_file"
      continue
    fi

    printf '%s\t%s\t%s\n' "$abs" "$id" "$body_file" >> "$out_index"
  done < "$allowlist"
}

_target_body_index_lookup() {
  local index_file="$1" path="$2" id="$3"
  [[ -s "$index_file" ]] || return 1
  local abs body_file
  abs=$(cd "$(dirname "$path")" 2>/dev/null && pwd 2>/dev/null)/$(basename "$path")
  body_file=$(awk -F'\t' -v p="$abs" -v i="$id" '$1 == p && $2 == i { print $3; exit }' "$index_file")
  if [[ -n "$body_file" ]] && [[ -s "$body_file" ]]; then
    printf '%s' "$body_file"
  fi
}

# BTS-240: target-aware body grep. For .md targets, the manifest scope is
# the file's BODY (everything after the closing frontmatter `---` delimiter)
# — skipping the frontmatter avoids false-positive matches against the
# manifest declaration itself. For .sh targets, fall through to
# _function_body_grep.
_target_body_grep() {
  local path="$1" id="$2" pattern="$3"

  # BTS-296: consult the cached body when cmd_validate has populated the
  # index. Falls through to the original path on cache miss.
  if [[ -n "${MM_TARGET_BODY_INDEX:-}" ]] && [[ -s "$MM_TARGET_BODY_INDEX" ]]; then
    local _bf
    _bf=$(_target_body_index_lookup "$MM_TARGET_BODY_INDEX" "$path" "$id")
    if [[ -n "$_bf" ]]; then
      grep -qE -- "$pattern" "$_bf"
      return $?
    fi
  fi

  if [[ "$path" == *.md ]]; then
    # BTS-252: capture awk output into a var before grep, instead of piping
    # `awk | grep -qE`. Under `set -o pipefail`, the awk-grep pipe trips on
    # SIGPIPE: grep -q exits on first match, awk gets killed mid-output,
    # the pipeline returns awk's signal-exit code, and the function reports
    # no-match even though grep DID match. Manifests with bodies large
    # enough for grep to short-circuit early failed depends-on resolution
    # (regression observed on the idea skill — 305-line body). Two-step
    # capture serializes the work and isolates each step's exit code.
    local _body
    _body=$(awk '
      BEGIN { fm=0; body=0 }
      /^---$/ {
        if (fm == 0) { fm=1; next }
        else if (fm == 1) { body=1; next }
      }
      body == 1 { print }
      fm == 0 { print }   # no frontmatter at all → entire file is body
    ' "$path")
    echo "$_body" | grep -qE -- "$pattern"
    return $?
  fi
  _function_body_grep "$path" "$id" "$pattern"
}

# Verify that <caller_ref> actually invokes <primitive_id> somewhere.
# Matches either the function name directly OR the dispatch-verb form
# (cmd_foo_bar → foo-bar) used by skills/hooks invoking via `bash <script> <verb>`.
# Returns 0 if call relationship found, 1 otherwise.
# BTS-293 Phase 1: build a TSV index of (file, function, body) tuples by
# walking the search_dirs ONCE. Replaces ~7,500 per-validate-run grep+awk
# scans (BTS-282 profile) with a per-(caller, primitive) jq-grep on
# pre-extracted bodies. Bash 3.2 / awk only — no associative arrays.
#
# Index format: <abspath>\t<funcname>\t<body-with-newlines-encoded-as-\\n>
# Lookup: awk-filter by funcname → for each match, sed-decode \\n →
# grep against pattern.
_build_caller_index() {
  local out_file="$1" project_dir="${2:-.}"
  local search_dirs=(".ccanvil/scripts" ".claude/hooks" ".claude/hooks/_lib")
  : > "$out_file"
  local d f abs
  for d in "${search_dirs[@]}"; do
    [[ ! -d "$project_dir/$d" ]] && continue
    for f in "$project_dir/$d"/*.sh; do
      [[ ! -f "$f" ]] && continue
      abs=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
      awk -v path="$abs" '
        BEGIN { in_fn=0; depth=0; fn=""; body="" }
        function emit() {
          if (fn != "") {
            gsub(/\t/, " ", body)
            gsub(/\n/, "\\n", body)
            printf "%s\t%s\t%s\n", path, fn, body
          }
        }
        function count_open(s,   c) { c = gsub(/\{/, "&", s); return c }
        function count_close(s,   c) { c = gsub(/\}/, "&", s); return c }
        {
          if (in_fn == 0) {
            if (match($0, /^[a-zA-Z_][a-zA-Z_0-9]*\(\)[ \t]*\{/)) {
              fn = $0
              sub(/\(\).*/, "", fn)
              in_fn = 1
              body = $0 "\n"
              # Count braces on declaration line itself.
              depth = count_open($0) - count_close($0)
              if (depth <= 0) {
                emit()
                in_fn = 0; fn = ""; body = ""
              }
              next
            }
          } else {
            body = body $0 "\n"
            depth = depth + count_open($0) - count_close($0)
            if (depth <= 0) {
              emit()
              in_fn = 0; fn = ""; body = ""
            }
          }
        }
      ' "$f" >> "$out_file"
    done
  done
}

# BTS-293 Phase 1: lookup helper. Returns 0 if any indexed body for
# <caller_ref> matches <pattern>; 1 otherwise.
_index_caller_check() {
  local index_file="$1" caller_ref="$2" pattern="$3"
  [[ -s "$index_file" ]] || return 1
  local encoded decoded
  while IFS= read -r encoded; do
    decoded=$(printf '%s' "$encoded" | sed 's/\\n/\
/g')
    if printf '%s\n' "$decoded" | grep -qE -- "$pattern"; then
      return 0
    fi
  done < <(awk -F'\t' -v fn="$caller_ref" '$2 == fn { print $3 }' "$index_file")
  return 1
}

_caller_actually_calls_primitive() {
  local caller_ref="$1" primitive_id="$2" project_dir="${3:-.}"
  local verb="${primitive_id#cmd_}"
  verb="${verb//_/-}"
  local pattern="\\b${primitive_id}\\b|\\b${verb}\\b"

  # BTS-240: bare path-form caller (e.g. ".claude/commands/foo.md",
  # ".ccanvil/scripts/bar.sh"). The path is checked for existence and
  # grepped directly — no function-extraction.
  if [[ "$caller_ref" == */* && "$caller_ref" != skill:/* ]]; then
    local target="$project_dir/$caller_ref"
    [[ -f "$target" ]] || return 1
    grep -qE "$pattern" "$target" && return 0
    return 1
  fi

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

  # BTS-293 Phase 1: bare-form caller. Use the in-memory index when
  # cmd_validate has populated MM_CALLER_INDEX (the common path); fall
  # back to the original walk when the env var is unset (preserves
  # correctness for direct callers of this helper outside cmd_validate).
  if [[ -n "${MM_CALLER_INDEX:-}" ]] && [[ -s "$MM_CALLER_INDEX" ]]; then
    _index_caller_check "$MM_CALLER_INDEX" "$caller_ref" "$pattern"
    return $?
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

  # BTS-293 Phase 1: build caller-resolution index ONCE per invocation.
  # _caller_actually_calls_primitive consults MM_CALLER_INDEX when set,
  # eliminating ~7,500 redundant grep+awk file scans per validate run.
  local _mm_caller_index _mm_target_body_index _mm_target_body_dir
  _mm_caller_index=$(mktemp)
  _mm_target_body_index=$(mktemp)
  _mm_target_body_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$_mm_caller_index' '$_mm_target_body_index' '$_mm_target_body_dir'" RETURN
  _build_caller_index "$_mm_caller_index" "."
  export MM_CALLER_INDEX="$_mm_caller_index"

  # BTS-296 Phase 1.5: build per-(path, id) body cache so _target_body_grep
  # serves depends-on / failure-mode / side-effect marker checks from
  # pre-extracted bodies instead of re-walking the source file per marker.
  _build_target_body_index "$_mm_target_body_index" "$_mm_target_body_dir" "$allowlist"
  export MM_TARGET_BODY_INDEX="$_mm_target_body_index"

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
      # BTS-240: extension-agnostic basename (handles .sh AND .md).
      local _vext="${path##*.}"
      id="$(basename "$path" ".${_vext}")"
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
        # BTS-240: _target_body_grep dispatches by extension (whole-file for .md).
        if ! _target_body_grep "$path" "$id" "\\b${dep}\\b"; then
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
    # BTS-240: marker-skip for .md paths — markdown bodies don't anchor code-paths.
    local fms_json
    fms_json=$(printf '%s' "$manifest" | jq -c '."failure-mode" // []')
    if [[ "$path" != *.md && "$fms_json" != "[]" && "$fms_json" != "null" ]]; then
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
    # BTS-240: marker-skip for .md paths.
    local ses_json
    ses_json=$(printf '%s' "$manifest" | jq -c '."side-effect" // []')
    if [[ "$path" != *.md && "$ses_json" != "[]" && "$ses_json" != "null" ]]; then
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

  # BTS-240: also watch markdown source dirs so a manifest edit in
  # .claude/skills/<n>/SKILL.md triggers index regeneration on next query.
  local md_globs=(
    ".claude/skills/*/SKILL.md"
    ".claude/rules/*.md"
    ".claude/agents/*.md"
    ".claude/commands/*.md"
  )
  local g
  for g in "${md_globs[@]}"; do
    for f in $g; do
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
# purpose: Filter the manifest index by `<key>:<value>` substring match across scalar and array fields, OR by targeted lens flags (--by-side-effect, --callers-of, --depends-on, --by-failure-mode) for cross-cutting structural questions.
# input: positional <expr> (form `<key>:<value>`)
# input: flag --by-side-effect <pattern>
# input: flag --callers-of <id>
# input: flag --depends-on <id>
# input: flag --by-failure-mode <pattern>
# output: stdout JSON array of matching manifest objects
# output: exit-codes 0 always (empty array on no match), 2 on usage error
# depends-on: jq
# depends-on: _maybe_regenerate_index
# side-effect: regenerates-index-if-stale
# failure-mode: missing-expr | exit=2 | visible=stderr-usage
# failure-mode: malformed-expr | exit=2 | visible=stderr-error
# failure-mode: mutually-exclusive | exit=2 | visible=stderr-error
# failure-mode: missing-flag-value | exit=2 | visible=stderr-error
# contract: returns-empty-array-on-no-match
# contract: matches-substring-not-exact
# anchor: BTS-239 (origin)
# anchor: BTS-270 (lens flags)
cmd_query() {
  # BTS-270: parse lens flags. Mutually exclusive with each other AND with the
  # positional <key>:<value> expression. Falls through to legacy positional
  # parsing when no flags are present.
  local lens_flag="" lens_value="" expr=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --by-side-effect|--callers-of|--depends-on|--by-failure-mode)
        # @failure-mode: mutually-exclusive
        if [[ -n "$lens_flag" || -n "$expr" ]]; then
          echo "ERROR: query flags are mutually exclusive" >&2
          return 2
        fi
        lens_flag="$1"
        # @failure-mode: missing-flag-value
        if [[ $# -lt 2 || -z "$2" ]]; then
          echo "ERROR: $1 requires a pattern" >&2
          return 2
        fi
        lens_value="$2"
        shift 2
        ;;
      --*)
        echo "ERROR: unknown flag: $1" >&2
        return 2
        ;;
      *)
        if [[ -n "$lens_flag" ]]; then
          echo "ERROR: query flags are mutually exclusive" >&2
          return 2
        fi
        if [[ -n "$expr" ]]; then
          echo "ERROR: only one positional expression allowed" >&2
          return 2
        fi
        expr="$1"
        shift
        ;;
    esac
  done

  # Lens-flag dispatch.
  if [[ -n "$lens_flag" ]]; then
    local out=".ccanvil/state/manifests.json"
    _maybe_regenerate_index "$out" || return $?
    case "$lens_flag" in
      --by-side-effect)
        jq --arg v "$lens_value" '
          [ to_entries[]
            | .key as $k | .value as $m
            | select(($m["side-effect"] // []) | any(contains($v)))
            | {id: $m.id, path: ($k | split(":")[0]),
               "side-effect": [($m["side-effect"] // [])[] | select(contains($v))]}
          ]' "$out"
        ;;
      --callers-of)
        # Match either literal id OR skill: form mapping.
        jq --arg v "$lens_value" '
          ($v | sub("^.*\\.claude/skills/"; "") | sub("/SKILL\\.md.*"; "")) as $maybe_skill |
          [ to_entries[]
            | .key as $k | .value as $m
            | select(($m.caller // []) | any(. == $v or . == "skill:/" + $maybe_skill))
            | {id: $m.id, path: ($k | split(":")[0]),
               caller: [($m.caller // [])[] | select(. == $v or . == "skill:/" + $maybe_skill)]}
          ]' "$out"
        ;;
      --depends-on)
        jq --arg v "$lens_value" '
          [ to_entries[]
            | .key as $k | .value as $m
            | select(($m["depends-on"] // []) | any(. == $v))
            | {id: $m.id, path: ($k | split(":")[0]),
               "depends-on": [($m["depends-on"] // [])[] | select(. == $v)]}
          ]' "$out"
        ;;
      --by-failure-mode)
        jq --arg v "$lens_value" '
          [ to_entries[]
            | .key as $k | .value as $m
            | select(($m["failure-mode"] // []) | any(contains($v)))
            | {id: $m.id, path: ($k | split(":")[0]),
               "failure-mode": [($m["failure-mode"] // [])[] | select(contains($v))]}
          ]' "$out"
        ;;
    esac
    return 0
  fi

  # Legacy positional shape: <key>:<value>.
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

  # BTS-240: markdown source-dir walks. Each glob pattern emits zero or
  # more .md files. Manifests are extracted via the same cmd_extract path.
  local md_globs=(
    ".claude/skills/*/SKILL.md"
    ".claude/rules/*.md"
    ".claude/agents/*.md"
    ".claude/commands/*.md"
  )
  local g
  for g in "${md_globs[@]}"; do
    for f in $g; do
      [[ ! -f "$f" ]] && continue
      local entries
      entries=$(cmd_extract "$f") || return 2
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

# @manifest
# purpose: Walk a downstream-node substrate and emit a proposed manifest allowlist on stdout, in canonical format with section headers, deduped against an existing allowlist when present.
# input: flag --dir <path> (default cwd)
# output: stdout proposed-allowlist text
# output: exit-codes 0 ok, 2 usage-error|directory-not-found
# depends-on: grep
# depends-on: awk
# side-effect: reads-substrate-and-existing-allowlist
# failure-mode: usage-error | exit=2 | visible=stderr-usage
# failure-mode: directory-not-found | exit=2 | visible=stderr-error
# contract: empty-substrate-emits-empty-stdout
# contract: dedup-against-existing-allowlist-when-present
# contract: section-headers-only-when-section-has-entries
# anchor: BTS-267 (origin)
cmd_seed_allowlist() {
  local dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir) dir="$2"; shift 2 ;;
      # @failure-mode: usage-error
      *)     echo "Usage: module-manifest.sh seed-allowlist [--dir <path>]" >&2; return 2 ;;
    esac
  done
  # @failure-mode: directory-not-found
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: directory not found: $dir" >&2
    return 2
  fi
  # @side-effect: reads-substrate-and-existing-allowlist

  (
    cd "$dir" || exit 2

    # Read existing allowlist into a dedup set (when present).
    local existing="" allow=".ccanvil/manifest-allowlist.txt"
    if [[ -f "$allow" ]]; then
      existing=$(grep -vE '^\s*(#|$)' "$allow" | sort -u)
    fi
    # Read hub-managed paths from .ccanvil/ccanvil.lock so the seed only
    # proposes node-owned candidates. A fresh node that just pulled has all
    # hub-distributed files in the lockfile — filtering them yields a true
    # "what's mine to manifest?" answer instead of 100+ phantom candidates.
    local hub_paths="" lock=".ccanvil/ccanvil.lock"
    if [[ -f "$lock" ]]; then
      hub_paths=$(jq -r '.files | keys[]' "$lock" 2>/dev/null || true)
    fi
    _seed_emit() {
      local entry="$1"
      # Strip optional :fn suffix to get the bare path for lockfile lookup.
      local path="${entry%%:*}"
      if [[ -n "$hub_paths" ]] && grep -qxF "$path" <<< "$hub_paths"; then
        return 0
      fi
      if [[ -n "$existing" ]] && grep -qxF "$entry" <<< "$existing"; then
        return 0
      fi
      echo "$entry"
    }

    # Render to a buffer first; emit canonical header + sectioned output once
    # all candidates are resolved. Section headers only fire when the section
    # has at least one entry — keeps empty-substrate output truly empty.
    local scripts_buf="" skills_buf="" md_buf="" hooks_buf=""
    local f fn fns
    if [[ -d .ccanvil/scripts ]]; then
      for f in .ccanvil/scripts/*.sh; do
        [[ -f "$f" ]] || continue
        fns=$(grep -oE '^cmd_[a-z_]+' "$f" | sort -u)
        if [[ -n "$fns" ]]; then
          while IFS= read -r fn; do
            local entry; entry=$(_seed_emit "${f}:${fn}") || true
            [[ -n "$entry" ]] && scripts_buf+="${entry}"$'\n'
          done <<< "$fns"
        else
          local entry; entry=$(_seed_emit "$f") || true
          [[ -n "$entry" ]] && scripts_buf+="${entry}"$'\n'
        fi
      done
    fi

    # Skills — frontmatter `name:` resolves the manifest id.
    local skill_dir name
    if [[ -d .claude/skills ]]; then
      for skill_dir in .claude/skills/*/; do
        f="${skill_dir}SKILL.md"
        [[ -f "$f" ]] || continue
        name=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); gsub(/^["\x27]|["\x27]$/,""); print; exit}' "$f")
        local entry
        if [[ -n "$name" ]]; then
          entry=$(_seed_emit "${f}:${name}") || true
        else
          entry=$(_seed_emit "$f") || true
        fi
        [[ -n "$entry" ]] && skills_buf+="${entry}"$'\n'
      done
    fi

    # Rules / agents / commands — basename matches manifest id, plain path emit.
    local md_dir
    for md_dir in .claude/rules .claude/agents .claude/commands; do
      [[ -d "$md_dir" ]] || continue
      for f in "$md_dir"/*.md; do
        [[ -f "$f" ]] || continue
        local entry; entry=$(_seed_emit "$f") || true
        [[ -n "$entry" ]] && md_buf+="${entry}"$'\n'
      done
    done

    # Hooks — file-level entries.
    if [[ -d .claude/hooks ]]; then
      for f in .claude/hooks/*.sh; do
        [[ -f "$f" ]] || continue
        local entry; entry=$(_seed_emit "$f") || true
        [[ -n "$entry" ]] && hooks_buf+="${entry}"$'\n'
      done
    fi

    # Render. Header is conditional on having at least one entry — empty
    # substrate (AC-3) emits nothing.
    if [[ -n "$scripts_buf$skills_buf$md_buf$hooks_buf" ]]; then
      echo "# Proposed manifest allowlist (BTS-267 seed-allowlist)."
      echo "# Review entries below, then pipe to .ccanvil/manifest-allowlist.txt."
      echo
      [[ -n "$scripts_buf" ]] && { echo "# Shell scripts"; printf '%s' "$scripts_buf"; echo; }
      [[ -n "$skills_buf"  ]] && { echo "# Skills";        printf '%s' "$skills_buf";  echo; }
      [[ -n "$md_buf"      ]] && { echo "# Rules / agents / commands"; printf '%s' "$md_buf"; echo; }
      [[ -n "$hooks_buf"   ]] && { echo "# Hooks";         printf '%s' "$hooks_buf"; }
    fi
    exit 0
  )
}

# Walk a unified diff and emit a JSON object per touched file with its added-line
# blob. Output: NDJSON, one object per file: {path, is_new, added}.
# `added` is an array of strings (the +-prefix-stripped added lines).
_diff_files_added() {
  local diff_file="$1"
  awk '
    /^diff --git / { flush(); cur=""; isnew=0; next }
    /^new file mode/ { isnew=1; next }
    /^--- / { next }
    /^\+\+\+ / {
      flush()
      cur=$2
      sub(/^b\//, "", cur)
      next
    }
    /^@@/ {
      in_hunk=1
      # Extract enclosing function context (everything after the second `@@`).
      ctx=""
      m=match($0, /@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)? @@/)
      if (m > 0) {
        rest=substr($0, m + RLENGTH)
        sub(/^[[:space:]]+/, "", rest)
        ctx=rest
      }
      hunk_ctx=ctx
      next
    }
    in_hunk && /^\+/ {
      line=$0
      sub(/^\+/, "", line)
      if (cur != "") {
        added[++count]=line
        added_ctx[count]=hunk_ctx
      }
    }
    # context (" ") or removed ("-") lines — ignored intentionally.
    function flush() {
      if (cur != "" && count > 0) {
        printf "{\"path\":\"%s\",\"is_new\":%d,\"added\":[", cur, isnew
        for (i=1; i<=count; i++) {
          gsub(/\\/, "\\\\", added[i])
          gsub(/"/, "\\\"", added[i])
          gsub(/\t/, "\\t", added[i])
          gsub(/\\/, "\\\\", added_ctx[i])
          gsub(/"/, "\\\"", added_ctx[i])
          if (i>1) printf ","
          printf "{\"text\":\"%s\",\"ctx\":\"%s\"}", added[i], added_ctx[i]
        }
        printf "]}\n"
      }
      delete added; delete added_ctx; count=0; in_hunk=0
    }
    END { flush() }
  ' "$diff_file"
}

# Given a hunk context string (whatever follows the `@@` anchor) and a file path,
# return the manifested primitive id this hunk is inside, or empty.
# Examples of context:
#   "cmd_query() {"    → cmd_query
#   "function foo() {" → foo
#   ""                  → empty (file-level scope or unknown)
_diff_ctx_to_primitive_id() {
  local ctx="$1"
  if [[ "$ctx" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\(\) ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Read allowlist into two parallel arrays (function-level only for now):
#   ALLOW_FN_PATH[cmd_X]=<path>
#   ALLOW_FN_ID[cmd_X]=cmd_X
# File-level entries are tracked separately; this helper handles function-level.
_diff_load_function_allowlist() {
  local allow="${1:-.ccanvil/manifest-allowlist.txt}"
  [[ -f "$allow" ]] || return 0
  local raw path fn
  while IFS= read -r raw; do
    [[ "$raw" =~ ^[[:space:]]*($|#) ]] && continue
    if [[ "$raw" == *:* ]]; then
      path="${raw%%:*}"
      fn="${raw##*:}"
      # function-level entries only — skill manifests use :<name> too,
      # filter to cmd_*-style ids.
      [[ "$fn" =~ ^cmd_ ]] || continue
      printf '%s\t%s\n' "$fn" "$path"
    fi
  done < "$allow"
}

# Read manifest's `caller:` array for a given primitive.
# Args: <containing-file> <fn-id>
# Output: one caller value per line.
_diff_get_callers() {
  local path="$1" id="$2"
  cmd_extract "$path" 2>/dev/null \
    | jq -r --arg id "$id" '.[] | select(.id == $id) | .caller // [] | .[]?'
}

# Normalize a caller-eligible path to its skill: form (if applicable) for
# matching against manifest declarations.
# .claude/skills/<n>/SKILL.md  → skill:/<n>
# .claude/commands/<n>.md      → skill:/<n>
# Otherwise: echo the literal path (path-form match).
_diff_normalize_caller_path() {
  local path="$1"
  if [[ "$path" =~ ^\.claude/skills/([^/]+)/SKILL\.md$ ]]; then
    echo "skill:/${BASH_REMATCH[1]}"
  elif [[ "$path" =~ ^\.claude/commands/([^/]+)\.md$ ]]; then
    echo "skill:/${BASH_REMATCH[1]}"
  else
    echo "$path"
  fi
}

# @manifest
# purpose: Walk a unified diff and detect manifest-drift introduced by added lines (new caller / new depends-on / new exit path / new side-effect not declared) — deterministic Layer 3 gate that replaces operator-attention prose nudges.
# input: flag --diff <path|->
# output: stdout JSON envelope {drift:[{path,id,drift_type,value}],status:"ok"|"drift"}
# output: exit-codes 0 no-drift, 2 drift-detected|usage-error|diff-file-not-found
# depends-on: jq
# depends-on: awk
# depends-on: cmd_extract
# side-effect: reads-diff-and-allowlist
# failure-mode: usage-error | exit=2 | visible=stderr-usage
# failure-mode: diff-file-not-found | exit=2 | visible=stderr-error
# failure-mode: drift-detected | exit=2 | visible=stdout-envelope-status-drift
# contract: empty-diff-emits-empty-drift-array
# contract: drift-array-mirrors-cmd_validate-shape
# anchor: BTS-268 (origin)
cmd_diff_vs_manifest() {
  local diff_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --diff) diff_path="$2"; shift 2 ;;
      # @failure-mode: usage-error
      *)      echo "Usage: module-manifest.sh diff-vs-manifest --diff <path|->" >&2; return 2 ;;
    esac
  done
  if [[ -z "$diff_path" ]]; then
    echo "Usage: module-manifest.sh diff-vs-manifest --diff <path|->" >&2
    return 2
  fi
  # @failure-mode: diff-file-not-found
  if [[ "$diff_path" != "-" && ! -f "$diff_path" ]]; then
    echo "ERROR: diff file not found: $diff_path" >&2
    return 2
  fi

  # Stdin support: spool to tempfile, then re-enter file path.
  local tmp_diff=""
  if [[ "$diff_path" == "-" ]]; then
    tmp_diff=$(mktemp)
    # @side-effect: reads-diff-and-allowlist
    cat - > "$tmp_diff"
    diff_path="$tmp_diff"
  fi

  # Load function-level allowlist (cmd_X → path map).
  local allow_table
  allow_table=$(_diff_load_function_allowlist)

  # Walk diff files and detect new-caller drift.
  local drift_entries=""
  local files_json
  files_json=$(_diff_files_added "$diff_path")

  local file_obj path is_new added
  while IFS= read -r file_obj; do
    [[ -z "$file_obj" ]] && continue
    path=$(echo "$file_obj" | jq -r '.path')
    # Normalize this caller-eligible path for matching against manifest caller lists.
    local caller_norm
    caller_norm=$(_diff_normalize_caller_path "$path")

    # ----- new-caller drift -----
    # Caller-eligible paths: runtime-invocation surfaces only. Skip docs/specs,
    # tests, fixtures, and lockfile/allowlist text — those mention cmd_* names
    # in prose or assertions, not as callers.
    local caller_eligible=0
    case "$path" in
      .claude/skills/*/SKILL.md|.claude/commands/*.md|.claude/rules/*.md|.claude/agents/*.md|.claude/hooks/*.sh|.ccanvil/scripts/*.sh)
        caller_eligible=1
        ;;
    esac

    if (( caller_eligible == 1 )); then
      while IFS=$'\t' read -r fn primitive_path; do
        [[ -z "$fn" ]] && continue
        # Skip self-calls — if the diffed file IS the primitive's own file, those are
        # depends-on / exit / side-effect concerns, not new-caller drift.
        [[ "$path" == "$primitive_path" ]] && continue

        if echo "$file_obj" | jq -r '.added[].text' | grep -qE "\b${fn}\b"; then
          local declared_callers
          declared_callers=$(_diff_get_callers "$primitive_path" "$fn")
          if ! echo "$declared_callers" | grep -qxF "$caller_norm" \
               && ! echo "$declared_callers" | grep -qxF "$path"; then
            drift_entries+="$(jq -nc \
              --arg p "${primitive_path}:${fn}" \
              --arg id "$fn" \
              --arg v "$path" \
              '{path:$p,id:$id,drift_type:"new-caller-not-declared",value:$v}')"$'\n'
          fi
        fi
      done <<< "$allow_table"
    fi

    # ----- new-depends-on / new-exit-path / new-side-effect drift (in-body) -----
    # These only apply when the diffed file is itself manifested. Per added line,
    # use the hunk context to attribute to the right primitive.
    local file_is_manifested=0
    if grep -qxF "$path" <<< "$(echo "$allow_table" | awk -F'\t' '{print $2}' | sort -u)"; then
      file_is_manifested=1
    fi

    if (( file_is_manifested == 1 )); then
      # Walk added lines via jq → tab-separated text + ctx pairs.
      local added_records line_text line_ctx prim_id manifest_json
      added_records=$(echo "$file_obj" | jq -r '.added[] | @base64')
      # Cache the file's full manifest extraction once.
      manifest_json=$(cmd_extract "$path" 2>/dev/null || echo "[]")

      while IFS= read -r b64; do
        [[ -z "$b64" ]] && continue
        line_text=$(echo "$b64" | base64 -d | jq -r '.text')
        line_ctx=$(echo "$b64" | base64 -d | jq -r '.ctx')
        prim_id=$(_diff_ctx_to_primitive_id "$line_ctx")
        # If hunk context didn't yield a primitive, skip body-scoped checks
        # (could be at file-scope; out of scope for first ramp).
        [[ -z "$prim_id" ]] && continue
        # Verify prim_id is in this file's manifest.
        local prim_obj
        prim_obj=$(echo "$manifest_json" | jq -c --arg id "$prim_id" '.[] | select(.id == $id)')
        [[ -z "$prim_obj" ]] && continue

        # ---- depends-on candidate detection ----
        # Skip self-references — when the dep token matches the host file's basename,
        # the line just mentions the script's own name (likely in prose or echo).
        local self_basename="${path##*/}"
        local deps_declared
        deps_declared=$(echo "$prim_obj" | jq -r '."depends-on" // [] | .[]?')
        local dep_token
        for dep_token in $(echo "$line_text" | grep -oE '[a-z][a-zA-Z0-9_-]*\.sh' | sort -u); do
          [[ "$dep_token" == "$self_basename" ]] && continue
          if ! grep -qxF "$dep_token" <<< "$deps_declared" \
               && ! grep -qF "$dep_token" <<< "$deps_declared"; then
            drift_entries+="$(jq -nc \
              --arg p "${path}:${prim_id}" \
              --arg id "$prim_id" \
              --arg v "$dep_token" \
              '{path:$p,id:$id,drift_type:"new-depends-on-not-declared",value:$v}')"$'\n'
          fi
        done

        # ---- new-side-effect detection ----
        # Match `# @side-effect: <id>` markers added inside the body.
        if [[ "$line_text" =~ ^[[:space:]]*#[[:space:]]*@side-effect:[[:space:]]*([A-Za-z0-9_.-]+) ]]; then
          local se_id="${BASH_REMATCH[1]}"
          local declared_se
          declared_se=$(echo "$prim_obj" | jq -r '."side-effect" // [] | .[]?')
          if ! grep -qxF "$se_id" <<< "$declared_se"; then
            drift_entries+="$(jq -nc \
              --arg p "${path}:${prim_id}" \
              --arg id "$prim_id" \
              --arg v "$se_id" \
              '{path:$p,id:$id,drift_type:"new-side-effect-not-declared",value:$v}')"$'\n'
          fi
        fi

        # ---- new-exit-path detection ----
        # Match `return N` or `exit N` (N != 0) at start-of-trimmed-line.
        if [[ "$line_text" =~ ^[[:space:]]*(return|exit)[[:space:]]+([1-9][0-9]*) ]]; then
          local exit_code="${BASH_REMATCH[2]}"
          # Read failure-mode array; extract declared exit codes via `exit=<N>` segment.
          local declared_exits
          declared_exits=$(echo "$prim_obj" \
            | jq -r '."failure-mode" // [] | .[] | capture("exit=(?<n>[0-9]+|passthrough|propagate|\\*)") // empty | .n' \
            | sort -u)
          # `*` / passthrough / propagate accept any code.
          if grep -qxE '^(\*|passthrough|propagate)$' <<< "$declared_exits"; then
            : # accepted
          elif ! grep -qxF "$exit_code" <<< "$declared_exits"; then
            drift_entries+="$(jq -nc \
              --arg p "${path}:${prim_id}" \
              --arg id "$prim_id" \
              --arg v "$exit_code" \
              '{path:$p,id:$id,drift_type:"new-exit-path-not-declared",value:$v}')"$'\n'
          fi
        fi
      done <<< "$added_records"
    fi
  done <<< "$files_json"

  # Cleanup.
  [[ -n "$tmp_diff" ]] && rm -f "$tmp_diff"

  # Render envelope.
  local drift_array
  if [[ -z "$drift_entries" ]]; then
    drift_array='[]'
  else
    drift_array=$(echo "$drift_entries" | jq -s '.')
  fi
  local status_val="ok"
  # @failure-mode: drift-detected
  [[ "$drift_array" != '[]' ]] && status_val="drift"
  jq -nc --argjson d "$drift_array" --arg s "$status_val" '{drift:$d,status:$s}'
  [[ "$status_val" == "drift" ]] && return 2 || return 0
}

# BTS-269: derive a node's cluster from its path. Path-prefix-based for v1.
_graph_node_cluster() {
  local path="$1"
  case "$path" in
    .ccanvil/scripts/*.sh)            echo "script" ;;
    .claude/hooks/*.sh)               echo "hook" ;;
    .claude/skills/*/SKILL.md)        echo "skill" ;;
    .claude/rules/*.md)               echo "rule" ;;
    .claude/agents/*.md)              echo "agent" ;;
    .claude/commands/*.md)            echo "command" ;;
    *)                                echo "other" ;;
  esac
}

# @manifest
# purpose: Emit the dependency graph (caller + depends-on edges) across all manifested entries with cluster annotations and a derived cross_cluster_edges array; default JSON envelope, optional Graphviz DOT format. Surfaces architecture-shaped change beyond what file-shaped diff review can catch.
# input: flag --format <json|dot> (default json)
# input: flag --allowlist <path> (default .ccanvil/manifest-allowlist.txt)
# output: stdout JSON envelope or DOT source
# output: exit-codes 0 ok, 2 unknown-format
# depends-on: jq
# depends-on: cmd_index
# side-effect: reads-allowlist-and-manifest-files
# failure-mode: unknown-format | exit=2 | visible=stderr-error
# contract: empty-allowlist-emits-empty-envelope-status-ok
# contract: cross_cluster_edges-only-include-edges-where-both-ends-resolve-to-nodes
# anchor: BTS-269 (origin)
# (note: removed `awk` from depends-on — not invoked in this body; jq handles all transformations.)
cmd_graph() {
  local format="json"
  local allow=".ccanvil/manifest-allowlist.txt"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format)    format="$2"; shift 2 ;;
      --allowlist) allow="$2"; shift 2 ;;
      *) echo "Usage: module-manifest.sh graph [--format json|dot] [--allowlist <path>]" >&2; return 2 ;;
    esac
  done
  # @failure-mode: unknown-format
  if [[ "$format" != "json" && "$format" != "dot" ]]; then
    echo "ERROR: unknown --format value: $format; supported: json, dot" >&2
    return 2
  fi

  # @side-effect: reads-allowlist-and-manifest-files
  # Refresh the manifest index — one-shot extract across all source files.
  # Far fewer subshell forks than per-entry cmd_extract loops; the old shape
  # could SIGBUS macOS bash 3.2 at full-allowlist scale (hundreds of forks).
  cmd_index >/dev/null 2>&1 || true
  local index_path=".ccanvil/state/manifests.json"
  local index_input="$index_path"
  [[ -f "$index_path" ]] || index_input=/dev/null

  # Build allowlist as JSON for jq consumption.
  local allow_json="[]"
  if [[ -f "$allow" ]]; then
    allow_json=$(grep -vE '^\s*(#|$)' "$allow" | jq -R -s 'split("\n") | map(select(length > 0))')
  fi

  # Compute nodes + edges + cross_cluster_edges in ONE jq invocation. Path-prefix
  # cluster mapping is encoded inside jq for portability.
  local envelope
  envelope=$(jq -nc \
    --argjson allow "$allow_json" \
    --slurpfile index_arr "$index_input" \
    '
    def cluster_of_path:
      if   test("^\\.ccanvil/scripts/.+\\.sh$") then "script"
      elif test("^\\.claude/hooks/.+\\.sh$")    then "hook"
      elif test("^\\.claude/skills/[^/]+/SKILL\\.md$") then "skill"
      elif test("^\\.claude/rules/.+\\.md$")    then "rule"
      elif test("^\\.claude/agents/.+\\.md$")   then "agent"
      elif test("^\\.claude/commands/.+\\.md$") then "command"
      else "other"
      end ;

    (($index_arr[0] // {})) as $index
    | ($allow | map(
        if test(":") then
          (split(":")[0]) as $p
          | {id: ., path: $p, cluster: ($p | cluster_of_path)}
        else
          {id: ., path: ., cluster: (. | cluster_of_path)}
        end
      )) as $nodes
    | ($nodes | map({(.id): .cluster}) | add // {}) as $cluster_of
    | ($nodes | map(.id)) as $node_ids
    | def resolve_caller(c):
        if c | test("^skill:/") then
          (c | sub("^skill:/"; "")) as $n
          | (".claude/skills/" + $n + "/SKILL.md:" + $n) as $sid
          | (".claude/commands/" + $n + ".md") as $cid
          | if ($node_ids | any(. == $sid)) then $sid
            elif ($node_ids | any(. == $cid)) then $cid
            else c end
        else c end ;
      # For each node, look up its manifest. For function-level entries, the
      # node id matches the index key directly (`<path>:<fn>`). For file-level
      # entries (bare `<path>`), the index key is `<path>:<id>` where id was
      # derived from the file — find any index entry whose key starts with
      # `<path>:` (one match per file-level entry by construction).
      [
        $nodes[]
        | . as $node
        | (
            $index[$node.id]
            // ($index | to_entries | map(select(.key | startswith($node.path + ":"))) | .[0].value)
            // null
          ) as $manifest
        | if $manifest == null then empty else
            (($manifest.caller // [])
              | .[] | {from: resolve_caller(.), to: $node.id, kind: "calls"}),
            (($manifest["depends-on"] // [])
              | .[] | {from: $node.id, to: ., kind: "depends-on"})
          end
      ] as $edges
    | [
        $edges[]
        | select(($cluster_of[.from] // null) != null and ($cluster_of[.to] // null) != null)
        | select($cluster_of[.from] != $cluster_of[.to])
        | . + {from_cluster: $cluster_of[.from], to_cluster: $cluster_of[.to]}
      ] as $cross
    | {
        nodes: $nodes,
        edges: $edges,
        cross_cluster_edges: $cross,
        status: "ok"
      }
    ')

  if [[ "$format" == "json" ]]; then
    echo "$envelope"
  else
    # DOT format: subgraphs per cluster, red cross-cluster edges. Single jq
    # invocation walks $envelope to emit DOT lines.
    echo "$envelope" | jq -r '
      . as $g
      | "digraph G {",
        "  rankdir=LR;",
        ([$g.nodes[].cluster] | unique[] as $c |
          "  subgraph cluster_\($c) {",
          "    label=\"\($c)\";",
          ($g.nodes[] | select(.cluster == $c) | "    \"\(.id)\";"),
          "  }"
        ),
        (
          ($g.cross_cluster_edges | map({(.from + "|" + .to): true}) | add // {}) as $cross_set |
          $g.edges[] | "  \"\(.from)\" -> \"\(.to)\"" +
            (if $cross_set[.from + "|" + .to] then " [color=red]" else "" end) +
            ";"
        ),
        "}"
    '
  fi
}

cmd="${1:-}"
shift || true
case "$cmd" in
  extract)          cmd_extract "$@" ;;
  validate)         cmd_validate "$@" ;;
  query)            cmd_query "$@" ;;
  index)            cmd_index "$@" ;;
  seed-allowlist)   cmd_seed_allowlist "$@" ;;
  diff-vs-manifest) cmd_diff_vs_manifest "$@" ;;
  graph)            cmd_graph "$@" ;;
  "")               echo "Usage: module-manifest.sh {extract|validate|query|index|seed-allowlist|diff-vs-manifest|graph} [args]" >&2; exit 2 ;;
  *)                echo "Usage: module-manifest.sh {extract|validate|query|index|seed-allowlist|diff-vs-manifest|graph} [args]" >&2; exit 2 ;;
esac
