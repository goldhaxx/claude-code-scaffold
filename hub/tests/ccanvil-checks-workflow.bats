#!/usr/bin/env bats
# BTS-488 — drift-guard for the hub-managed CI gates workflow.
#
# `.ccanvil/templates/github/workflows/ccanvil-checks.yml` is the split-out
# hub-managed gate workflow (lifecycle-docs + security). The existing
# `ci.yml` template now contains ONLY the node-customized `test:` job
# placeholder. This separation lets hub ship gate updates via broadcast
# without yaml conflicts on per-node test runner customization.

bats_require_minimum_version 1.5.0

CHECKS_YML="$BATS_TEST_DIRNAME/../../.ccanvil/templates/github/workflows/ccanvil-checks.yml"
CI_YML="$BATS_TEST_DIRNAME/../../.ccanvil/templates/github/workflows/ci.yml"
SYNC_SH="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

# ---------------------------------------------------------------------------
# AC-1: ccanvil-checks.yml shape + draft-guard + ready_for_review trigger
# ---------------------------------------------------------------------------

@test "AC-1: ccanvil-checks.yml exists" {
  [ -f "$CHECKS_YML" ]
}

@test "AC-1: ccanvil-checks.yml declares name: ccanvil-checks" {
  grep -qE '^name: ccanvil-checks' "$CHECKS_YML"
}

@test "AC-1: pull_request trigger includes ready_for_review activity type" {
  grep -qF 'ready_for_review' "$CHECKS_YML"
  grep -qE '^[[:space:]]+types:[[:space:]]+\[' "$CHECKS_YML"
}

@test "AC-1: lifecycle-docs job is declared" {
  grep -qE '^[[:space:]]*lifecycle-docs:' "$CHECKS_YML"
}

@test "AC-1: lifecycle-docs if-condition includes draft == false guard" {
  grep -qF "github.event.pull_request.draft == false" "$CHECKS_YML"
}

@test "AC-1: lifecycle-docs preserves the cleanup-required error message" {
  grep -qF 'Lifecycle docs must be cleaned up before merge' "$CHECKS_YML"
}

@test "AC-1: security job is declared" {
  grep -qE '^[[:space:]]*security:' "$CHECKS_YML"
}

@test "AC-1: security job invokes security-audit.sh" {
  grep -qF '.ccanvil/scripts/security-audit.sh' "$CHECKS_YML"
}

# ---------------------------------------------------------------------------
# AC-2: ci.yml is reduced to test-only (lifecycle-docs + security removed)
# ---------------------------------------------------------------------------

@test "AC-2: ci.yml no longer declares lifecycle-docs job" {
  ! grep -qE '^[[:space:]]*lifecycle-docs:' "$CI_YML"
}

@test "AC-2: ci.yml no longer declares security job" {
  ! grep -qE '^[[:space:]]*security:' "$CI_YML"
}

@test "AC-2: ci.yml retains test: job placeholder" {
  grep -qE '^[[:space:]]*test:' "$CI_YML"
}

@test "AC-2: ci.yml retains its NODE-SPECIFIC test placeholder comment" {
  grep -qF 'NODE-SPECIFIC' "$CI_YML"
}

# ---------------------------------------------------------------------------
# AC-3: INIT_GITHUB_TEMPLATES registers the new workflow mapping
# ---------------------------------------------------------------------------

@test "AC-3: INIT_GITHUB_TEMPLATES contains the ccanvil-checks mapping" {
  grep -qF 'workflows/ccanvil-checks.yml:.github/workflows/ccanvil-checks.yml' "$SYNC_SH"
}
