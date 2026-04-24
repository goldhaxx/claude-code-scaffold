#!/usr/bin/env bats
# Tests for docs-check.sh legacy-refs-scan subcommand.
# Spec: docs/specs/stasis-recall.md AC-35 through AC-37.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  FIXTURE=$(mktemp -d)
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "legacy-refs-scan: exits 0 and emits empty array on clean project" {
  mkdir -p "$FIXTURE/.claude/rules"
  cat > "$FIXTURE/.claude/rules/workflow.md" <<'EOF'
# Workflow

Run /stasis before /compact.
Read docs/stasis.md after resume.
EOF
  run bash "$SCRIPT" legacy-refs-scan "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "0" ]
}

@test "legacy-refs-scan: exits 1 and reports matches for legacy /catchup" {
  mkdir -p "$FIXTURE/.claude/rules"
  cat > "$FIXTURE/.claude/rules/workflow.md" <<'EOF'
# Workflow

Run /catchup after /compact.
EOF
  run bash "$SCRIPT" legacy-refs-scan "$FIXTURE"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq 'length')" -ge 1 ]
  match_found=$(echo "$output" | jq -r '.[] | select(.match | contains("/catchup")) | .file')
  [[ "$match_found" == *"workflow.md"* ]]
}

@test "legacy-refs-scan: detects docs/checkpoint.md reference" {
  mkdir -p "$FIXTURE/docs"
  cat > "$FIXTURE/docs/readme.md" <<'EOF'
See docs/checkpoint.md for session state.
EOF
  run bash "$SCRIPT" legacy-refs-scan "$FIXTURE"
  [ "$status" -eq 1 ]
  match_found=$(echo "$output" | jq -r '.[] | select(.match | contains("docs/checkpoint.md")) | .file')
  [[ "$match_found" == *"readme.md"* ]]
}

@test "legacy-refs-scan: detects stale-checkpoint state name" {
  mkdir -p "$FIXTURE/scripts"
  cat > "$FIXTURE/scripts/helper.sh" <<'EOF'
if [[ "$result" == "stale-checkpoint" ]]; then
  echo "stale"
fi
EOF
  run bash "$SCRIPT" legacy-refs-scan "$FIXTURE"
  [ "$status" -eq 1 ]
  match_found=$(echo "$output" | jq -r '.[] | select(.match | contains("stale-checkpoint")) | .file')
  [[ "$match_found" == *"helper.sh"* ]]
}

@test "legacy-refs-scan: classifies hub-owned vs node-specific scope via NODE-SPECIFIC marker" {
  mkdir -p "$FIXTURE/.claude/rules"
  cat > "$FIXTURE/.claude/rules/workflow.md" <<'EOF'
# Hub content

Run /catchup after /compact.

<!-- NODE-SPECIFIC-START -->
## Local additions

Also run /checkpoint before deploys.
EOF
  run bash "$SCRIPT" legacy-refs-scan "$FIXTURE"
  [ "$status" -eq 1 ]
  scopes=$(echo "$output" | jq -r '[.[] | .scope] | unique | sort | join(",")')
  [[ "$scopes" == *"hub-owned"* ]]
  [[ "$scopes" == *"node-specific"* ]]
}

@test "legacy-refs-scan: JSON entries have file, line, match, scope keys" {
  set -e
  mkdir -p "$FIXTURE/.claude/rules"
  cat > "$FIXTURE/.claude/rules/workflow.md" <<'EOF'
Run /catchup now.
EOF
  run bash "$SCRIPT" legacy-refs-scan "$FIXTURE"
  [ "$status" -eq 1 ]
  first=$(echo "$output" | jq '.[0]')
  echo "$first" | jq -e '.file'
  echo "$first" | jq -e '.line'
  echo "$first" | jq -e '.match'
  echo "$first" | jq -e '.scope'
}

@test "legacy-refs-scan: skips binary files and .git directory" {
  mkdir -p "$FIXTURE/.git"
  echo "fake /catchup in .git" > "$FIXTURE/.git/config"
  printf '\x00\x01\x02/catchup\x03' > "$FIXTURE/binary"
  run bash "$SCRIPT" legacy-refs-scan "$FIXTURE"
  [ "$status" -eq 0 ]
}

