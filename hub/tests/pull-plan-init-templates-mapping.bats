#!/usr/bin/env bats
# BTS-493 — pull-plan / pull-auto / pull-apply resolve INIT_GITHUB_TEMPLATES path mappings.
#
# The three sync-side consumers historically computed `hub_file="$hub_source/$file"`
# from the lockfile key. For entries registered via INIT_GITHUB_TEMPLATES the
# lockfile key is the destination path (.github/workflows/X.yml) while the hub
# stores the file at the template path (.ccanvil/templates/github/workflows/X.yml).
# Surfaced fleet-wide after the BTS-488 heal registered ccanvil-checks.yml in
# every downstream lockfile. unifi-toolbox captured the canonical FIX evidence.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

# ---------------------------------------------------------------------------
# Step 1: helper unit tests (AC-1, AC-7)
# ---------------------------------------------------------------------------

@test "helper: resolves .github/workflows/ccanvil-checks.yml to template path" {
  source "$SCRIPT" --source-only
  result=$(_resolve_hub_relpath_for_lockfile_key ".github/workflows/ccanvil-checks.yml")
  [ "$result" = ".ccanvil/templates/github/workflows/ccanvil-checks.yml" ]
}

@test "helper: resolves .github/workflows/ci.yml to template path" {
  source "$SCRIPT" --source-only
  result=$(_resolve_hub_relpath_for_lockfile_key ".github/workflows/ci.yml")
  [ "$result" = ".ccanvil/templates/github/workflows/ci.yml" ]
}

@test "helper: resolves .github/PULL_REQUEST_TEMPLATE.md to template path" {
  source "$SCRIPT" --source-only
  result=$(_resolve_hub_relpath_for_lockfile_key ".github/PULL_REQUEST_TEMPLATE.md")
  [ "$result" = ".ccanvil/templates/github/PULL_REQUEST_TEMPLATE.md" ]
}

@test "helper: resolves README.md to template path" {
  source "$SCRIPT" --source-only
  result=$(_resolve_hub_relpath_for_lockfile_key "README.md")
  [ "$result" = ".ccanvil/templates/github/README.md" ]
}

@test "helper: resolves CONTRIBUTING.md to template path" {
  source "$SCRIPT" --source-only
  result=$(_resolve_hub_relpath_for_lockfile_key "CONTRIBUTING.md")
  [ "$result" = ".ccanvil/templates/github/CONTRIBUTING.md" ]
}

@test "helper: passthrough for non-template key (.claude/rules/tdd.md)" {
  source "$SCRIPT" --source-only
  result=$(_resolve_hub_relpath_for_lockfile_key ".claude/rules/tdd.md")
  [ "$result" = ".claude/rules/tdd.md" ]
}

@test "helper: passthrough for arbitrary deep path" {
  source "$SCRIPT" --source-only
  result=$(_resolve_hub_relpath_for_lockfile_key ".ccanvil/scripts/ccanvil-sync.sh")
  [ "$result" = ".ccanvil/scripts/ccanvil-sync.sh" ]
}

# ---------------------------------------------------------------------------
# Fixture: tmpdir hub + node with INIT_GITHUB_TEMPLATES entry registered
# ---------------------------------------------------------------------------

setup_hub_with_template() {
  HUB=$(mktemp -d)
  mkdir -p "$HUB/.ccanvil/templates/github/workflows"
  echo "$1" > "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml"
}

setup_node_with_template_entry() {
  local content="$1"
  NODE=$(mktemp -d)
  mkdir -p "$NODE/.ccanvil" "$NODE/.github/workflows"
  echo "$content" > "$NODE/.github/workflows/ccanvil-checks.yml"
  local h
  h=$(shasum -a 256 "$NODE/.github/workflows/ccanvil-checks.yml" | awk '{print $1}')
  jq -n --arg hub "$HUB" --arg h "$h" '{
    hub_source: $hub,
    files: {
      ".github/workflows/ccanvil-checks.yml": {
        origin: "hub", hub_hash: $h, local_hash: $h, status: "clean", sync: "tracked"
      }
    }
  }' > "$NODE/.ccanvil/ccanvil.lock"
}

teardown() {
  if [[ -n "${HUB:-}" ]]; then rm -rf "$HUB"; fi
  if [[ -n "${NODE:-}" ]]; then rm -rf "$NODE"; fi
}

# ---------------------------------------------------------------------------
# Step 2: cmd_pull_plan emits no entry for clean template-mapped file (AC-2)
# ---------------------------------------------------------------------------

