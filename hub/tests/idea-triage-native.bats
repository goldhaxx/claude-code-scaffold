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
  set -e
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
# Covers AC-4 foundation: resolve emits params.state when config carries it.
# =========================================================================

@test "Step 2: idea.triage resolve includes state_ids.triage as --state in http command (BTS-166)" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--state") and contains("aaaaaaaa-0000-0000-0000-000000000001")'
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
  set -e
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

@test "Step 5: Linear idea.promote returns save_issue with state=backlog" {
  set -e
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.promote --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  echo "$output" | jq -e '.invocation.tool == "mcp__claude_ai_Linear__save_issue"'
  echo "$output" | jq -e '.invocation.params.state == "bbbbbbbb-0000-0000-0000-000000000002"'
}

@test "Step 5: Linear idea.defer returns save_issue with state=icebox" {
  set -e
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.defer --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.tool == "mcp__claude_ai_Linear__save_issue"'
  echo "$output" | jq -e '.invocation.params.state == "cccccccc-0000-0000-0000-000000000003"'
}

@test "Step 5: Linear idea.dismiss returns save_issue with state=canceled" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.dismiss --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "dddddddd-0000-0000-0000-000000000004"'
}

# =========================================================================
# Step 13 — command-reference.md documents new subcommands + five-state model.
# =========================================================================

@test "Step 13: command-reference documents idea-review-icebox and idea-migrate-state" {
  local ref="$BATS_TEST_DIRNAME/../../.ccanvil/guide/command-reference.md"
  [ -f "$ref" ]
  grep -q 'idea-review-icebox' "$ref"
  grep -q 'idea-migrate-state' "$ref"
  grep -q 'state_ids' "$ref"
  grep -qE 'five-state|triage.*backlog.*icebox' "$ref"
}

# =========================================================================
# Step 12 — Skill prose references the new model (grep assertions).
# =========================================================================

@test "Step 12: /idea skill names all four triage outcomes via operations.sh resolvers" {
  local skill="$BATS_TEST_DIRNAME/../../.claude/skills/idea/SKILL.md"
  [ -f "$skill" ]
  # Outcome names — table rows remain promote/defer/dismiss/merge.
  grep -q 'promote'   "$skill"
  grep -q 'defer'     "$skill"
  grep -q 'dismiss'   "$skill"
  grep -q 'merge'     "$skill"
  # Resolver verb — post-BTS-128, the four outcomes dispatch through a
  # single wrapper (`ticket.transition <id> <role>`) rather than four
  # separate idea.* resolvers.
  grep -q 'ticket\.transition' "$skill"
  # BTS-166: Linear path now uses --state on the linear-query.sh command line.
  # Agentic: state-id dispatch, never name-based.
  grep -qE -- '--state|state-id|state_id' "$skill"
  grep -q 'review-icebox' "$skill"
}

@test "Step 12: /radar skill references icebox_stale_count surface" {
  local skill="$BATS_TEST_DIRNAME/../../.claude/skills/radar/SKILL.md"
  [ -f "$skill" ]
  grep -q 'icebox_stale_count' "$skill"
  grep -q 'review-icebox' "$skill"
}

# =========================================================================
# Step 11 — Pending log carries op-agnostic intents (AC-8).
# =========================================================================

@test "Step 11: idea-sync surfaces mixed-op entries (add + promote + defer)" {
  set -e
  local pending="$PROJECT/.ccanvil/ideas-pending.log"
  cat > "$pending" <<'EOF'
{"op":"add","args":{"title":"t1","body":"b1"},"ts":1776000001}
{"op":"promote","args":{"id":"BTS-1","priority":3},"ts":1776000002}
{"op":"defer","args":{"id":"BTS-2"},"ts":1776000003}
EOF
  run bash "$DOCS_CHECK" idea-sync "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pending == 3'
  echo "$output" | jq -e '[.entries[].op] == ["add","promote","defer"]'
}

@test "Step 11: idea-sync --ack removes a specific entry by ts (regardless of op)" {
  set -e
  local pending="$PROJECT/.ccanvil/ideas-pending.log"
  cat > "$pending" <<'EOF'
{"op":"promote","args":{"id":"BTS-1","priority":3},"ts":1776000002}
{"op":"defer","args":{"id":"BTS-2"},"ts":1776000003}
EOF
  run bash "$DOCS_CHECK" idea-sync --ack 1776000002 "$PROJECT"
  [ "$status" -eq 0 ]
  run bash "$DOCS_CHECK" idea-sync "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pending == 1'
  echo "$output" | jq -e '.entries[0].op == "defer"'
}

# =========================================================================
# Step 10 — Legacy migration (AC-7).
# =========================================================================

