#!/usr/bin/env bash
#
# BTS-504 — telemetry-helper injector.
#
# Wires `hub/tests/_helpers/telemetry.bash` into bats test files by
# dispatching one of 5 per-category wiring actions. Idempotent: already-wired
# files are no-ops. Files matching no supported category are reported
# UNCLASSIFIED and left untouched.
#
# Categories partition the 4-tuple boolean space (has_setup_file,
# has_teardown_file, has_setup, has_teardown). See docs/spec.md
# Implementation Notes for the truth table.
#
# @manifest
# purpose: Wire BTS-497 telemetry hooks into hub/tests/*.bats by category-dispatched template; idempotent; accumulate-then-exit on bulk mode.
# input: positional <subcommand> [args]
# input: subcommands = classify <file> | --help | -h | --all [--root <dir>] | print-skip-list | <file>
# output: stdout JSON report on --all (counts: wired, already_wired, skipped, unclassified)
# output: stdout classification letter on classify (A|B|C|E|F|G|SKIP|UNCLASSIFIED)
# output: stdout newline-delimited filenames on print-skip-list
# output: stderr UNCLASSIFIED: <file>: <reason> per unsupported shape
# output: exit-codes 0 ok, 2 usage-error, 3 unclassified-file-in-bulk-mode|unclassified-file-in-single-mode
# depends-on: jq
# depends-on: bash >= 3.2
# side-effect: rewrites-bats-files-in-place
# failure-mode: unknown-subcommand | exit=2 | visible=stderr-Usage
# failure-mode: missing-file-arg | exit=2 | visible=stderr-Usage
# failure-mode: unclassified-shape | exit=3 | visible=stderr-UNCLASSIFIED
# contract: idempotent-on-wired-files
# contract: never-mutate-on-unclassified
# contract: classifier-rows-partition-disjointly
# anchor: BTS-504

set -euo pipefail

# ---------------------------------------------------------------------------
# Skip-list — files the injector intentionally leaves unwired.
# ---------------------------------------------------------------------------
# Each entry MUST carry a one-line rationale (AC-5).
SKIP_LIST=(
  # Tests the telemetry helper itself; double-sourcing would create recursion.
  "telemetry-helper.bats"
)

# ---------------------------------------------------------------------------
# Subcommand dispatch (BTS-504 Step 1 — skeleton; per-cat wiring + classify
# implemented in subsequent steps).
# ---------------------------------------------------------------------------