# ============================================================================
# BTS-132 — --respect-allowlist flag
# ============================================================================

@test "BTS-132 AC-1: default behavior (no flag) returns full raw match list" {
  # Regression guard — existing callers see no change.
  mkdir -p "$FIXTURE/docs/specs"
  echo "See /catchup details." > "$FIXTURE/docs/specs/legacy.md"
  echo "Also /checkpoint here." > "$FIXTURE/README.md"
  run bash "$SCRIPT" legacy-refs-scan "$FIXTURE"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq 'length')" -eq 2 ]
}

@test "BTS-132 AC-2: --respect-allowlist filters matches whose file:line:content matches an allowlist pattern" {
  set -e
  mkdir -p "$FIXTURE/docs/specs"
  echo "See /catchup details." > "$FIXTURE/docs/specs/legacy.md"
  echo "Also /checkpoint here." > "$FIXTURE/README.md"
  # Allowlist excludes docs/specs/ so only README.md match survives.
  local allowlist="$FIXTURE/allowlist.txt"
  cat > "$allowlist" <<'EOF'
# Historical specs
^docs/specs/
EOF
  run bash "$SCRIPT" legacy-refs-scan --respect-allowlist "$allowlist" "$FIXTURE"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq 'length')" -eq 1 ]
  echo "$output" | jq -e '.[0].file == "README.md"'
}

@test "BTS-132 AC-2 edge: allowlist covers ALL matches → exit 0, empty array" {
  set -e
  mkdir -p "$FIXTURE/docs/specs"
  echo "Legacy /catchup in spec." > "$FIXTURE/docs/specs/old.md"
  local allowlist="$FIXTURE/allowlist.txt"
  echo '^docs/specs/' > "$allowlist"
  run bash "$SCRIPT" legacy-refs-scan --respect-allowlist "$allowlist" "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" -eq 0 ]
}

@test "BTS-132 AC-3: --respect-allowlist with missing file exits 2 with ERROR" {
  mkdir -p "$FIXTURE/docs"
  echo "/catchup" > "$FIXTURE/docs/readme.md"
  run bash "$SCRIPT" legacy-refs-scan --respect-allowlist /nonexistent.txt "$FIXTURE"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "ERROR" ]] || [[ "$stderr" =~ "ERROR" ]] || [[ "${output}${stderr:-}" =~ "allowlist" ]]
}

@test "BTS-132 AC-4: allowlist comments and blank lines are skipped" {
  set -e
  mkdir -p "$FIXTURE"
  echo "/checkpoint here" > "$FIXTURE/a.md"
  local allowlist="$FIXTURE/allowlist.txt"
  cat > "$allowlist" <<'EOF'
# This is a comment and should be skipped.

# Another comment
^a\.md:
EOF
  run bash "$SCRIPT" legacy-refs-scan --respect-allowlist "$allowlist" "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" -eq 0 ]
}

@test "BTS-132 AC-5: exit 0 when post-filter matches are zero, 1 when remain" {
  set -e
  mkdir -p "$FIXTURE/docs" "$FIXTURE/src"
  echo "/catchup 1" > "$FIXTURE/docs/a.md"
  echo "/catchup 2" > "$FIXTURE/src/b.sh"
  local allowlist="$FIXTURE/allowlist.txt"
  # Only covers docs/ — src/ match survives.
  echo '^docs/' > "$allowlist"
  run bash "$SCRIPT" legacy-refs-scan --respect-allowlist "$allowlist" "$FIXTURE"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq 'length')" -eq 1 ]
  echo "$output" | jq -e '.[0].file == "src/b.sh"'
}

@test "BTS-132 AC-6: output schema (file, line, match, scope) preserved after filtering" {
  set -e
  mkdir -p "$FIXTURE/src" "$FIXTURE/docs"
  echo "/catchup foo" > "$FIXTURE/src/helper.sh"
  echo "/catchup doc" > "$FIXTURE/docs/spec.md"
  local allowlist="$FIXTURE/allowlist.txt"
  echo '^docs/' > "$allowlist"
  run bash "$SCRIPT" legacy-refs-scan --respect-allowlist "$allowlist" "$FIXTURE"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.[0] | has("file") and has("line") and has("match") and has("scope")'
}
