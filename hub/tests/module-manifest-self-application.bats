#!/usr/bin/env bats
# BTS-239 Step 9: self-application — manifests for module-manifest.sh's own 4 verbs (AC-7 part 4, AC-8 base).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
}

@test "self-app: extract emits manifests for all 4 verbs (cmd_extract, cmd_validate, cmd_query, cmd_index)" {
  set -e
  run bash "$SCRIPT" extract "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 4'
  echo "$output" | jq -e '[.[].id] | sort == ["cmd_extract", "cmd_index", "cmd_query", "cmd_validate"]'
}

@test "self-app: each verb manifest has all required keys" {
  set -e
  run bash "$SCRIPT" extract "$SCRIPT"
  for vid in cmd_extract cmd_validate cmd_query cmd_index; do
    manifest=$(echo "$output" | jq -c --arg id "$vid" '.[] | select(.id == $id)')
    [ -n "$manifest" ]
    echo "$manifest" | jq -e '.purpose | type == "string" and length > 0'
    echo "$manifest" | jq -e '.input | type == "array" and length > 0'
    echo "$manifest" | jq -e '.output | type == "array" and length > 0'
    echo "$manifest" | jq -e '."side-effect" | type == "array" and length > 0'
    echo "$manifest" | jq -e '."failure-mode" | type == "array" and length > 0'
    echo "$manifest" | jq -e '.contract | type == "array" and length > 0'
    echo "$manifest" | jq -e '.anchor | type == "array" and length > 0'
  done
}

@test "self-app: full validate over allowlist exits 0 (BTS-240: now 11 entries)" {
  set -e
  cd "$REPO_ROOT"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  # BTS-240 grew the allowlist from 7 → 11 (added 4 markdown reference manifests).
  # Sessions 9-10 will grow it further. This test asserts coverage matches total
  # — the actual count check is delegated to the production drift-guard test which
  # asserts `covered == total` regardless of magnitude.
  echo "$output" | jq -e '.coverage.covered == .coverage.total'
  echo "$output" | jq -e '.coverage.covered >= 11'
  echo "$output" | jq -e '.status == "ok"'
}

@test "self-app: index includes self-described verbs" {
  set -e
  cd "$REPO_ROOT"
  bash "$SCRIPT" index >/dev/null
  for vid in cmd_extract cmd_validate cmd_query cmd_index; do
    jq -e --arg k ".ccanvil/scripts/module-manifest.sh:$vid" '.[$k] != null' .ccanvil/state/manifests.json
  done
}