usage() {
  cat <<'USAGE'
Usage: inject-telemetry-source.sh <subcommand> [args]

Subcommands:
  classify <file>      Print one of A|B|C|E|F|G|SKIP|UNCLASSIFIED to stdout.
  print-skip-list      Print one filename per line for documented skip-list entries.
  --all [--root <d>]   Walk every hub/tests/*.bats (root defaults to hub/tests/);
                       inject wiring per-category; emit JSON report.
  <file>               Inject wiring into a single .bats file (idempotent).
  --help, -h           This text.
USAGE
}

cmd_print_skip_list() {
  local f
  for f in "${SKIP_LIST[@]}"; do
    printf '%s\n' "$f"
  done
}

# ---------------------------------------------------------------------------
# Classifier (BTS-504 Step 2 — AC-3).
# ---------------------------------------------------------------------------
# Reads the top of a bats file, detects line-leading function declarations
# (setup_file / teardown_file / setup / teardown), and dispatches via the
# 5-row disjoint truth table from docs/spec.md. The `setup` regex anchors to
# `^setup\(` so it can't false-positive on `setup_file()` (which starts with
# `setup_f...`, not `setup(`).

_is_skip_listed() {
  local base="$1" entry
  for entry in "${SKIP_LIST[@]}"; do
    if [[ "$base" == "$entry" ]]; then
      return 0
    fi
  done
  return 1
}

_classify_file() {
  local file="$1"
  local has_setup_file=no has_teardown_file=no has_setup=no has_teardown=no
  if grep -qE '^[[:space:]]*setup_file[[:space:]]*\([[:space:]]*\)' "$file"; then
    has_setup_file=yes
  fi
  if grep -qE '^[[:space:]]*teardown_file[[:space:]]*\([[:space:]]*\)' "$file"; then
    has_teardown_file=yes
  fi
  if grep -qE '^[[:space:]]*setup[[:space:]]*\([[:space:]]*\)' "$file"; then
    has_setup=yes
  fi
  if grep -qE '^[[:space:]]*teardown[[:space:]]*\([[:space:]]*\)' "$file"; then
    has_teardown=yes
  fi
  # Disjoint dispatch — the 5 supported rows partition the boolean space.
  # `-` separator avoids collision with bash case-pattern `|` alternation.
  case "${has_setup_file}-${has_teardown_file}-${has_setup}-${has_teardown}" in
    no-no-no-no)    echo "A" ;;
    no-no-yes-no)   echo "B" ;;
    no-no-yes-yes)  echo "C" ;;
    yes-no-yes-no)  echo "E" ;;
    yes-yes-no-no)  echo "F" ;;
    no-no-no-yes)   echo "G" ;;
    # @failure-mode: unclassified-shape
    *)              echo "UNCLASSIFIED" ;;
  esac
}

cmd_classify() {
  # @failure-mode: missing-file-arg
  if [[ $# -lt 1 ]]; then
    echo "Usage: classify <file>" >&2
    exit 2
  fi
  local file="$1"
  if [[ ! -f "$file" ]]; then
    # @failure-mode: missing-file-arg
    echo "Usage: classify: file not found: $file" >&2
    exit 2
  fi
  local base; base="$(basename "$file")"
  if _is_skip_listed "$base"; then
    echo "SKIP"
    return 0
  fi
  _classify_file "$file"
}

# ---------------------------------------------------------------------------
# Wiring templates (BTS-504 Step 3+). Mirror the BTS-497 sample exactly so
# diff-vs-reference produces identical output to hub/tests/canonical-fixtures.bats
# (Cat A) and hub/tests/lifecycle-state.bats (Cat C).
# ---------------------------------------------------------------------------

# Already-wired heuristic (preview of AC-2; full idempotency in Step 5).
_is_wired() {
  local file="$1"
  grep -qE '^source[[:space:]]+"\$BATS_TEST_DIRNAME/_helpers/telemetry\.bash"' "$file"
}

# Emit a per-category source+ADD block (always includes source + comment;
# ADD wrappers depend on which lifecycle hooks the file is missing).
# $1 = "yes|no" for each of add_setup_file add_teardown_file add_setup add_teardown.
_emit_block() {
  local add_sf="$1" add_tf="$2" add_s="$3" add_t="$4"
  printf '\n'
  printf '# BTS-497 telemetry hooks.\n'
  printf 'source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"\n'
  [[ "$add_sf" == "yes" ]] && printf 'setup_file()    { telemetry_setup_file; }\n'
  [[ "$add_tf" == "yes" ]] && printf 'teardown_file() { telemetry_teardown_file; }\n'
  [[ "$add_s"  == "yes" ]] && printf 'setup()         { telemetry_setup; }\n'
  [[ "$add_t"  == "yes" ]] && printf 'teardown()      { telemetry_teardown; }\n'
  return 0
}

# Convenience: Cat A emits all four ADDs.
_emit_cat_a_block() {
  _emit_block yes yes yes yes
}

# Apply per-category wiring: insert source+ADD block + PREPEND/APPEND inside
# existing user functions. State-machine awk emits in a single pass.
# Args: file pre_sf pre_t app_s app_tf  add_sf add_tf add_s add_t
_wire_with_directives() {
  local file="$1" pre_sf="$2" pre_t="$3" app_s="$4" app_tf="$5"
  local add_sf="$6" add_tf="$7" add_s="$8" add_t="$9"
  local tmp; tmp=$(mktemp "${file}.XXXXXX")
  local blockfile; blockfile=$(mktemp)
  _emit_block "$add_sf" "$add_tf" "$add_s" "$add_t" > "$blockfile"

  # The state-machine recognises the OPEN of a user multiline function ONLY
  # when the line ends right after `{` (optional trailing whitespace). This
  # keeps single-line ADD wrappers (e.g. `setup() { telemetry_setup; }`)
  # emitted by the block from being entered as state.
  awk -v blockfile="$blockfile" \
      -v pre_sf="$pre_sf" -v pre_t="$pre_t" \
      -v app_s="$app_s"  -v app_tf="$app_tf" '
    BEGIN { inserted = 0; state = "outside"; heredoc_id = ""; heredoc_dash = 0 }

    # Heredoc pass-through: print line, check for closing terminator, do
    # NOT process function open/close patterns while inside a heredoc.
    # Bash heredocs with quoted or unquoted IDs all close on the line
    # containing only the ID; <<- variants allow leading tabs.
    heredoc_id != "" {
      print
      if (heredoc_dash) {
        if ($0 ~ ("^[\t]*" heredoc_id "[[:space:]]*$")) {
          heredoc_id = ""; heredoc_dash = 0
        }
      } else {
        if ($0 == heredoc_id) { heredoc_id = ""; heredoc_dash = 0 }
      }
      next
    }

    # Source+ADD block insertion (once, after bats_require_minimum_version).
    !inserted && /^bats_require_minimum_version/ {
      print
      while ((getline line < blockfile) > 0) print line
      close(blockfile)
      inserted = 1
      next
    }

    # User multiline-function entry (opening brace at end of line).
    state == "outside" && /^setup_file[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*$/ {
      print
      if (pre_sf == "yes") print "  telemetry_setup_file"
      state = "in_setup_file"
      next
    }
    state == "outside" && /^teardown_file[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*$/ {
      print
      state = "in_teardown_file"
      next
    }
    state == "outside" && /^teardown[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*$/ {
      print
      if (pre_t == "yes") print "  telemetry_teardown"
      state = "in_teardown"
      next
    }
    state == "outside" && /^setup[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*$/ {
      print
      state = "in_setup"
      next
    }

    # User function close (bare `}`). Only reachable when NOT inside heredoc.
    state != "outside" && /^\}[[:space:]]*$/ {
      if (state == "in_setup" && app_s == "yes")            print "  telemetry_setup"
      if (state == "in_teardown_file" && app_tf == "yes")   print "  telemetry_teardown_file"
      print
      state = "outside"
      next
    }

    # Default: emit + check for heredoc opening on the line.
    {
      print
      # Detect heredoc opening: << optionally followed by -, optional
      # whitespace, optional quote, identifier, optional matching quote.
      # Match the LAST occurrence on the line (bash takes the rightmost
      # `<<` when multiple appear).
      tmp_s = $0
      last_start = 0
      while (match(tmp_s, /<<-?[[:space:]]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/)) {
        last_start = RSTART
        last_chunk = substr(tmp_s, RSTART, RLENGTH)
        tmp_s = substr(tmp_s, RSTART + RLENGTH)
      }
      if (last_start > 0) {
        # Strip leading <<.
        rest = last_chunk
        sub(/^<</, "", rest)
        heredoc_dash = 0
        if (substr(rest, 1, 1) == "-") { heredoc_dash = 1; rest = substr(rest, 2) }
        sub(/^[[:space:]]+/, "", rest)
        sub(/^['\''"]/, "", rest)
        sub(/['\''"]$/, "", rest)
        heredoc_id = rest
      }
    }
  ' "$file" > "$tmp" 2>/dev/null

  # Fallback: no bats_require_minimum_version line → insert after shebang.
  # We rerun with NR==1 trigger to keep the single-pass guarantee.
  if ! grep -q '^bats_require_minimum_version' "$file"; then
    awk -v blockfile="$blockfile" \
        -v pre_sf="$pre_sf" -v pre_t="$pre_t" \
        -v app_s="$app_s"  -v app_tf="$app_tf" '
      BEGIN { inserted = 0; state = "outside"; heredoc_id = ""; heredoc_dash = 0 }
      heredoc_id != "" {
        print
        if (heredoc_dash) {
          if ($0 ~ ("^[\t]*" heredoc_id "[[:space:]]*$")) { heredoc_id = ""; heredoc_dash = 0 }
        } else {
          if ($0 == heredoc_id) { heredoc_id = ""; heredoc_dash = 0 }
        }
        next
      }
      NR == 1 && !inserted {
        print
        while ((getline line < blockfile) > 0) print line
        close(blockfile)
        inserted = 1
        next
      }
      state == "outside" && /^setup_file[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*$/ {
        print; if (pre_sf == "yes") print "  telemetry_setup_file"; state = "in_setup_file"; next
      }
      state == "outside" && /^teardown_file[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*$/ {
        print; state = "in_teardown_file"; next
      }
      state == "outside" && /^teardown[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*$/ {
        print; if (pre_t == "yes") print "  telemetry_teardown"; state = "in_teardown"; next
      }
      state == "outside" && /^setup[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*$/ {
        print; state = "in_setup"; next
      }
      state != "outside" && /^\}[[:space:]]*$/ {
        if (state == "in_setup" && app_s == "yes")          print "  telemetry_setup"
        if (state == "in_teardown_file" && app_tf == "yes") print "  telemetry_teardown_file"
        print; state = "outside"; next
      }
      {
        print
        tmp_s = $0; last_start = 0
        while (match(tmp_s, /<<-?[[:space:]]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/)) {
          last_start = RSTART; last_chunk = substr(tmp_s, RSTART, RLENGTH)
          tmp_s = substr(tmp_s, RSTART + RLENGTH)
        }
        if (last_start > 0) {
          rest = last_chunk; sub(/^<</, "", rest); heredoc_dash = 0
          if (substr(rest, 1, 1) == "-") { heredoc_dash = 1; rest = substr(rest, 2) }
          sub(/^[[:space:]]+/, "", rest); sub(/^['\''"]/, "", rest); sub(/['\''"]$/, "", rest)
          heredoc_id = rest
        }
      }
    ' "$file" > "$tmp"
  fi

  rm -f "$blockfile"
  mv "$tmp" "$file"
}

# Per-category wiring. Each row of the truth table maps to one of these.
_wire_cat_a() { _wire_with_directives "$1"  no no no no   yes yes yes yes ; }
_wire_cat_b() { _wire_with_directives "$1"  no no yes no  yes yes no  yes ; }
_wire_cat_c() { _wire_with_directives "$1"  no yes yes no yes yes no  no  ; }
_wire_cat_e() { _wire_with_directives "$1"  yes no yes no no  yes no  yes ; }
_wire_cat_f() { _wire_with_directives "$1"  yes no no yes  no  no  yes yes ; }
_wire_cat_g() { _wire_with_directives "$1"  no yes no no   yes yes yes no  ; }

# @side-effect: rewrites-bats-files-in-place
cmd_wire_single() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: inject-telemetry-source.sh <file>" >&2
    exit 2
  fi
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Usage: file not found: $file" >&2
    exit 2
  fi
  # Idempotency preview (full coverage in Step 5).
  if _is_wired "$file"; then
    return 0
  fi
  local base; base="$(basename "$file")"
  if _is_skip_listed "$base"; then
    return 0
  fi
  local cat; cat="$(_classify_file "$file")"
  case "$cat" in
    A) _wire_cat_a "$file" ;;
    B) _wire_cat_b "$file" ;;
    C) _wire_cat_c "$file" ;;
    E) _wire_cat_e "$file" ;;
    F) _wire_cat_f "$file" ;;
    G) _wire_cat_g "$file" ;;
    UNCLASSIFIED)
      echo "UNCLASSIFIED: $file: shape does not match any of A|B|C|E|F|G" >&2
      exit 3
      ;;
  esac
}

cmd_all() {
  local root="hub/tests"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) shift; root="$1"; shift ;;
      *)      echo "Usage: --all [--root <dir>]" >&2; exit 2 ;;
    esac
  done
  if [[ ! -d "$root" ]]; then
    echo "Usage: --root: directory not found: $root" >&2
    exit 2
  fi

  local wired=0 already=0 skipped=0 unclassified=0
  local unclassified_files=()
  local f base cat

  # Iterate via shell glob — deterministic alphabetical order.
  shopt -s nullglob
  for f in "$root"/*.bats; do
    base="$(basename "$f")"
    if _is_skip_listed "$base"; then
      skipped=$((skipped + 1))
      continue
    fi
    if _is_wired "$f"; then
      already=$((already + 1))
      continue
    fi
    cat="$(_classify_file "$f")"
    case "$cat" in
      A) _wire_cat_a "$f"; wired=$((wired + 1)) ;;
      B) _wire_cat_b "$f"; wired=$((wired + 1)) ;;
      C) _wire_cat_c "$f"; wired=$((wired + 1)) ;;
      E) _wire_cat_e "$f"; wired=$((wired + 1)) ;;
      F) _wire_cat_f "$f"; wired=$((wired + 1)) ;;
      G) _wire_cat_g "$f"; wired=$((wired + 1)) ;;
      UNCLASSIFIED)
        # --all leaves stderr clean; unclassified_files in the JSON envelope
        # is the authoritative report. Single-file mode (cmd_wire_single)
        # is what surfaces the UNCLASSIFIED stderr line per AC-7.
        unclassified=$((unclassified + 1))
        unclassified_files+=("$f")
        ;;
    esac
  done
  shopt -u nullglob

  # JSON envelope. Compose unclassified_files JSON conditionally so an empty
  # array stays as [] rather than collapsing to [""] via the printf|jq pipeline.
  local uf_json="[]"
  if (( ${#unclassified_files[@]} > 0 )); then
    uf_json=$(printf '%s\n' "${unclassified_files[@]}" | jq -R . | jq -s .)
  fi
  jq -n \
    --arg root "$root" \
    --argjson wired "$wired" \
    --argjson already "$already" \
    --argjson skipped "$skipped" \
    --argjson unclassified "$unclassified" \
    --argjson unclassified_files "$uf_json" \
    '{root: $root, wired: $wired, already_wired: $already, skipped: $skipped, unclassified: $unclassified, unclassified_files: $unclassified_files}'

  if (( unclassified > 0 )); then
    exit 3
  fi
}

main() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi
  case "$1" in
    -h|--help)
      usage
      ;;
    print-skip-list)
      cmd_print_skip_list
      ;;
    classify)
      shift
      cmd_classify "$@"
      ;;
    --all)
      shift
      cmd_all "$@"
      ;;
    -*)
      # @failure-mode: unknown-subcommand
      echo "Usage: unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      # Single positional → treated as a target bats file in later steps.
      # For Step 1, surface a clear "not yet implemented" path that does NOT
      # collide with the "unknown subcommand → exit 2" contract: any token
      # that looks like a path/filename (ends in .bats) routes to wire-single;
      # anything else is a typo'd subcommand.
      if [[ "$1" == *.bats ]] || [[ -f "$1" ]]; then
        cmd_wire_single "$1"
      else
        # @failure-mode: unknown-subcommand
        echo "Usage: unknown subcommand: $1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
}

main "$@"
