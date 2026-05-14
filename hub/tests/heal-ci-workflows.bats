#!/usr/bin/env bats
# BTS-488 — cmd_heal_ci_workflows behavior tests.
#
# The heal verb iterates a hub-rooted registry, copies hub's ccanvil-checks.yml
# onto each reachable node, registers the file in each node's lockfile, strips
# lifecycle-docs + security blocks from each node's ci.yml, and commits. Tests
# exercise the verb against synthetic hub+node fixtures.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

# Configure git identity for any commits this test makes inside fixture nodes.
git_id() {
  local repo="$1"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
}

# Build a synthetic hub root with the ccanvil-checks.yml template + registry.
setup_hub() {
  HUB=$(mktemp -d)
  mkdir -p "$HUB/.ccanvil/templates/github/workflows"
  cat > "$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml" <<'YAML'
name: ccanvil-checks
on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, ready_for_review]
jobs:
  lifecycle-docs:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request' && github.event.pull_request.draft == false
    steps:
      - uses: actions/checkout@v4
      - name: Check
        run: echo ok
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Security audit
        run: bash .ccanvil/scripts/security-audit.sh
YAML
  # Initialize hub git so get_hub_source_raw works
  git -C "$HUB" init -q
  git_id "$HUB"
  echo "{}" > "$HUB/.ccanvil/registry.json"
}

# Register a new fake node in HUB's registry.json keyed by UUID.
register_node() {
  local node_path="$1"
  local node_name="$2"
  local uuid="${3:-00000000-0000-4000-8000-000000000001}"
  local tmp
  tmp=$(mktemp)
  jq --arg u "$uuid" --arg n "$node_name" --arg p "$node_path" \
    '.nodes[$u] = {name: $n, path: $p, registered_at: "1000000000", last_synced: "1000000000"}' \
    "$HUB/.ccanvil/registry.json" > "$tmp" && mv "$tmp" "$HUB/.ccanvil/registry.json"
}

# Build a fake node with .ccanvil/ccanvil.lock + .github/workflows/ci.yml.
# Optional flag: pass "customized" to give the test job extra steps.
setup_node() {
  local name="${1:-fake}"
  local mode="${2:-default}"
  NODE=$(mktemp -d)
  git -C "$NODE" init -q
  git_id "$NODE"
  mkdir -p "$NODE/.ccanvil" "$NODE/.github/workflows"

  # Lockfile (minimal — 1 unrelated tracked entry so jq has something to mutate)
  jq -n --arg hub "$HUB" '{
    hub_source: $hub,
    files: {".ccanvil/scripts/ccanvil-sync.sh": {origin:"hub", hub_hash:"x", local_hash:"x", status:"clean", sync:"tracked"}}
  }' > "$NODE/.ccanvil/ccanvil.lock"

  if [[ "$mode" != "no-ci" ]]; then
    cat > "$NODE/.github/workflows/ci.yml" <<'YAML'
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YAML
    if [[ "$mode" == "customized" ]]; then
      cat >> "$NODE/.github/workflows/ci.yml" <<'YAML'
      - name: Install bats
        run: sudo apt-get install -y bats
      - name: Run tests
        run: bats tests/
YAML
    else
      cat >> "$NODE/.github/workflows/ci.yml" <<'YAML'
      - name: Run tests
        run: echo TODO
YAML
    fi
    # Append the two jobs we expect heal to strip
    cat >> "$NODE/.github/workflows/ci.yml" <<'YAML'
  lifecycle-docs:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - name: Check for stale docs
        run: echo stale-check
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Security
        run: bash .ccanvil/scripts/security-audit.sh
YAML
  fi
  git -C "$NODE" add -A
  git -C "$NODE" -c commit.gpgsign=false commit -q -m "init"

  # Register node in hub registry under provided UUID
  register_node "$NODE" "$name" "${3:-00000000-0000-4000-8000-000000000001}"
}

teardown() {
  if [[ -n "${HUB:-}" ]]; then rm -rf "$HUB"; fi
  if [[ -n "${NODE:-}" ]]; then rm -rf "$NODE"; fi
  if [[ -n "${NODE2:-}" ]]; then rm -rf "$NODE2"; fi
}

# ---------------------------------------------------------------------------
# AC-4: happy path — file written, lockfile registered, ci.yml stripped, commit landed
# ---------------------------------------------------------------------------

@test "AC-4: heal writes ccanvil-checks.yml onto node" {
  setup_hub
  setup_node node1
  cd "$HUB"
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  [ -f "$NODE/.github/workflows/ccanvil-checks.yml" ]
  grep -qF 'ccanvil-checks' "$NODE/.github/workflows/ccanvil-checks.yml"
}

@test "AC-4: heal registers ccanvil-checks.yml in node lockfile with origin=hub" {
  setup_hub
  setup_node node1
  cd "$HUB"
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  origin=$(jq -r '.files[".github/workflows/ccanvil-checks.yml"].origin' "$NODE/.ccanvil/ccanvil.lock")
  [ "$origin" = "hub" ]
}

@test "AC-4: heal strips lifecycle-docs + security from ci.yml" {
  setup_hub
  setup_node node1
  cd "$HUB"
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  ! grep -qE '^[[:space:]]*lifecycle-docs:' "$NODE/.github/workflows/ci.yml"
  ! grep -qE '^[[:space:]]*security:' "$NODE/.github/workflows/ci.yml"
}

@test "AC-4: heal commits with chore(ccanvil-checks) subject" {
  setup_hub
  setup_node node1
  cd "$HUB"
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  msg=$(git -C "$NODE" log -1 --format=%s)
  [[ "$msg" == "chore(ccanvil-checks): split hub-managed CI gates (BTS-488)" ]]
}