@test "Step 10: idea-migrate-state rewrites legacy vocab + creates backup" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  cat > "$ideas_log" <<'EOF'
{"uid":"u1","created":1,"status":"new","title":"a","body":"a"}
{"uid":"u2","created":2,"status":"promoted","title":"b","body":"b"}
{"uid":"u3","created":3,"status":"parked","title":"c","body":"c"}
{"uid":"u4","created":4,"status":"dismissed","title":"d","body":"d"}
{"uid":"u5","created":5,"status":"merged","title":"e","body":"e"}
EOF
  run bash "$DOCS_CHECK" idea-migrate-state "$PROJECT"
  [ "$status" -eq 0 ]
  # Log now carries new vocab.
  run jq -r '.status' "$ideas_log"
  [ "$status" -eq 0 ]
  # Every status should now be new-vocab (no legacy names).
  grep -qE 'status":"(triage|backlog|icebox|canceled|duplicate)"' "$ideas_log"
  ! grep -qE 'status":"(new|promoted|parked|dismissed|merged)"' "$ideas_log"
  # A timestamped backup file was created.
  local backup_count
  backup_count=$(find "$PROJECT/.ccanvil" -name 'ideas.log.*.bak' | wc -l | tr -d ' ')
  [ "$backup_count" -ge 1 ]
}

@test "Step 10: idea-migrate-state is idempotent (second run reports zero migrations)" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  cat > "$ideas_log" <<'EOF'
{"uid":"u1","created":1,"status":"new","title":"a","body":"a"}
EOF
  run bash "$DOCS_CHECK" idea-migrate-state "$PROJECT"
  [ "$status" -eq 0 ]
  run bash "$DOCS_CHECK" idea-migrate-state "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '0 entries migrated|no legacy entries'
}

# =========================================================================
# Step 9 — radar-gather surfaces Icebox-stale count (AC-6 local half).
# =========================================================================

@test "Step 9: radar-gather emits ideas.icebox_stale_count" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  local now stale fresh
  now=$(date +%s)
  stale=$((now - 5184001))
  fresh=$((now - 86400))
  cat > "$ideas_log" <<EOF
{"uid":"s1","created":$stale,"status":"icebox","title":"a","body":"a"}
{"uid":"s2","created":$stale,"status":"icebox","title":"b","body":"b"}
{"uid":"s3","created":$fresh,"status":"icebox","title":"c","body":"c"}
{"uid":"s4","created":$stale,"status":"backlog","title":"d","body":"d"}
EOF
  # radar-gather targets a docs/ dir; stub one.
  mkdir -p "$PROJECT/docs"
  run bash "$DOCS_CHECK" radar-gather "$PROJECT/docs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ideas.icebox_stale_count == 2'
}

# =========================================================================
# Step 8 — Icebox review command (AC-5).
# =========================================================================

@test "Step 8: cmd_idea_review_icebox returns only icebox items older than 60d" {
  set -e
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

@test "Step 8: idea.review-icebox Linear resolver includes icebox state in http command (BTS-166)" {
  set -e
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("list-issues")'
  echo "$output" | jq -e '.invocation.command | contains("--state") and contains("cccccccc-0000-0000-0000-000000000003")'
}

@test "BTS-166: idea.review-icebox falls through to type-name 'icebox' when state_ids.icebox is empty string" {
  # Mirror of BTS-121 AC-5 for the icebox path. Empty string must be treated
  # as unconfigured to avoid filtering by --state '' (server-side error or
  # silent no-op). Falls through to the literal "icebox" type-name filter.
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
        "state_ids": {
          "triage": "aaaaaaaa-0000-0000-0000-000000000001",
          "icebox": ""
        }
      }
    },
    "routing": { "idea": "linear" }
  }
}
JSON
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # Empty-string state_id MUST fall through to the type-name "icebox" filter.
  echo "$output" | jq -e '.invocation.command | contains("--state") and contains("icebox")'
  # And NOT pass --state '' literally (which would surface as a server error
  # or silent no-op on Linear's side).
  echo "$output" | jq -e ".invocation.command | contains(\"--state ''\") | not"
}

# =========================================================================
# Step 7 — Default idea-list excludes terminal + deferred states (AC-9).
# =========================================================================

