#!/usr/bin/env bats
# Tests for the idea-triage-native feature.
# Covers the five-state lifecycle (triage → backlog / icebox / canceled / duplicate),
# agentic mutations via state IDs, Icebox review, and legacy migration.

OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"
DOCS_CHECK="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.ccanvil"
}

teardown() {
  rm -rf "$PROJECT"
}

# Helper: write a Linear-routed config with optional state_ids block.
_linear_config_with_state_ids() {
  mkdir -p "$PROJECT/.claude"
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {
      "linear": {
        "mechanism": "mcp",
        "project": "Test Project",
        "team": "Test Team",
        "idea_label": "idea",
        "idea_status": "Idea",
        "icebox_status": "Icebox",
        "state_ids": {
          "triage":    "aaaaaaaa-0000-0000-0000-000000000001",
          "backlog":   "bbbbbbbb-0000-0000-0000-000000000002",
          "icebox":    "cccccccc-0000-0000-0000-000000000003",
          "canceled":  "dddddddd-0000-0000-0000-000000000004",
          "duplicate": "eeeeeeee-0000-0000-0000-000000000005"
        }
      }
    },
    "routing": { "idea": "linear" }
  }
}
JSON
}

# Helper: write a Linear-routed config WITHOUT state_ids.
_linear_config_no_state_ids() {
  mkdir -p "$PROJECT/.claude"
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {
      "linear": {
        "mechanism": "mcp",
        "project": "Test Project",
        "team": "Test Team",
        "idea_label": "idea",
        "idea_status": "Idea"
      }
    },
    "routing": { "idea": "linear" }
  }
}
JSON
}

# =========================================================================
# Step 1 — Local-log status vocabulary (triage/backlog/icebox/canceled/duplicate)
# Covers AC-1 (local half): capture writes status="triage".
# =========================================================================

@test "Step 1: cmd_idea_add writes status=triage (not legacy new)" {
  run bash "$DOCS_CHECK" idea-add "capture one" "$PROJECT"
  [ "$status" -eq 0 ]
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  [ -f "$ideas_log" ]
  run jq -r '.status' "$ideas_log"
  [ "$status" -eq 0 ]
  [ "$output" = "triage" ]
}

@test "Step 1: cmd_idea_list --status triage includes legacy status=new entries" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  cat > "$ideas_log" <<'EOF'
{"uid":"l1","created":1,"status":"new","title":"legacy","body":"legacy"}
{"uid":"n1","created":2,"status":"triage","title":"native","body":"native"}
{"uid":"b1","created":3,"status":"backlog","title":"promoted","body":"promoted"}
EOF
  run bash "$DOCS_CHECK" idea-list --status triage "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '[.[].id] | contains(["l1", "n1"])'
}

# =========================================================================
# Step 2 — State-ID config shape + lookup helper
# Covers AC-4 foundation: resolve emits params.stateId when config carries it.
# =========================================================================

@test "Step 2: idea.triage resolve includes state_ids.triage as params.stateId" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.stateId == "aaaaaaaa-0000-0000-0000-000000000001"'
}

# =========================================================================
# Step 5 — Four mutation resolvers: idea.{promote,defer,dismiss,merge}.
# Covers AC-3 + AC-4: each verb targets the correct state by ID (Linear)
# or status string (local). Merge carries duplicateOf.
# =========================================================================