@test "pull-plan: clean template-mapped entry produces empty plan (AC-2)" {
  setup_hub_with_template "# v1"
  setup_node_with_template_entry "# v1"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" pull-plan
  [ "$status" -eq 0 ]
  local n
  n=$(echo "$output" | jq 'length')
  [ "$n" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Step 3: hub-mutated template emits auto-update (AC-3)
# ---------------------------------------------------------------------------

@test "pull-plan: hub-mutated template emits auto-update (AC-3)" {
  setup_hub_with_template "# v1"
  setup_node_with_template_entry "# v1"
  # Mutate hub template after node lockfile fixed at v1 hash
  echo "# v2" > "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" pull-plan
  [ "$status" -eq 0 ]
  local n action file
  n=$(echo "$output" | jq 'length')
  [ "$n" -eq 1 ]
  action=$(echo "$output" | jq -r '.[0].action')
  [ "$action" = "auto-update" ]
  file=$(echo "$output" | jq -r '.[0].file')
  [ "$file" = ".github/workflows/ccanvil-checks.yml" ]
}

# ---------------------------------------------------------------------------
# Step 4: cmd_pull_auto applies template-mapped auto-update (AC-4)
# ---------------------------------------------------------------------------

@test "pull-auto: copies hub template into dest and updates lockfile (AC-4)" {
  setup_hub_with_template "# v1"
  setup_node_with_template_entry "# v1"
  echo "# v2" > "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml"
  local v2_hash
  v2_hash=$(shasum -a 256 "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml" | awk '{print $1}')

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" pull-auto
  [ "$status" -eq 0 ]

  # Dest file content matches hub v2
  local dest_content
  dest_content=$(cat "$NODE/.github/workflows/ccanvil-checks.yml")
  [ "$dest_content" = "# v2" ]

  # Lockfile reflects clean v2 on both sides
  local entry
  entry=$(jq -r '.files[".github/workflows/ccanvil-checks.yml"]' "$NODE/.ccanvil/ccanvil.lock")
  [ "$(echo "$entry" | jq -r '.hub_hash')" = "$v2_hash" ]
  [ "$(echo "$entry" | jq -r '.local_hash')" = "$v2_hash" ]
  [ "$(echo "$entry" | jq -r '.status')" = "clean" ]
}

# ---------------------------------------------------------------------------
# Step 5: cmd_pull_apply take-hub on template-mapped entry (AC-5)
# ---------------------------------------------------------------------------

@test "pull-apply take-hub: succeeds for template-mapped entry (AC-5)" {
  setup_hub_with_template "# v1"
  setup_node_with_template_entry "# v1"
  echo "# v2" > "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml"
  local v2_hash
  v2_hash=$(shasum -a 256 "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml" | awk '{print $1}')

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" pull-apply .github/workflows/ccanvil-checks.yml take-hub
  [ "$status" -eq 0 ]
  # No "Hub file not found" anywhere in stderr
  [[ ! "$stderr" =~ "Hub file not found" ]]

  # Dest file content matches hub v2
  local dest_content
  dest_content=$(cat "$NODE/.github/workflows/ccanvil-checks.yml")
  [ "$dest_content" = "# v2" ]

  # Lockfile reflects clean v2
  local entry
  entry=$(jq -r '.files[".github/workflows/ccanvil-checks.yml"]' "$NODE/.ccanvil/ccanvil.lock")
  [ "$(echo "$entry" | jq -r '.hub_hash')" = "$v2_hash" ]
  [ "$(echo "$entry" | jq -r '.local_hash')" = "$v2_hash" ]
  [ "$(echo "$entry" | jq -r '.status')" = "clean" ]
}

# ---------------------------------------------------------------------------
# Step 6: AC-6 regression guard — non-template entry classification unchanged
# ---------------------------------------------------------------------------

setup_hub_with_rule() {
  HUB=$(mktemp -d)
  mkdir -p "$HUB/.claude/rules"
  echo "$1" > "$HUB/.claude/rules/tdd.md"
}

setup_node_with_rule_entry() {
  local content="$1"
  NODE=$(mktemp -d)
  mkdir -p "$NODE/.ccanvil" "$NODE/.claude/rules"
  echo "$content" > "$NODE/.claude/rules/tdd.md"
  local h
  h=$(shasum -a 256 "$NODE/.claude/rules/tdd.md" | awk '{print $1}')
  jq -n --arg hub "$HUB" --arg h "$h" '{
    hub_source: $hub,
    files: {
      ".claude/rules/tdd.md": {
        origin: "hub", hub_hash: $h, local_hash: $h, status: "clean", sync: "tracked"
      }
    }
  }' > "$NODE/.ccanvil/ccanvil.lock"
}

@test "pull-plan: non-template entry — clean produces empty plan (AC-6 regression)" {
  setup_hub_with_rule "rule v1"
  setup_node_with_rule_entry "rule v1"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" pull-plan
  [ "$status" -eq 0 ]
  local n
  n=$(echo "$output" | jq 'length')
  [ "$n" -eq 0 ]
}

@test "pull-plan: non-template entry — hub-mutated emits auto-update (AC-6 regression)" {
  setup_hub_with_rule "rule v1"
  setup_node_with_rule_entry "rule v1"
  echo "rule v2" > "$HUB/.claude/rules/tdd.md"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" pull-plan
  [ "$status" -eq 0 ]
  local action file
  action=$(echo "$output" | jq -r '.[] | select(.file == ".claude/rules/tdd.md") | .action')
  [ "$action" = "auto-update" ]
}

@test "pull-plan: non-template entry — both-changed emits conflict (AC-6 regression)" {
  setup_hub_with_rule "rule v1"
  setup_node_with_rule_entry "rule v1"
  # Mutate both hub and local to different content
  echo "rule v2" > "$HUB/.claude/rules/tdd.md"
  echo "rule local-edit" > "$NODE/.claude/rules/tdd.md"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" pull-plan
  [ "$status" -eq 0 ]
  local action
  action=$(echo "$output" | jq -r '.[] | select(.file == ".claude/rules/tdd.md") | .action')
  [ "$action" = "conflict" ]
}

# ---------------------------------------------------------------------------
# Step 7: AC-8 — genuine-removal preservation
# ---------------------------------------------------------------------------

@test "pull-plan: genuinely-absent hub template emits removed (AC-8)" {
  # Hub does NOT have the template file; node lockfile still has the entry
  HUB=$(mktemp -d)
  mkdir -p "$HUB/.ccanvil/templates/github/workflows"
  # Intentionally NO ccanvil-checks.yml in hub

  setup_node_with_template_entry "# v1"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" pull-plan
  [ "$status" -eq 0 ]
  local n action file
  n=$(echo "$output" | jq 'length')
  [ "$n" -eq 1 ]
  action=$(echo "$output" | jq -r '.[0].action')
  [ "$action" = "removed" ]
  file=$(echo "$output" | jq -r '.[0].file')
  [ "$file" = ".github/workflows/ccanvil-checks.yml" ]
}
