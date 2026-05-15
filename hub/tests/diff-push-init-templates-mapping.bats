#!/usr/bin/env bats
# BTS-494 — extend INIT_GITHUB_TEMPLATES helper resolution to cmd_diff + cmd_push_candidates.
#
# BTS-493 introduced _resolve_hub_relpath_for_lockfile_key and routed
# cmd_pull_plan/cmd_pull_auto/cmd_pull_apply through it. cmd_diff and
# cmd_push_candidates still computed hub_file="$hub_source/$file" raw,
# inheriting the same bug: template-mapped lockfile entries (dest path key)
# couldn't find their hub-side files (template path).

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

# ---------------------------------------------------------------------------
# Fixture: tmpdir hub + node with INIT_GITHUB_TEMPLATES entry
# ---------------------------------------------------------------------------

setup_hub_with_template() {
  HUB=$(mktemp -d)
  mkdir -p "$HUB/.ccanvil/templates/github/workflows"
  echo "$1" > "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml"
}

# Args: <local-content> [<lockfile-status>]
# Sets lockfile status field to the provided value (default "clean"). The
# hub_hash field always reflects sha256(local-content) so a "matching" state
# is the default; tests that want hash mismatch overwrite the local file
# after this helper runs.
setup_node_with_template_entry() {
  local content="$1"
  local status="${2:-clean}"
  NODE=$(mktemp -d)
  mkdir -p "$NODE/.ccanvil" "$NODE/.github/workflows"
  echo "$content" > "$NODE/.github/workflows/ccanvil-checks.yml"
  local h
  h=$(shasum -a 256 "$NODE/.github/workflows/ccanvil-checks.yml" | awk '{print $1}')
  jq -n --arg hub "$HUB" --arg h "$h" --arg s "$status" '{
    hub_source: $hub,
    files: {
      ".github/workflows/ccanvil-checks.yml": {
        origin: "hub", hub_hash: $h, local_hash: $h, status: $s, sync: "tracked"
      }
    }
  }' > "$NODE/.ccanvil/ccanvil.lock"
}

# Fixture: tmpdir hub + node with a non-template entry (regression guard)
setup_hub_with_rule() {
  HUB=$(mktemp -d)
  mkdir -p "$HUB/.claude/rules"
  echo "$1" > "$HUB/.claude/rules/tdd.md"
}

setup_node_with_rule_entry() {
  local content="$1"
  local status="${2:-clean}"
  NODE=$(mktemp -d)
  mkdir -p "$NODE/.ccanvil" "$NODE/.claude/rules"
  echo "$content" > "$NODE/.claude/rules/tdd.md"
  local h
  h=$(shasum -a 256 "$NODE/.claude/rules/tdd.md" | awk '{print $1}')
  jq -n --arg hub "$HUB" --arg h "$h" --arg s "$status" '{
    hub_source: $hub,
    files: {
      ".claude/rules/tdd.md": {
        origin: "hub", hub_hash: $h, local_hash: $h, status: $s, sync: "tracked"
      }
    }
  }' > "$NODE/.ccanvil/ccanvil.lock"
}

teardown() {
  if [[ -n "${HUB:-}" ]]; then rm -rf "$HUB"; fi
  if [[ -n "${NODE:-}" ]]; then rm -rf "$NODE"; fi
}

# ---------------------------------------------------------------------------
# Step 1 / AC-1: cmd_diff specific-file on clean template entry emits headers
# ---------------------------------------------------------------------------

@test "diff: template-mapped entry, hub identical — headers emitted, no 'File not in hub' (AC-1)" {
  setup_hub_with_template "# v1"
  setup_node_with_template_entry "# v1"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" diff .github/workflows/ccanvil-checks.yml
  [ "$status" -eq 0 ]
  [[ "$output" == *"--- hub: .github/workflows/ccanvil-checks.yml"* ]]
  [[ "$output" == *"+++ local: .github/workflows/ccanvil-checks.yml"* ]]
  [[ "$output" != *"File not in hub"* ]]
}

# ---------------------------------------------------------------------------
# Step 1 / AC-2: cmd_diff specific-file on hub-differs template entry emits body
# ---------------------------------------------------------------------------

@test "diff: template-mapped entry, hub differs — headers + non-empty diff body (AC-2)" {
  setup_hub_with_template "# v1"
  setup_node_with_template_entry "# v1"
  echo "# v2" > "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" diff .github/workflows/ccanvil-checks.yml
  [ "$status" -eq 0 ]
  [[ "$output" == *"--- hub:"* ]]
  [[ "$output" == *"+++ local:"* ]]
  # Diff body lines start with @, -, or + after the header
  [[ "$output" == *"-# v2"* || "$output" == *"+# v1"* ]]
  [[ "$output" != *"File not in hub"* ]]
}