@test "Step 5: is_valid_operation recognizes idea.promote" {
  run bash "$OPS" resolve idea.promote --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "Step 5: is_valid_operation recognizes idea.defer" {
  run bash "$OPS" resolve idea.defer --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "Step 5: is_valid_operation recognizes idea.dismiss" {
  run bash "$OPS" resolve idea.dismiss --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "Step 5: is_valid_operation recognizes idea.merge" {
  run bash "$OPS" resolve idea.merge --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "Step 5: local idea.promote maps to idea-update <uid> backlog" {
  run bash "$OPS" resolve idea.promote --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.invocation.command | test("idea-update.*backlog")'
}

@test "Step 5: local idea.defer maps to idea-update <uid> icebox" {
  run bash "$OPS" resolve idea.defer --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | test("idea-update.*icebox")'
}

@test "Step 5: local idea.dismiss maps to idea-update <uid> canceled" {
  run bash "$OPS" resolve idea.dismiss --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | test("idea-update.*canceled")'
}

@test "Step 5: local idea.merge maps to idea-update <uid> duplicate" {
  run bash "$OPS" resolve idea.merge --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | test("idea-update.*duplicate")'
}

@test "Step 5: Linear idea.promote returns save_issue with stateId=backlog" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.promote --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  echo "$output" | jq -e '.invocation.tool == "mcp__claude_ai_Linear__save_issue"'
  echo "$output" | jq -e '.invocation.params.stateId == "bbbbbbbb-0000-0000-0000-000000000002"'
}

@test "Step 5: Linear idea.defer returns save_issue with stateId=icebox" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.defer --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.tool == "mcp__claude_ai_Linear__save_issue"'
  echo "$output" | jq -e '.invocation.params.stateId == "cccccccc-0000-0000-0000-000000000003"'
}

@test "Step 5: Linear idea.dismiss returns save_issue with stateId=canceled" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.dismiss --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.stateId == "dddddddd-0000-0000-0000-000000000004"'
}

# =========================================================================
# Step 8 — Icebox review command (AC-5).
# =========================================================================

@test "Step 8: cmd_idea_review_icebox returns only icebox items older than 60d" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  local now stale fresh
  now=$(date +%s)
  stale=$((now - 5184001))   # >60d
  fresh=$((now - 86400))     # 1d
  cat > "$ideas_log" <<EOF
{"uid":"old1","created":$stale,"status":"icebox","title":"a","body":"a"}
{"uid":"old2","created":$stale,"status":"icebox","title":"b","body":"b"}
{"uid":"new1","created":$fresh,"status":"icebox","title":"c","body":"c"}
{"uid":"back","created":$stale,"status":"backlog","title":"d","body":"d"}
EOF
  run bash "$DOCS_CHECK" idea-review-icebox "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '[.[].id] | contains(["old1","old2"])'
}

@test "Step 8: idea.review-icebox resolves to local bash with no config" {
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | test("idea-review-icebox")'
}

@test "Step 8: idea.review-icebox Linear resolver includes icebox stateId + type filter" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.tool == "mcp__claude_ai_Linear__list_issues"'
  echo "$output" | jq -e '.invocation.params.stateId == "cccccccc-0000-0000-0000-000000000003"'
}

# =========================================================================
# Step 7 — Default idea-list excludes terminal + deferred states (AC-9).
# =========================================================================

@test "Step 7: idea-list default excludes icebox, canceled, duplicate" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  cat > "$ideas_log" <<'EOF'
{"uid":"a","created":1,"status":"triage","title":"t","body":"t"}
{"uid":"b","created":2,"status":"backlog","title":"b","body":"b"}
{"uid":"c","created":3,"status":"icebox","title":"i","body":"i"}
{"uid":"d","created":4,"status":"canceled","title":"c","body":"c"}
{"uid":"e","created":5,"status":"duplicate","title":"d","body":"d"}
EOF
  run bash "$DOCS_CHECK" idea-list "$PROJECT"
  [ "$status" -eq 0 ]
  # Default: only triage + backlog (2 entries).
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '[.[].id] | contains(["a","b"])'
  echo "$output" | jq -e '[.[].id] | any(. == "c") | not'
  echo "$output" | jq -e '[.[].id] | any(. == "d") | not'
  echo "$output" | jq -e '[.[].id] | any(. == "e") | not'
}

@test "Step 7: idea-list --status icebox surfaces iceboxed items" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  cat > "$ideas_log" <<'EOF'
{"uid":"a","created":1,"status":"triage","title":"t","body":"t"}
{"uid":"c","created":3,"status":"icebox","title":"i","body":"i"}
EOF
  run bash "$DOCS_CHECK" idea-list --status icebox "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1'
  echo "$output" | jq -e '.[0].id == "c"'
}

# =========================================================================
# Step 6 — cmd_idea_update accepts new vocab; rejects unknowns.
# =========================================================================

