#!/usr/bin/env bats
# BTS-504 — drift-guard: every non-skip-listed hub/tests/*.bats must source
# the telemetry helper. Fails fast if any new bats file lands without
# wiring, or if the injector's skip-list and the actual files drift apart.
#
# Single source of truth for the skip-list:
#   bash .ccanvil/scripts/inject-telemetry-source.sh print-skip-list
#
# Anchored on BTS-504 AC-6.

bats_require_minimum_version 1.5.0

# BTS-497 telemetry hooks.
source "$BATS_TEST_DIRNAME/_helpers/telemetry.bash"
setup_file()    { telemetry_setup_file; }
teardown_file() { telemetry_teardown_file; }
setup()         { telemetry_setup; }
teardown()      { telemetry_teardown; }

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
INJECTOR="$REPO_ROOT/.ccanvil/scripts/inject-telemetry-source.sh"
TESTS_DIR="$REPO_ROOT/hub/tests"

# Compose the set of files that MUST carry the wiring marker (all .bats minus
# the documented skip-list). Returns one path per line.
_required_files() {
  local skip_list
  skip_list=$(bash "$INJECTOR" print-skip-list)
  local f base skip
  for f in "$TESTS_DIR"/*.bats; do
    base="$(basename "$f")"
    skip=0
    while IFS= read -r s; do
      [[ "$base" == "$s" ]] && { skip=1; break; }
    done <<< "$skip_list"
    (( skip == 0 )) && printf '%s\n' "$f"
  done
}

@test "AC-6: every non-skip-listed hub/tests/*.bats sources telemetry.bash" {
  local missing=()
  while IFS= read -r f; do
    if ! grep -qE '^source[[:space:]]+"\$BATS_TEST_DIRNAME/_helpers/telemetry\.bash"' "$f"; then
      missing+=("$(basename "$f")")
    fi
  done < <(_required_files)
  if (( ${#missing[@]} > 0 )); then
    echo "Missing telemetry wiring (${#missing[@]} files):" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "Fix: bash .ccanvil/scripts/inject-telemetry-source.sh --all" >&2
    return 1
  fi
}

@test "AC-6: skip-list entries actually exist in hub/tests/" {
  # Guard against a skip-list entry referring to a no-longer-present file —
  # would silently drop coverage. Each entry must resolve.
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    [[ -f "$TESTS_DIR/$s" ]] \
      || { echo "Skip-list entry '$s' does not exist in $TESTS_DIR" >&2; return 1; }
  done < <(bash "$INJECTOR" print-skip-list)
}
