#!/usr/bin/env bats
# Tests for the already-initialized idempotency path of /ccanvil-init.
# Covers the preflight-side detection; the skill-level branch is tested
# via grep assertions in ccanvil-init-skill.bats.

HUB_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$HUB_ROOT/.ccanvil/scripts/ccanvil-sync.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  NODE=$(mktemp -d)
  mkdir -p "$NODE/.ccanvil/scripts"
  cp "$SCRIPT" "$NODE/.ccanvil/scripts/ccanvil-sync.sh"
  cd "$NODE"
}

teardown() {
  rm -rf "$NODE"
}

# Fixture: minimal already-initialized node — has both the bootstrap
# script and a plausible lockfile.
_init_fixture() {
  echo '{"hub_version": "abc", "synced_at": "2026-04-22", "files": {}}' \
    > "$NODE/.ccanvil/ccanvil.lock"
}

# =========================================================================
# AC-18: preflight on already-initialized node reports the mode
# =========================================================================

@test "AC-18: preflight on already-initialized node emits already-initialized" {
  _init_fixture
  local mode
  mode=$(bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init-preflight "$HUB_ROOT" \
    | jq -r '.project_mode')
  [ "$mode" = "already-initialized" ]
}

@test "AC-18: preflight on already-initialized node still produces a plan" {
  _init_fixture
  run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init-preflight "$HUB_ROOT"
  [ "$status" -eq 0 ]

  # Plan is still emitted — the skill uses it only when user picks the
  # update option.
  local total
  total=$(echo "$output" | jq '.plan | length')
  [ "$total" -gt 0 ]
}

@test "AC-18: repeat preflight on already-initialized produces identical mode" {
  _init_fixture
  local mode1 mode2
  mode1=$(bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init-preflight "$HUB_ROOT" | jq -r '.project_mode')
  mode2=$(bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" init-preflight "$HUB_ROOT" | jq -r '.project_mode')
  [ "$mode1" = "$mode2" ]
  [ "$mode1" = "already-initialized" ]
}

# =========================================================================
# AC-12 / AC-13: retrofit-check on already-initialized surfaces the mode
# without writing anything (the skill's update-mode menu relies on this
# read-only preview path)
# =========================================================================

@test "AC-12 preview: retrofit-check on already-initialized reports the mode" {
  _init_fixture
  run bash "$NODE/.ccanvil/scripts/ccanvil-sync.sh" retrofit-check "$HUB_ROOT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "^Detected mode: already-initialized"
}
