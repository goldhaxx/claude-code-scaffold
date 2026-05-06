#!/usr/bin/env bats
# BTS-319 Phase 1: provider-resolve-ids substrate primitive.
# Resolves Linear team_id, project_id, state_ids[8], label_ids[idea] from
# live API + deep-merges into .claude/ccanvil.local.json. Phase 1 of the
# provider-heal umbrella surfaced by the unifi-toolbox dogfood 2026-05-06.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
  PROJECT_DIR="$TMPDIR_BATS/proj"
  mkdir -p "$PROJECT_DIR/.claude"
  # Pre-existing partial config: routing already set, missing IDs.
  cat > "$PROJECT_DIR/.claude/ccanvil.local.json" <<'EOF'
{
  "node_uuid": "deadbeef-aaaa-bbbb-cccc-111122223333",
  "integrations": {
    "routing": {"idea": "linear"},
    "providers": {
      "linear": {
        "team": "Foo",
        "project": "Bar"
      }
    }
  }
}
EOF
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

# Stub linear-query.sh that branches on subcommand.
# Behavior parameterized by env vars per call. Uses if/else (not
# ${VAR:-default}) to avoid bash parameter-expansion truncation on `}`.
write_lq_stub() {
  local stub="$TMPDIR_BATS/lq-stub.sh"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
case "$1" in
  list-teams)
    if [[ -n "$STUB_TEAMS_JSON" ]]; then echo "$STUB_TEAMS_JSON"
    else echo '[{"id":"STUB-TEAM-1","name":"Foo"}]'
    fi
    exit 0
    ;;
  list-projects)
    if [[ -n "$STUB_PROJECTS_JSON" ]]; then echo "$STUB_PROJECTS_JSON"
    else echo '[{"id":"STUB-PROJ-1","name":"Bar"}]'
    fi
    exit 0
    ;;
  list-states)
    if [[ -n "$STUB_STATES_JSON" ]]; then echo "$STUB_STATES_JSON"
    else echo '[{"id":"S-TRI","name":"Triage","type":"triage"},{"id":"S-BAK","name":"Backlog","type":"backlog"},{"id":"S-ICE","name":"Icebox","type":"backlog"},{"id":"S-TODO","name":"Todo","type":"unstarted"},{"id":"S-IP","name":"In Progress","type":"started"},{"id":"S-DONE","name":"Done","type":"completed"},{"id":"S-DUP","name":"Duplicate","type":"canceled"},{"id":"S-CAN","name":"Canceled","type":"canceled"}]'
    fi
    exit 0
    ;;
  list-labels)
    shift
    if [[ "$1" == "--workspace-scoped" ]]; then
      if [[ -n "$STUB_LABELS_WS_JSON" ]]; then echo "$STUB_LABELS_WS_JSON"
      else echo '[{"id":"L-IDEA","name":"idea"}]'
      fi
    else
      if [[ -n "$STUB_LABELS_TEAM_JSON" ]]; then echo "$STUB_LABELS_TEAM_JSON"
      else echo '[]'
      fi
    fi
    exit 0
    ;;
  *)
    echo "stub: unsupported subcommand $1" >&2
    exit 2
    ;;
esac
STUBEOF
  chmod +x "$stub"
  echo "$stub"
}

# =========================================================================
# AC-1: happy path — full ID block written
# =========================================================================

@test "AC-1: provider-resolve-ids writes full IDs into config" {
  set -e
  stub=$(write_lq_stub)
  CFG="$PROJECT_DIR/.claude/ccanvil.local.json"

  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" provider-resolve-ids \
    --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.integrations.providers.linear.team_id == "STUB-TEAM-1"' "$CFG"
  jq -e '.integrations.providers.linear.project_id == "STUB-PROJ-1"' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.triage == "S-TRI"' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.backlog == "S-BAK"' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.icebox == "S-ICE"' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.todo == "S-TODO"' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.in_progress == "S-IP"' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.done == "S-DONE"' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.duplicate == "S-DUP"' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.canceled == "S-CAN"' "$CFG"
  jq -e '.integrations.providers.linear.label_ids.idea == "L-IDEA"' "$CFG"
}

# =========================================================================
# AC-2: state-name → role mapping ignores extra states (custom "Idea" state)
# =========================================================================

