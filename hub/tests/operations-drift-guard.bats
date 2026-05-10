#!/usr/bin/env bats
# BTS-419 — substrate-staleness drift-guard.
#
# Asserts that linear_assert_project_id_emitted enforces the contract:
# "if project_id is configured, the resolved command for any project-scoped
# verb MUST contain --project-id". Hard-fail with ALLOW_STALE_SUBSTRATE=1
# bypass.

bats_require_minimum_version 1.5.0

OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude"
}

teardown() {
  rm -rf "$PROJECT"
}

# ===========================================================================
# Step 1 — helper exists, clean pass-through paths
# ===========================================================================

@test "BTS-419 Step 1a: linear_assert_project_id_emitted is defined" {
  source "$OPS"
  declare -F linear_assert_project_id_emitted >/dev/null
}

@test "BTS-419 Step 1b: helper passes through when project_id is empty" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  output=$(linear_assert_project_id_emitted "backlog.list" "" "$input")
  [ "$output" = "$input" ]
}

@test "BTS-419 Step 1c: helper passes through when command already has --project-id" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --project-id UUID --team T"}}'
  output=$(linear_assert_project_id_emitted "backlog.list" "UUID" "$input")
  [ "$output" = "$input" ]
}
