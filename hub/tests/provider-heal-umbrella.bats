#!/usr/bin/env bats
# BTS-326: provider-heal umbrella verb. Composes Phase 3 (auth) →
# Phase 2 (drift) → Phase 1 (resolve-ids) with fail-fast halt-and-remediate.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
  PROJECT_DIR="$TMPDIR_BATS/proj"
  FAKE_HOME="$TMPDIR_BATS/fake-home"
  mkdir -p "$PROJECT_DIR/.claude" "$FAKE_HOME"
  unset LINEAR_API_KEY
  export HOME="$FAKE_HOME"
  cat > "$PROJECT_DIR/.claude/ccanvil.local.json" <<'EOF'
{
  "node_uuid": "deadbeef-aaaa-bbbb-cccc-111122223333",
  "integrations": {
    "routing": {"idea": "linear"},
    "providers": {"linear": {"team": "Foo", "project": "Bar"}}
  }
}
EOF
  CALLS_LOG="$TMPDIR_BATS/calls.log"
  : > "$CALLS_LOG"
  export CALLS_LOG
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

write_lq_stub() {
  local stub="$TMPDIR_BATS/lq-stub.sh"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
echo "lq: $*" >> "$CALLS_LOG"
case "$1" in
  viewer)
    echo '{"id":"VIEWER-1","name":"Stub User"}'; exit 0 ;;
  list-teams)
    if [[ -n "$STUB_TEAMS_JSON" ]]; then echo "$STUB_TEAMS_JSON"
    else echo '[{"id":"STUB-TEAM-1","name":"Foo"}]'
    fi
    exit 0 ;;
  list-projects)
    echo '[{"id":"STUB-PROJ-1","name":"Bar"}]'; exit 0 ;;
  list-states)
    echo '[{"id":"S-TRI","name":"Triage","type":"triage"},{"id":"S-BAK","name":"Backlog","type":"backlog"},{"id":"S-ICE","name":"Icebox","type":"backlog"},{"id":"S-TODO","name":"Todo","type":"unstarted"},{"id":"S-IP","name":"In Progress","type":"started"},{"id":"S-DONE","name":"Done","type":"completed"},{"id":"S-DUP","name":"Duplicate","type":"canceled"},{"id":"S-CAN","name":"Canceled","type":"canceled"}]'
    exit 0 ;;
  list-labels)
    shift
    if [[ "$1" == "--workspace-scoped" ]]; then echo '[{"id":"L-IDEA","name":"idea"}]'
    else echo '[]'
    fi
    exit 0 ;;
  *) echo "lq stub: unsupported $1" >&2; exit 2 ;;
esac
STUBEOF
  chmod +x "$stub"
  echo "$stub"
}

write_sync_stub() {
  local stub="$TMPDIR_BATS/sync-stub.sh"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
echo "sync: $*" >> "$CALLS_LOG"
case "$1" in
  pull-plan)
    if [[ -n "$STUB_PLAN_JSON" ]]; then echo "$STUB_PLAN_JSON"
    else echo '[]'
    fi
    exit 0 ;;
  pull-auto|pull-apply)
    echo "sync stub: PROHIBITED CALL: $*" >&2
    exit 99 ;;
  *) echo "sync stub: unsupported $1" >&2; exit 2 ;;
esac
STUBEOF
  chmod +x "$stub"
  echo "$stub"
}

# Init the lock for Phase 2 to read hub_source from.
init_lock() {
  mkdir -p "$PROJECT_DIR/.ccanvil"
  cat > "$PROJECT_DIR/.ccanvil/ccanvil.lock" <<EOF
{"hub_source": "$TMPDIR_BATS/hub-stub", "hub_version":"stub", "node_uuid":"deadbeef", "files":{}}
EOF
  mkdir -p "$TMPDIR_BATS/hub-stub"
}

# =========================================================================
# AC-1: happy path — all 3 phases succeed
# =========================================================================

@test "AC-1: happy path → PROVIDER-HEAL-OK exit 0" {
  set -e
  init_lock
  lq=$(write_lq_stub)
  sync=$(write_sync_stub)
  LINEAR_API_KEY="lin_api_x" \
  LINEAR_QUERY_OVERRIDE="$lq" CCANVIL_SYNC_OVERRIDE="$sync" \
    run bash "$SCRIPT" provider-heal --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'PROVIDER-HEAL-OK'
  echo "$output" | grep -qF 'auth=VIEWER-1'
  echo "$output" | grep -qF 'drift=clean'
  echo "$output" | grep -qF 'ids=resolved'
}

# =========================================================================
# AC-2: auth halt → no Phase 2 / Phase 1 execution
# =========================================================================

