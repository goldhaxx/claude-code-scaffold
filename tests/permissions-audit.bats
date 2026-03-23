#!/usr/bin/env bats
# Tests for scripts/permissions-audit.sh
#
# Each test creates an isolated directory with fixture settings files.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/permissions-audit.sh"

setup() {
  FIXTURE=$(mktemp -d)
}

teardown() {
  rm -rf "$FIXTURE"
}


# =========================================================================
# Step 1: Script skeleton + entry parsing (AC-1 partial)
# =========================================================================

@test "check outputs valid JSON with entries array" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(ls:*)",
      "Bash(diff:*)"
    ]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  echo "$output" | jq -e '.entries | length == 3'
}

@test "each entry has permission, source, and status fields" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.entries[0].permission == "Bash(git status:*)"'
  echo "$output" | jq -e '.entries[0].source'
  echo "$output" | jq -e '.entries[0].status'
}

@test "output includes danger, unreviewed, reviewed counts" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)", "Bash(ls:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e 'has("danger")'
  echo "$output" | jq -e 'has("unreviewed")'
  echo "$output" | jq -e 'has("reviewed")'
}

@test "parses both allow and deny entries" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"],
    "deny": ["Bash(rm -rf /)*"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.entries | length == 2'
}

@test "missing settings.json exits with error" {
  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
}
