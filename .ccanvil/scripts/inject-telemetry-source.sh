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
# output: stdout classification letter on classify (A|B|C|E|F|SKIP|UNCLASSIFIED)
# output: stdout newline-delimited filenames on print-skip-list
# output: stderr UNCLASSIFIED: <file>: <reason> per unsupported shape
# output: exit-codes 0 ok, 2 usage-error, 3 unclassified-file-in-bulk-mode|unclassified-file-in-single-mode
# depends-on: jq
# depends-on: bash >= 3.2
# side-effect: rewrites-bats-files-in-place (single-file invocation modifies the named file unless already-wired)
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
  classify <file>      Print one of A|B|C|E|F|SKIP|UNCLASSIFIED to stdout.
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

# @side-effect: rewrites-bats-files-in-place
cmd_wire_single() {
  echo "ERROR: single-file wiring not yet implemented (BTS-504 Step 3+)" >&2
  exit 3
}

cmd_all() {
  echo "ERROR: --all not yet implemented (BTS-504 Step 7)" >&2
  exit 3
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