@test "AC-2: auth halt (no LINEAR_API_KEY) → halts before Phase 2" {
  init_lock
  lq=$(write_lq_stub)
  sync=$(write_sync_stub)
  LINEAR_QUERY_OVERRIDE="$lq" CCANVIL_SYNC_OVERRIDE="$sync" \
    run bash "$SCRIPT" provider-heal --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'LINEAR_API_KEY not found'
  # Phase 2 (pull-plan) MUST NOT have been called
  ! grep -qE '^sync: pull-plan' "$CALLS_LOG"
  # Phase 1 (list-teams) MUST NOT have been called
  ! grep -qE '^lq: list-teams' "$CALLS_LOG"
}

# =========================================================================
# AC-3: drift halt → no Phase 1 execution
# =========================================================================

@test "AC-3: drift halt → halts before Phase 1" {
  init_lock
  lq=$(write_lq_stub)
  STUB_PLAN_JSON='[{"file":"a.md","action":"auto-update"}]'
  sync=$(STUB_PLAN_JSON="$STUB_PLAN_JSON" write_sync_stub)
  LINEAR_API_KEY="lin_api_x" \
  STUB_PLAN_JSON="$STUB_PLAN_JSON" \
  LINEAR_QUERY_OVERRIDE="$lq" CCANVIL_SYNC_OVERRIDE="$sync" \
    run bash "$SCRIPT" provider-heal --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF 'DRIFT DETECTED'
  # Phase 1 (list-teams) MUST NOT have been called
  ! grep -qE '^lq: list-teams' "$CALLS_LOG"
}

# =========================================================================
# AC-4: resolve-ids halt → exits with that error
# =========================================================================

@test "AC-4: resolve-ids halt (missing team) → halts at Phase 1" {
  init_lock
  STUB_TEAMS_JSON='[]'
  lq=$(STUB_TEAMS_JSON='[]' write_lq_stub)
  sync=$(write_sync_stub)
  LINEAR_API_KEY="lin_api_x" \
  STUB_TEAMS_JSON='[]' \
  LINEAR_QUERY_OVERRIDE="$lq" CCANVIL_SYNC_OVERRIDE="$sync" \
    run bash "$SCRIPT" provider-heal --provider linear --team NotAReal --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "team 'NotAReal' not found"
}

# =========================================================================
# AC-5 OK: --json envelope on happy path
# =========================================================================

@test "AC-5 OK: --json status=ok with all 3 phase objects populated" {
  set -e
  init_lock
  lq=$(write_lq_stub)
  sync=$(write_sync_stub)
  LINEAR_API_KEY="lin_api_x" \
  LINEAR_QUERY_OVERRIDE="$lq" CCANVIL_SYNC_OVERRIDE="$sync" \
    run bash "$SCRIPT" provider-heal --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok"'
  echo "$output" | jq -e '.phases.auth.status == "ok"'
  echo "$output" | jq -e '.phases.drift.status == "ok"'
  echo "$output" | jq -e '.phases.resolve_ids != null'
}

# =========================================================================
# AC-5 AUTH-FAILED: --json shape when auth halts
# =========================================================================

@test "AC-5 AUTH-FAILED: --json status=auth-failed, drift+resolve_ids null" {
  init_lock
  lq=$(write_lq_stub)
  sync=$(write_sync_stub)
  LINEAR_QUERY_OVERRIDE="$lq" CCANVIL_SYNC_OVERRIDE="$sync" \
    run bash "$SCRIPT" provider-heal --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR" --json
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.status == "auth-failed"'
  echo "$output" | jq -e '.phases.auth.status == "missing-key"'
  echo "$output" | jq -e '.phases.drift == null'
  echo "$output" | jq -e '.phases.resolve_ids == null'
}

# =========================================================================
# AC-6: pull-auto and pull-apply NEVER invoked from umbrella
# =========================================================================

@test "AC-6: drift detected → no pull-auto/pull-apply invocations" {
  init_lock
  lq=$(write_lq_stub)
  STUB_PLAN_JSON='[{"file":"a.md","action":"auto-update"}]'
  sync=$(STUB_PLAN_JSON="$STUB_PLAN_JSON" write_sync_stub)
  LINEAR_API_KEY="lin_api_x" \
  STUB_PLAN_JSON="$STUB_PLAN_JSON" \
  LINEAR_QUERY_OVERRIDE="$lq" CCANVIL_SYNC_OVERRIDE="$sync" \
    run bash "$SCRIPT" provider-heal --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
  ! grep -qE '^sync: (pull-auto|pull-apply)' "$CALLS_LOG"
}
