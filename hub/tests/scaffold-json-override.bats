#!/usr/bin/env bats
# Tests for scaffold.json + scaffold.local.json overlay merge behavior.
#
# Each test creates an isolated project directory with fixture configs.

OPERATIONS_SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude"
}

teardown() {
  rm -rf "$PROJECT"
}

# =========================================================================
# Step 1: Merge function core behavior (AC-1, AC-3, AC-4, AC-11)
# =========================================================================

@test "AC-1: both files present — deep merge produces combined result" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features":{"pr_review":false}}
EOF
  cat > "$PROJECT/.claude/scaffold.local.json" <<'EOF'
{"integrations":{"routing":{"backlog":"linear"}}}
EOF

  run bash "$OPERATIONS_SCRIPT" merge-config --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.features.pr_review == false'
  echo "$output" | jq -e '.integrations.routing.backlog == "linear"'
}

@test "AC-3: no local file — effective config equals hub file" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features":{"pr_review":false},"integrations":{}}
EOF

  run bash "$OPERATIONS_SCRIPT" merge-config --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.features.pr_review == false'
  echo "$output" | jq -e '.integrations == {}'
}

@test "AC-4: no hub file and no local file — empty JSON object, exit 0" {
  run bash "$OPERATIONS_SCRIPT" merge-config --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {}'
}

# =========================================================================
# Step 2: Node-wins conflict behavior (AC-2)
# =========================================================================

@test "AC-2: node wins on conflict — local overrides hub value" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features":{"pr_review":false}}
EOF
  cat > "$PROJECT/.claude/scaffold.local.json" <<'EOF'
{"features":{"pr_review":true}}
EOF

  run bash "$OPERATIONS_SCRIPT" merge-config --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.features.pr_review == true'
}

# =========================================================================
# Step 3: Invalid local JSON error (AC-7)
# =========================================================================

@test "AC-7: invalid local JSON exits 1 with error message" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features":{"pr_review":false}}
EOF
  echo "not valid json{{{" > "$PROJECT/.claude/scaffold.local.json"

  run bash "$OPERATIONS_SCRIPT" merge-config --project-dir "$PROJECT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ERROR: .claude/scaffold.local.json is not valid JSON"
}

# =========================================================================
# Step 4: Wire operations.sh resolve to use merged config (AC-5)
# =========================================================================

@test "AC-5: resolve uses merged config — routing in local file only" {
  # Hub has features only, no routing
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features":{"pr_review":false},"integrations":{}}
EOF
  # Local file has routing config
  cat > "$PROJECT/.claude/scaffold.local.json" <<'EOF'
{
  "integrations":{
    "routing":{"backlog":"linear"},
    "providers":{"linear":{"mechanism":"mcp","project":"Test","team":"TestTeam"}}
  }
}
EOF

  run bash "$OPERATIONS_SCRIPT" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  echo "$output" | jq -e '.mechanism == "mcp"'
}

# =========================================================================
# Step 5: Wire docs-check.sh config-get to use merged config (AC-6)
# =========================================================================

DOCS_CHECK_SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

@test "AC-6: config-get reads merged config — feature in local file only" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features":{}}
EOF
  cat > "$PROJECT/.claude/scaffold.local.json" <<'EOF'
{"features":{"pr_review":true}}
EOF

  run bash "$DOCS_CHECK_SCRIPT" config-get pr_review "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "AC-6: config-get hub default when no local override" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"features":{"pr_review":false}}
EOF

  run bash "$DOCS_CHECK_SCRIPT" config-get pr_review "$PROJECT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

# =========================================================================
# Step 6: Gitignore and claudeignore (AC-9, AC-10)
# =========================================================================

@test "AC-9: scaffold.local.json is in .gitignore" {
  grep -q 'scaffold.local.json' "$BATS_TEST_DIRNAME/../../.gitignore"
}

@test "AC-10: scaffold.local.json is in .claudeignore" {
  grep -q 'scaffold.local.json' "$BATS_TEST_DIRNAME/../../.claudeignore"
}

# =========================================================================
# Step 7: Pull safety — scaffold.json stays clean when overrides in local (AC-8)
# =========================================================================

@test "AC-8: pull-plan classifies scaffold.json as auto-update when local is clean" {
  SYNC_SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

  # Set up a "hub" scaffold with scaffold.json
  HUB=$(mktemp -d)
  mkdir -p "$HUB/.claude"
  cat > "$HUB/.claude/scaffold.json" <<'EOF'
{"features":{"pr_review":false}}
EOF

  # Set up a "node" project — init lockfile from hub
  NODE=$(mktemp -d)
  cd "$NODE"
  git init -q
  mkdir -p .claude .ccanvil
  cp "$HUB/.claude/scaffold.json" .claude/scaffold.json
  git add -A
  git commit -q -m "init"

  # Create lockfile tracking scaffold.json
  bash "$SYNC_SCRIPT" init "$HUB"

  # Node adds overrides to scaffold.local.json (not scaffold.json)
  cat > "$NODE/.claude/scaffold.local.json" <<'EOF'
{"integrations":{"routing":{"backlog":"linear"}}}
EOF
  # scaffold.local.json is gitignored — don't commit it

  # Hub changes scaffold.json (adds a feature toggle)
  cat > "$HUB/.claude/scaffold.json" <<'EOF'
{"features":{"pr_review":false,"auto_format":true}}
EOF

  # Run pull-plan — scaffold.json should be auto-update (local is clean)
  run bash "$SYNC_SCRIPT" pull-plan "$HUB"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.file == ".claude/scaffold.json") | .action == "auto-update"'

  rm -rf "$HUB" "$NODE"
}

# =========================================================================
# Step 8: Template updated (AC-12)
# =========================================================================

@test "AC-12: scaffold.json template has companion doc referencing scaffold.local.json" {
  grep -q 'scaffold.local.json' "$BATS_TEST_DIRNAME/../../.ccanvil/templates/scaffold.json.md"
}

@test "AC-11: deep merge preserves nested keys from both sides" {
  cat > "$PROJECT/.claude/scaffold.json" <<'EOF'
{"integrations":{"providers":{"github":{"mechanism":"cli"}}}}
EOF
  cat > "$PROJECT/.claude/scaffold.local.json" <<'EOF'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
EOF

  run bash "$OPERATIONS_SCRIPT" merge-config --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.integrations.providers | keys | length == 2'
  echo "$output" | jq -e '.integrations.providers.github.mechanism == "cli"'
  echo "$output" | jq -e '.integrations.providers.linear.mechanism == "mcp"'
}