# ---------------------------------------------------------------------------
# Step 3 / AC-3: hub template genuinely absent — still emits "File not in hub"
# ---------------------------------------------------------------------------

@test "diff: hub template genuinely absent — still emits 'File not in hub' (AC-3)" {
  HUB=$(mktemp -d)
  mkdir -p "$HUB/.ccanvil/templates/github/workflows"
  # Intentionally NO ccanvil-checks.yml in hub
  setup_node_with_template_entry "# v1"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" diff .github/workflows/ccanvil-checks.yml
  [ "$status" -eq 0 ]
  [[ "$output" == *"File not in hub: .github/workflows/ccanvil-checks.yml"* ]]
}

# ---------------------------------------------------------------------------
# Step 4 / AC-4: cmd_diff diff-all branch emits === header + body for
# modified template-mapped entry when local hash differs from lockfile hash
# ---------------------------------------------------------------------------

@test "diff (no arg): modified template-mapped entry with hash mismatch — '=== file ===' + body (AC-4)" {
  setup_hub_with_template "# v3"
  # Setup node with lockfile hash from v1; then overwrite local to v2
  setup_node_with_template_entry "# v1" modified
  echo "# v2" > "$NODE/.github/workflows/ccanvil-checks.yml"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== .github/workflows/ccanvil-checks.yml ==="* ]]
  # Body shows hub-side (v3) vs local-side (v2)
  [[ "$output" == *"-# v3"* || "$output" == *"+# v2"* ]]
}

@test "diff (no arg): clean-status template entry with local drift — '=== file ===' + body (AC-4 status=clean)" {
  # Coverage gap closure (post-review): the diff-all branch accepts both
  # status=modified AND status=clean as long as current_hash != hub_hash.
  # This sub-test exercises the clean-status code path through the helper.
  setup_hub_with_template "# v3"
  setup_node_with_template_entry "# v1" clean
  echo "# v2" > "$NODE/.github/workflows/ccanvil-checks.yml"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== .github/workflows/ccanvil-checks.yml ==="* ]]
}

# ---------------------------------------------------------------------------
# Step 5 / AC-5: cmd_push_candidates emits has_diff:true for modified
# template-mapped entry whose local content differs from hub template
# ---------------------------------------------------------------------------

@test "push-candidates: modified template-mapped entry with content divergence — has_diff:true (AC-5)" {
  setup_hub_with_template "# v1"
  setup_node_with_template_entry "# v1" modified
  echo "# v2" > "$NODE/.github/workflows/ccanvil-checks.yml"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" push-candidates
  [ "$status" -eq 0 ]
  local n file status_field has_diff
  n=$(echo "$output" | jq 'length')
  [ "$n" -eq 1 ]
  file=$(echo "$output" | jq -r '.[0].file')
  status_field=$(echo "$output" | jq -r '.[0].status')
  has_diff=$(echo "$output" | jq -r '.[0].has_diff')
  [ "$file" = ".github/workflows/ccanvil-checks.yml" ]
  [ "$status_field" = "modified" ]
  [ "$has_diff" = "true" ]
}

# ---------------------------------------------------------------------------
# Step 6 / AC-6: regression guard — non-template entries unaffected by helper
# ---------------------------------------------------------------------------

@test "diff: non-template entry, clean — headers emitted, exit 0 (AC-6 regression)" {
  setup_hub_with_rule "rule v1"
  setup_node_with_rule_entry "rule v1"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" diff .claude/rules/tdd.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"--- hub: .claude/rules/tdd.md"* ]]
  [[ "$output" == *"+++ local: .claude/rules/tdd.md"* ]]
  [[ "$output" != *"File not in hub"* ]]
}

@test "diff (no arg): modified non-template entry — '=== file ===' + body (AC-6 regression)" {
  setup_hub_with_rule "rule v3"
  setup_node_with_rule_entry "rule v1" modified
  echo "rule v2" > "$NODE/.claude/rules/tdd.md"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== .claude/rules/tdd.md ==="* ]]
}

@test "push-candidates: modified non-template entry with content divergence — has_diff:true (AC-6 regression)" {
  setup_hub_with_rule "rule v1"
  setup_node_with_rule_entry "rule v1" modified
  echo "rule v2" > "$NODE/.claude/rules/tdd.md"

  cd "$NODE"
  run --separate-stderr bash "$SCRIPT" push-candidates
  [ "$status" -eq 0 ]
  local has_diff
  has_diff=$(echo "$output" | jq -r '.[] | select(.file == ".claude/rules/tdd.md") | .has_diff')
  [ "$has_diff" = "true" ]
}