# ---------------------------------------------------------------------------
# AC-5: idempotency — re-running on an already-healed node = no-op
# ---------------------------------------------------------------------------

@test "AC-5: re-run on healed node makes no new commit" {
  setup_hub
  setup_node node1
  cd "$HUB"
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  first_head=$(git -C "$NODE" rev-parse HEAD)
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  second_head=$(git -C "$NODE" rev-parse HEAD)
  [ "$first_head" = "$second_head" ]
}

# ---------------------------------------------------------------------------
# AC-6: preservation — customized test job survives heal
# ---------------------------------------------------------------------------

@test "AC-6: customized test job (Install bats + bats tests/) survives heal" {
  setup_hub
  setup_node node1 customized
  cd "$HUB"
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  grep -qF 'Install bats' "$NODE/.github/workflows/ci.yml"
  grep -qF 'bats tests/' "$NODE/.github/workflows/ci.yml"
  # test: job header preserved
  grep -qE '^[[:space:]]*test:' "$NODE/.github/workflows/ci.yml"
}

# ---------------------------------------------------------------------------
# AC-7: graceful no-ci.yml
# ---------------------------------------------------------------------------

@test "AC-7: node with no ci.yml still gets ccanvil-checks.yml" {
  setup_hub
  setup_node node1 no-ci
  cd "$HUB"
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  [ -f "$NODE/.github/workflows/ccanvil-checks.yml" ]
  [ ! -f "$NODE/.github/workflows/ci.yml" ]
}

# ---------------------------------------------------------------------------
# AC-8: per-node failure isolation — dirty-tree node doesn't abort fleet
# ---------------------------------------------------------------------------

@test "AC-8: commit-failing node logs ERROR; fleet loop continues to next node" {
  setup_hub
  setup_node node1 default 00000000-0000-4000-8000-000000000001

  # Set up a second node with a pre-commit hook that rejects everything.
  # This forces git commit to exit non-zero after heal has written
  # ccanvil-checks.yml, updated the lockfile, and stripped ci.yml. The
  # heal verb must isolate node2's failure from node1's success.
  NODE2=$(mktemp -d)
  git -C "$NODE2" init -q
  git_id "$NODE2"
  mkdir -p "$NODE2/.ccanvil" "$NODE2/.github/workflows" "$NODE2/.git/hooks"
  jq -n --arg hub "$HUB" '{hub_source:$hub, files:{}}' > "$NODE2/.ccanvil/ccanvil.lock"
  git -C "$NODE2" add -A
  git -C "$NODE2" -c commit.gpgsign=false commit -q --allow-empty -m "init"
  cat > "$NODE2/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
echo "pre-commit-rejected" >&2
exit 1
HOOK
  chmod +x "$NODE2/.git/hooks/pre-commit"
  register_node "$NODE2" "node2" "00000000-0000-4000-8000-000000000002"

  cd "$HUB"
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]

  # Assert node1 healed cleanly (loop continued past node2's failure)
  [ -f "$NODE/.github/workflows/ccanvil-checks.yml" ]
  msg=$(git -C "$NODE" log -1 --format=%s)
  [[ "$msg" == "chore(ccanvil-checks): split hub-managed CI gates (BTS-488)" ]]

  # Assert node2 surfaced as ERROR in the output
  [[ "$output" == *"ERROR"* ]]
  # And node2's HEAD has not advanced past the init commit
  node2_commits=$(git -C "$NODE2" rev-list --count HEAD)
  [ "$node2_commits" -eq 1 ]

  # Assert fleet summary reports both healed=1 AND errors=1
  [[ "$output" == *"Healed: 1"* ]]
  [[ "$output" == *"Errors: 1"* ]]
}

@test "AC-8/B-2: orphaned heal-target writes from prior commit failure retry on next run" {
  setup_hub
  setup_node node1 default 00000000-0000-4000-8000-000000000001
  cd "$HUB"

  # First run with a pre-commit hook that rejects: Steps A/B/C write to the
  # working tree but Step D fails. Files are now in node1's working tree
  # uncommitted.
  mkdir -p "$NODE/.git/hooks"
  cat > "$NODE/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
  chmod +x "$NODE/.git/hooks/pre-commit"
  pre_head=$(git -C "$NODE" rev-parse HEAD)
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  [[ "$output" == *"ERROR"* ]]

  # Files are on disk but not in HEAD
  [ -f "$NODE/.github/workflows/ccanvil-checks.yml" ]
  mid_head=$(git -C "$NODE" rev-parse HEAD)
  [ "$pre_head" = "$mid_head" ]

  # Remove the hook so the next run can commit
  rm "$NODE/.git/hooks/pre-commit"

  # Second run must detect the uncommitted heal-target writes and retry the
  # commit — not report UNCHANGED as if the node were already healed.
  run bash "$SCRIPT" heal-ci-workflows
  [ "$status" -eq 0 ]
  post_head=$(git -C "$NODE" rev-parse HEAD)
  [ "$pre_head" != "$post_head" ]
  msg=$(git -C "$NODE" log -1 --format=%s)
  [[ "$msg" == "chore(ccanvil-checks): split hub-managed CI gates (BTS-488)" ]]
}

# ---------------------------------------------------------------------------
# Dry-run contract: no mutations
# ---------------------------------------------------------------------------

@test "dry-run: no file written, no commit landed" {
  setup_hub
  setup_node node1
  cd "$HUB"
  pre_head=$(git -C "$NODE" rev-parse HEAD)
  run bash "$SCRIPT" heal-ci-workflows --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$NODE/.github/workflows/ccanvil-checks.yml" ]
  post_head=$(git -C "$NODE" rev-parse HEAD)
  [ "$pre_head" = "$post_head" ]
  [[ "$output" == *"WOULD"* ]]
}
