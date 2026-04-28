#!/usr/bin/env bats
# BTS-215: docs-check.sh usage string single-source-of-truth from dispatch table.
# Verifies the unknown-command fall-through usage string contains every verb
# registered in the top-level dispatch case — by construction (generated from
# the dispatch table itself), not by manual maintenance.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

# =========================================================================
# AC-3 sanity baseline: legacy verbs still present
# =========================================================================

@test "AC-3 baseline: usage string contains legacy verbs status, activate, land" {
  run bash "$SCRIPT" __nonexistent_subcommand_for_test__
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'status'
  echo "$output" | grep -q 'activate'
  echo "$output" | grep -q 'land'
}

# =========================================================================
# AC-3 main: previously-omitted verbs now present
# =========================================================================

@test "AC-3 main: usage string contains BTS-204+ verbs (artifact-read/write, route-of, ssot-migrate, lifecycle-state)" {
  run bash "$SCRIPT" __nonexistent_subcommand_for_test__
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'artifact-read'
  echo "$output" | grep -q 'artifact-write'
  echo "$output" | grep -q 'route-of'
  echo "$output" | grep -q 'ssot-migrate'
  echo "$output" | grep -q 'lifecycle-state'
}

@test "AC-3 main: usage string contains BTS-22+ verbs (archive-stasis, sessions-list, evidence-scan-session, stasis-carry-forward, ship-finalize)" {
  run bash "$SCRIPT" __nonexistent_subcommand_for_test__
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'archive-stasis'
  echo "$output" | grep -q 'sessions-list'
  echo "$output" | grep -q 'evidence-scan-session'
  echo "$output" | grep -q 'stasis-carry-forward'
  echo "$output" | grep -q 'ship-finalize'
}

@test "AC-3 main: usage string contains pr-title verbs (assert-pr-title, derive-pr-title) and session-info" {
  run bash "$SCRIPT" __nonexistent_subcommand_for_test__
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'assert-pr-title'
  echo "$output" | grep -q 'derive-pr-title'
  echo "$output" | grep -q 'session-info'
  echo "$output" | grep -q 'idea-template-body'
}

# =========================================================================
# AC-4 drift-guard: every dispatch verb appears in usage output
# =========================================================================

@test "AC-4 drift-guard: every dispatch case verb appears in usage output" {
  set -e
  # Extract dispatch verbs from the script itself.
  local verbs
  verbs=$(awk '
    /^case "\$cmd" in$/ { in_case=1; next }
    in_case && /^esac$/ { in_case=0 }
    in_case && /^[[:space:]]*[a-z][a-z0-9-]+\)/ {
      sub(/^[[:space:]]*/, "")
      sub(/\).*$/, "")
      print
    }
  ' "$SCRIPT")

  [ -n "$verbs" ]

  run bash "$SCRIPT" __nonexistent_subcommand_for_test__
  [ "$status" -eq 1 ]

  while IFS= read -r verb; do
    [ -z "$verb" ] && continue
    if ! echo "$output" | grep -qF "$verb"; then
      echo "MISSING: dispatch verb '$verb' not in usage output:" >&2
      echo "$output" >&2
      return 1
    fi
  done <<< "$verbs"
}

# =========================================================================
# AC-2 exit code preserved
# =========================================================================

@test "AC-2: unknown-command exit code is 1 (not 2)" {
  run bash "$SCRIPT" __nonexistent_subcommand_for_test__
  [ "$status" -eq 1 ]
}

# =========================================================================
# Drift-guard inline reference
# =========================================================================

@test "drift: BTS-215 referenced inline in docs-check.sh" {
  grep -q "BTS-215" "$SCRIPT"
}