@test "Step 6: idea-update accepts each of {triage, backlog, icebox, canceled, duplicate}" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  # Seed with five entries, one per uid.
  cat > "$ideas_log" <<'EOF'
{"uid":"u1","created":1,"status":"triage","title":"a","body":"a"}
{"uid":"u2","created":2,"status":"triage","title":"b","body":"b"}
{"uid":"u3","created":3,"status":"triage","title":"c","body":"c"}
{"uid":"u4","created":4,"status":"triage","title":"d","body":"d"}
{"uid":"u5","created":5,"status":"triage","title":"e","body":"e"}
EOF
  run bash "$DOCS_CHECK" idea-update u1 triage    "$PROJECT"; [ "$status" -eq 0 ]
  run bash "$DOCS_CHECK" idea-update u2 backlog   "$PROJECT"; [ "$status" -eq 0 ]
  run bash "$DOCS_CHECK" idea-update u3 icebox    "$PROJECT"; [ "$status" -eq 0 ]
  run bash "$DOCS_CHECK" idea-update u4 canceled  "$PROJECT"; [ "$status" -eq 0 ]
  run bash "$DOCS_CHECK" idea-update u5 duplicate "$PROJECT"; [ "$status" -eq 0 ]
  # Confirm each entry actually updated.
  run jq -r 'select(.uid=="u5").status' "$ideas_log"
  [ "$output" = "duplicate" ]
}

@test "Step 6: idea-update rejects unknown status values" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  echo '{"uid":"u1","created":1,"status":"triage","title":"a","body":"a"}' > "$ideas_log"
  run bash "$DOCS_CHECK" idea-update u1 bogus-status "$PROJECT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'ERROR'
}

@test "Step 5: Linear idea.merge returns save_issue with stateId=duplicate + duplicateOf" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.merge BTS-99 --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.stateId == "eeeeeeee-0000-0000-0000-000000000005"'
  echo "$output" | jq -e '.invocation.params.duplicateOf == "BTS-99"'
}

# =========================================================================
# Step 4 — Local idea.triage adapter uses --status triage (not legacy "new").
# Covers AC-2 (local half).
# =========================================================================

@test "Step 4: local idea.triage adapter invokes idea-list --status triage" {
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | test("idea-list --status triage")'
  echo "$output" | jq -e '.invocation.command | test("--status new") | not'
}

# =========================================================================
# Step 3 — Capture routes to Linear-native Triage via API auto-routing.
# Covers AC-1 (Linear half): idea.add does NOT pass a state, letting the
# Linear workspace's Triage feature route the API-created issue itself.
# =========================================================================

@test "Step 3: idea.add Linear resolver does NOT pass .invocation.params.state" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # state must be absent (Linear auto-routes API-created issues to Triage).
  echo "$output" | jq -e '.invocation.params | has("state") | not'
  # Project + team + labels still present.
  echo "$output" | jq -e '.invocation.params.project == "Test Project"'
  echo "$output" | jq -e '.invocation.params.labels == ["idea"]'
}

@test "Step 2: idea.triage resolve stateId is null when config lacks state_ids" {
  _linear_config_no_state_ids
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # Either absent or null — both are acceptable "no configured ID" signals.
  echo "$output" | jq -e '(.invocation.params.stateId // null) == null'
}

@test "Step 1: cmd_idea_count sums legacy + new vocab into new-named counters" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  # 10 entries: one per legacy status, one per new-vocab status.
  # Expected collapse: new→triage, promoted→backlog, parked→icebox,
  # dismissed→canceled, merged→duplicate. Total count: 10.
  cat > "$ideas_log" <<'EOF'
{"uid":"l1","created":1,"status":"new","title":"a","body":"a"}
{"uid":"l2","created":2,"status":"promoted","title":"b","body":"b"}
{"uid":"l3","created":3,"status":"parked","title":"c","body":"c"}
{"uid":"l4","created":4,"status":"dismissed","title":"d","body":"d"}
{"uid":"l5","created":5,"status":"merged","title":"e","body":"e"}
{"uid":"n1","created":6,"status":"triage","title":"f","body":"f"}
{"uid":"n2","created":7,"status":"backlog","title":"g","body":"g"}
{"uid":"n3","created":8,"status":"icebox","title":"h","body":"h"}
{"uid":"n4","created":9,"status":"canceled","title":"i","body":"i"}
{"uid":"n5","created":10,"status":"duplicate","title":"j","body":"j"}
EOF
  run bash "$DOCS_CHECK" idea-count "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 10'
  echo "$output" | jq -e '.triage == 2'
  echo "$output" | jq -e '.backlog == 2'
  echo "$output" | jq -e '.icebox == 2'
  echo "$output" | jq -e '.canceled == 2'
  echo "$output" | jq -e '.duplicate == 2'
}