@test "AC-2: extra Linear states (e.g., custom 'Idea') silently ignored" {
  set -e
  STUB_STATES_JSON='[
    {"id":"S-TRI","name":"Triage","type":"triage"},
    {"id":"S-IDEA-CUSTOM","name":"Idea","type":"backlog"},
    {"id":"S-BAK","name":"Backlog","type":"backlog"},
    {"id":"S-ICE","name":"Icebox","type":"backlog"},
    {"id":"S-TODO","name":"Todo","type":"unstarted"},
    {"id":"S-IP","name":"In Progress","type":"started"},
    {"id":"S-DONE","name":"Done","type":"completed"},
    {"id":"S-DUP","name":"Duplicate","type":"canceled"},
    {"id":"S-CAN","name":"Canceled","type":"canceled"}
  ]'
  stub=$(STUB_STATES_JSON="$STUB_STATES_JSON" write_lq_stub)
  CFG="$PROJECT_DIR/.claude/ccanvil.local.json"

  STUB_STATES_JSON="$STUB_STATES_JSON" \
  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" provider-resolve-ids \
    --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  # state_ids must have exactly 8 keys (custom "Idea" excluded)
  jq -e '.integrations.providers.linear.state_ids | length == 8' "$CFG"
  jq -e '.integrations.providers.linear.state_ids.backlog == "S-BAK"' "$CFG"
  # No "idea" key under state_ids (the canonical key for label is under label_ids)
  jq -e '.integrations.providers.linear.state_ids | has("idea") | not' "$CFG"
}

# =========================================================================
# AC-3: workspace-scoped label fallback (team-scoped returns [])
# =========================================================================

@test "AC-3: label resolution falls back to workspace scope when team scope empty" {
  set -e
  # Team-scoped returns []; workspace-scoped has the idea label.
  stub=$(STUB_LABELS_TEAM_JSON="[]" write_lq_stub)
  CFG="$PROJECT_DIR/.claude/ccanvil.local.json"

  STUB_LABELS_TEAM_JSON="[]" \
  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" provider-resolve-ids \
    --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.integrations.providers.linear.label_ids.idea == "L-IDEA"' "$CFG"
}

# =========================================================================
# AC-4: deep-merge preserves existing keys
# =========================================================================

@test "AC-4: deep-merge preserves node_uuid, routing, and existing string keys" {
  set -e
  stub=$(write_lq_stub)
  CFG="$PROJECT_DIR/.claude/ccanvil.local.json"

  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" provider-resolve-ids \
    --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.node_uuid == "deadbeef-aaaa-bbbb-cccc-111122223333"' "$CFG"
  jq -e '.integrations.routing.idea == "linear"' "$CFG"
  jq -e '.integrations.providers.linear.team == "Foo"' "$CFG"
  jq -e '.integrations.providers.linear.project == "Bar"' "$CFG"
}

# =========================================================================
# AC-5: idempotent on re-run
# =========================================================================

@test "AC-5: byte-identical output on re-run with same args" {
  set -e
  stub=$(write_lq_stub)
  CFG="$PROJECT_DIR/.claude/ccanvil.local.json"

  LINEAR_QUERY_OVERRIDE="$stub" bash "$SCRIPT" provider-resolve-ids \
    --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR" >/dev/null
  hash1=$(md5sum "$CFG" | cut -d' ' -f1)

  LINEAR_QUERY_OVERRIDE="$stub" bash "$SCRIPT" provider-resolve-ids \
    --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR" >/dev/null
  hash2=$(md5sum "$CFG" | cut -d' ' -f1)

  [ "$hash1" = "$hash2" ]
}

# =========================================================================
# AC-6: error-mode for missing team
# =========================================================================

@test "AC-6: missing team exits non-zero with clear stderr message" {
  STUB_TEAMS_JSON='[]' \
  LINEAR_QUERY_OVERRIDE="$(STUB_TEAMS_JSON='[]' write_lq_stub)" \
    run bash "$SCRIPT" provider-resolve-ids \
      --provider linear --team NotAReal --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE 'team.*NotAReal|NotAReal.*team'
}

# =========================================================================
# AC-7: missing label warns but exits 0
# =========================================================================

@test "AC-7: missing label both scopes → WARN + exit 0 + partial config" {
  STUB_LABELS_TEAM_JSON='[]' STUB_LABELS_WS_JSON='[]' \
  LINEAR_QUERY_OVERRIDE="$(STUB_LABELS_TEAM_JSON='[]' STUB_LABELS_WS_JSON='[]' write_lq_stub)" \
    run bash "$SCRIPT" provider-resolve-ids \
      --provider linear --team Foo --project Bar --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE 'WARN.*idea label not resolved'
  CFG="$PROJECT_DIR/.claude/ccanvil.local.json"
  # team_id and state_ids written even though label_ids.idea missing
  jq -e '.integrations.providers.linear.team_id == "STUB-TEAM-1"' "$CFG"
  jq -e '.integrations.providers.linear.label_ids.idea // "missing" == "missing"' "$CFG"
}