@test "Step 7: idea-list default excludes icebox, canceled, duplicate" {
  set -e
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
  set -e
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

@test "Step 5: Linear idea.merge returns save_issue with state=duplicate (no duplicateOf in resolver)" {
  set -e
  # OP_ARGS is the source uid (uniform with promote/defer/dismiss); the
  # skill pairs duplicateOf in at dispatch time from user input. The
  # resolver returns only the invariant dispatch shape.
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.merge src-uid --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "eeeeeeee-0000-0000-0000-000000000005"'
  echo "$output" | jq -e '.invocation.params | has("duplicateOf") | not'
}

@test "Step 5: Linear idea.promote omits state when state_ids absent" {
  _linear_config_no_state_ids
  run bash "$OPS" resolve idea.promote --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params | has("state") | not'
}

@test "Step 5: Linear idea.defer omits state when state_ids absent" {
  _linear_config_no_state_ids
  run bash "$OPS" resolve idea.defer --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params | has("state") | not'
}

@test "Step 5: Linear idea.dismiss omits state when state_ids absent" {
  _linear_config_no_state_ids
  run bash "$OPS" resolve idea.dismiss --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params | has("state") | not'
}

@test "Step 5: Linear idea.merge omits state when state_ids absent" {
  _linear_config_no_state_ids
  run bash "$OPS" resolve idea.merge src-uid --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params | has("state") | not'
}

@test "Step 5: local idea.merge resolves to idea-update <source-uid> duplicate" {
  set -e
  # Verifies the resolver emits the right command shape (source = OP_ARGS).
  # The end-to-end rewrite is already covered by Step 6's update vocab tests.
  run bash "$OPS" resolve idea.merge src1 --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.invocation.command | test("idea-update src1 duplicate")'
}

# =========================================================================
# Step 4 — Local idea.triage adapter uses --status triage (not legacy "new").
# Covers AC-2 (local half).
# =========================================================================

@test "Step 4: local idea.triage adapter invokes idea-list --status triage" {
  set -e
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | test("idea-list --status triage")'
  echo "$output" | jq -e '.invocation.command | test("--status new") | not'
}

# =========================================================================
# BTS-121 — idea.add routes Linear captures to Triage via state.
# Empirically falsified the prior "Linear auto-routes API-created issues to
# Triage" assumption; team default (Backlog) wins when no state is passed.
# Resolver now injects state from state_ids.triage using the same
# conditional-merge pattern as idea.{promote,defer,dismiss,merge}.
# =========================================================================

@test "BTS-121 AC-1: idea.add http command includes --state when state_ids.triage is configured (BTS-166)" {
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--state") and contains("aaaaaaaa-0000-0000-0000-000000000001")'
}

@test "BTS-121 AC-2: idea.add http command — --state is additive (project/team/labels still present, BTS-166)" {
  set -e
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("Test Project")'
  echo "$output" | jq -e '.invocation.command | contains("Test Team")'
  echo "$output" | jq -e '.invocation.command | contains("--labels") and contains("idea")'
  echo "$output" | jq -e '.invocation.command | contains("--state")'
}

@test "BTS-121 AC-3: idea.add http command omits --state when state_ids absent (BTS-166)" {
  set -e
  _linear_config_no_state_ids
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--state") | not'
  # Existing contract still holds — project/team/labels present.
  echo "$output" | jq -e '.invocation.command | contains("Test Project")'
  echo "$output" | jq -e '.invocation.command | contains("--labels") and contains("idea")'
}

@test "BTS-121 AC-5: idea.add http command omits --state when state_ids.triage is empty string (BTS-166)" {
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
        "state_ids": {
          "triage": "",
          "backlog": "bbbbbbbb-0000-0000-0000-000000000002"
        }
      }
    },
    "routing": { "idea": "linear" }
  }
}
JSON
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # Empty string must be treated as unconfigured to avoid Linear API errors
  # or silent no-ops from passing --state ''.
  echo "$output" | jq -e '.invocation.command | contains("--state") | not'
}

# =========================================================================
# Step 3 — Capture routes to Linear-native Triage via explicit state.
# Covers AC-1 (Linear half): idea.add passes state=<UUID> when configured,
# superseded by the BTS-121 block above but retained to assert contract
# invariants: no legacy `stateId` key (BTS-139 rename guard), project/team/
# labels still present.
# =========================================================================

@test "Step 3: idea.add Linear resolver does NOT pass legacy stateId flag (BTS-139 regression guard, BTS-166)" {
  set -e
  _linear_config_with_state_ids
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # Post-BTS-139: the legacy `--state-id` / `stateId` form must never appear.
  # The wrapper accepts only --state.
  echo "$output" | jq -e '.invocation.command | contains("stateId") | not'
  echo "$output" | jq -e '.invocation.command | contains("--state-id") | not'
  # Project + team + labels still present.
  echo "$output" | jq -e '.invocation.command | contains("Test Project")'
  echo "$output" | jq -e '.invocation.command | contains("--labels") and contains("idea")'
}

@test "Step 2: idea.triage resolve has no legacy stateId flag when config lacks state_ids (BTS-166)" {
  _linear_config_no_state_ids
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # Falls through to type-name "triage" via --state when state_ids absent.
  echo "$output" | jq -e '.invocation.command | contains("stateId") | not'
  echo "$output" | jq -e '.invocation.command | contains("--state") and contains("triage")'
}

@test "Step 1: cmd_idea_count sums legacy + new vocab into new-named counters" {
  set -e
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
