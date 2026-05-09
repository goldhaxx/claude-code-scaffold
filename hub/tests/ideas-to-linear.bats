#!/usr/bin/env bats
# Tests for the ideas-to-linear feature.
# Covers the provider-routing layer for idea.* operations (Step 1 of the plan).
# Later steps extend this file with coverage for docs-check.sh rewiring,
# skill grep assertions, migration, and broadcast hints.

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"
DOCS_CHECK="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  # BTS-385: isolate from real ~/.ccanvil/operator.json (BTS-316 3-tier merge)
  # so the operator's config doesn't bleed into fixtures that assert
  # provider-resolution failure modes.
  export CCANVIL_OPERATOR_CONFIG_OVERRIDE="${BATS_TEST_TMPDIR}/no-operator-config.json"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.ccanvil"
}

teardown() {
  rm -rf "$PROJECT"
}

# Helper: write a Linear-routed config
_linear_config() {
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
        "icebox_status": "Icebox"
      }
    },
    "routing": {
      "idea": "linear"
    }
  }
}
JSON
}

# =========================================================================
# AC-14: is_valid_operation recognizes idea.{add,list,triage,sync}
# =========================================================================

@test "AC-14: idea.add is a valid operation (resolves with no config)" {
  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "AC-14: idea.list is a valid operation" {
  run bash "$SCRIPT" resolve idea.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "AC-14: idea.triage is a valid operation" {
  run bash "$SCRIPT" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "AC-14: idea.sync is a valid operation" {
  run bash "$SCRIPT" resolve idea.sync --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
}

# =========================================================================
# AC-16: local_adapter — no-config + routing=local → bash targeting docs-check.sh
# =========================================================================

@test "AC-16: idea.add with no config resolves to local bash adapter" {
  set -e
  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
  echo "$output" | jq -e '.invocation.command | test("docs-check.sh idea-add")'
}

@test "AC-16: idea.list with no config resolves to local bash adapter" {
  set -e
  run bash "$SCRIPT" resolve idea.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
  echo "$output" | jq -e '.invocation.command | test("docs-check.sh idea-list")'
}

@test "AC-16: idea.triage with no config resolves to local bash adapter" {
  set -e
  run bash "$SCRIPT" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
  echo "$output" | jq -e '.invocation.command | test("docs-check.sh idea-list")'
}

@test "AC-16: idea.sync with no config resolves to local bash no-op" {
  set -e
  run bash "$SCRIPT" resolve idea.sync --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
  # Local sync is a no-op — just needs to exit 0
}

@test "AC-16: idea operations contract declares output fields" {
  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  echo "$output" | jq -e '.contract.output | length > 0'
}

# =========================================================================
# AC-15: linear_mcp_adapter — idea.* → correct MCP tool + params
# =========================================================================

@test "AC-15: idea.add with Linear routing → save-issue http command (BTS-166)" {
  set -e
  _linear_config
  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  echo "$output" | jq -e '.mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("save-issue")'
  echo "$output" | jq -e '.invocation.command | contains("Test Team")'
  echo "$output" | jq -e '.invocation.command | contains("Test Project")'
  echo "$output" | jq -e '.invocation.command | contains("idea")'
  # This fixture lacks state_ids, so --state is absent. idea-triage-native AC-1
  # asserts the positive path (state_ids configured → --state present) and
  # the empty-string guard.
  echo "$output" | jq -e '.invocation.command | contains("--state") | not'
}

@test "AC-15: idea.list with Linear routing → list-issues http command (BTS-166)" {
  set -e
  _linear_config
  run bash "$SCRIPT" resolve idea.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("list-issues")'
  echo "$output" | jq -e '.invocation.command | contains("idea")'
  echo "$output" | jq -e '.invocation.command | contains("Test Project")'
}

@test "AC-15: idea.triage with Linear routing → list-issues http command with --state triage (BTS-166)" {
  set -e
  _linear_config
  run bash "$SCRIPT" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("list-issues")'
  # No state_ids in this fixture → falls through to the type-name "triage".
  echo "$output" | jq -e '.invocation.command | contains("--state") and contains("triage")'
  echo "$output" | jq -e '.invocation.command | contains("idea")'
}

@test "AC-15: idea.sync with Linear routing → local bash orchestration" {
  set -e
  # sync drains the pending log — orchestration, not a single MCP call.
  # Resolves to local bash even when Linear is configured.
  # BTS-179: resolver now points at idea-pending-replay (substrate dispatch
  # primitive), not idea-sync (which stays as enumerate-only).
  _linear_config
  run bash "$SCRIPT" resolve idea.sync --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
  echo "$output" | jq -e '.invocation.command | test("docs-check.sh idea-pending-replay")'
}

# =========================================================================
# AC-21: missing config fallback — routing unset or "local" → local adapter
# =========================================================================

@test "AC-21: routing.idea unset → local provider (no error)" {
  mkdir -p "$PROJECT/.claude"
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {},
    "routing": {
      "backlog": "linear"
    }
  }
}
JSON
  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
}

@test "AC-21: routing.idea = \"local\" explicitly → local provider" {
  mkdir -p "$PROJECT/.claude"
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {},
    "routing": {"idea": "local"}
  }
}
JSON
  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
}

@test "AC-21: routing.idea = \"linear\" without provider entry → error" {
  mkdir -p "$PROJECT/.claude"
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {},
    "routing": {"idea": "linear"}
  }
}
JSON
  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'ERROR: provider "linear" is configured for idea'
}

# =========================================================================
# AC-16 (local implementation): docs-check.sh idea-{add,list,count,update}
# now backed by .ccanvil/ideas.log (JSONL), not docs/ideas.md
# =========================================================================

@test "AC-16: idea-add writes JSONL to .ccanvil/ideas.log" {
  set -e
  run bash "$DOCS_CHECK" idea-add "a new idea" "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.ccanvil/ideas.log" ]
  # One JSONL line with uid, created, status=triage, title, body.
  # (Superseded by idea-triage-native AC-1 — prior behavior wrote status="new".)
  local line
  line=$(cat "$PROJECT/.ccanvil/ideas.log")
  echo "$line" | jq -e '.uid | test("^[0-9a-f]{4}$")'
  echo "$line" | jq -e '.created | tonumber > 0'
  echo "$line" | jq -e '.status == "triage"'
  echo "$line" | jq -e '.body == "a new idea"'
  # No --title → title defaults to body for short text (AC-22 path at CLI level)
  echo "$line" | jq -e '.title == "a new idea"'
}

@test "AC-16: idea-add with --title uses provided title, body unchanged" {
  set -e
  run bash "$DOCS_CHECK" idea-add "a very long body with lots of context that exceeds eighty characters by a wide margin and keeps going" --title "concise summary" "$PROJECT"
  [ "$status" -eq 0 ]
  local line
  line=$(cat "$PROJECT/.ccanvil/ideas.log")
  echo "$line" | jq -e '.title == "concise summary"'
  echo "$line" | jq -e '.body | test("a very long body")'
}

@test "AC-16: idea-add appends (multi-entry .ccanvil/ideas.log)" {
  bash "$DOCS_CHECK" idea-add "first" "$PROJECT" >/dev/null
  bash "$DOCS_CHECK" idea-add "second" "$PROJECT" >/dev/null
  bash "$DOCS_CHECK" idea-add "third" "$PROJECT" >/dev/null
  local count
  count=$(wc -l < "$PROJECT/.ccanvil/ideas.log")
  [ "$count" -eq 3 ]
  # Each line is valid JSON
  while IFS= read -r line; do
    echo "$line" | jq -e '.uid and .body' >/dev/null
  done < "$PROJECT/.ccanvil/ideas.log"
}

@test "AC-16: idea-list reads JSONL and outputs JSON array" {
  set -e
  cat > "$PROJECT/.ccanvil/ideas.log" <<'EOF'
{"uid":"a1b2","created":1776000001,"status":"new","title":"first","body":"first"}
{"uid":"c3d4","created":1776000002,"status":"promoted","title":"second","body":"second"}
{"uid":"e5f6","created":1776000003,"status":"dismissed","title":"third","body":"third"}
EOF
  run bash "$DOCS_CHECK" idea-list "$PROJECT"
  [ "$status" -eq 0 ]
  # Default view now excludes terminal states (canceled/dismissed, etc.) —
  # superseded by idea-triage-native AC-9. Expect 2 entries, not 3.
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
  echo "$output" | jq -e '.[0].id == "a1b2"'
  echo "$output" | jq -e '.[0].created == 1776000001'
  echo "$output" | jq -e '.[0].status == "new"'
}

@test "AC-16: idea-list filters by status" {
  cat > "$PROJECT/.ccanvil/ideas.log" <<'EOF'
{"uid":"a1b2","created":1776000001,"status":"new","title":"one","body":"one"}
{"uid":"c3d4","created":1776000002,"status":"promoted","title":"two","body":"two"}
{"uid":"e5f6","created":1776000003,"status":"new","title":"three","body":"three"}
EOF
  run bash "$DOCS_CHECK" idea-list --status new "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "AC-16: idea-count returns totals by status" {
  set -e
  cat > "$PROJECT/.ccanvil/ideas.log" <<'EOF'
{"uid":"a1b2","created":1776000001,"status":"new","title":"a","body":"a"}
{"uid":"c3d4","created":1776000002,"status":"new","title":"b","body":"b"}
{"uid":"e5f6","created":1776000003,"status":"promoted","title":"c","body":"c"}
{"uid":"1a2b","created":1776000004,"status":"dismissed","title":"d","body":"d"}
{"uid":"3c4d","created":1776000005,"status":"merged","title":"e","body":"e","parent":"BTS-99"}
EOF
  run bash "$DOCS_CHECK" idea-count "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 5'
  echo "$output" | jq -e '.new == 2'
  echo "$output" | jq -e '.promoted == 1'
  echo "$output" | jq -e '.dismissed == 1'
  echo "$output" | jq -e '.merged == 1'
}

@test "AC-16: idea-count on empty log returns all zeros" {
  set -e
  run bash "$DOCS_CHECK" idea-count "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 0'
  echo "$output" | jq -e '.new == 0'
}

@test "AC-16: idea-update mutates status by UID" {
  cat > "$PROJECT/.ccanvil/ideas.log" <<'EOF'
{"uid":"a1b2","created":1776000001,"status":"new","title":"first","body":"first"}
{"uid":"c3d4","created":1776000002,"status":"new","title":"second","body":"second"}
EOF
  run bash "$DOCS_CHECK" idea-update c3d4 promoted "$PROJECT"
  [ "$status" -eq 0 ]
  # c3d4 should be promoted, a1b2 untouched
  local c3d4_status a1b2_status
  c3d4_status=$(grep '"uid":"c3d4"' "$PROJECT/.ccanvil/ideas.log" | jq -r .status)
  a1b2_status=$(grep '"uid":"a1b2"' "$PROJECT/.ccanvil/ideas.log" | jq -r .status)
  [ "$c3d4_status" = "promoted" ]
  [ "$a1b2_status" = "new" ]
}

@test "AC-16: idea-update with nonexistent UID exits nonzero" {
  cat > "$PROJECT/.ccanvil/ideas.log" <<'EOF'
{"uid":"a1b2","created":1776000001,"status":"new","title":"only","body":"only"}
EOF
  run bash "$DOCS_CHECK" idea-update zzzz promoted "$PROJECT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not found"
}

# =========================================================================
# AC-3 / AC-30: hub config shape and isolation between shared + local files
# =========================================================================

@test "AC-3: hub ccanvil.json ships providers.linear defaults (no routing, no project/team)" {
  set -e
  local hub_json="$BATS_TEST_DIRNAME/../../.claude/ccanvil.json"
  [ -f "$hub_json" ]
  # Provider defaults are present
  jq -e '.integrations.providers.linear.mechanism == "mcp"' "$hub_json"
  jq -e '.integrations.providers.linear.idea_label == "idea"' "$hub_json"
  jq -e '.integrations.providers.linear.idea_status == "Idea"' "$hub_json"
  jq -e '.integrations.providers.linear.icebox_status == "Icebox"' "$hub_json"
  # routing is NOT in the shared file
  jq -e '.integrations.routing // null | not' "$hub_json"
}

@test "AC-30: hub ccanvil.json contains no node-specific fields (project/team)" {
  set -e
  local hub_json="$BATS_TEST_DIRNAME/../../.claude/ccanvil.json"
  # No top-level mention of ccanvil project identity or team name
  ! jq -e '.integrations.providers.linear.project // null' "$hub_json" | grep -qv "null"
  ! jq -e '.integrations.providers.linear.team // null' "$hub_json" | grep -qv "null"
}

@test "AC-3: hub ccanvil.local.json pins hub's own project + team" {
  set -e
  local hub_local="$BATS_TEST_DIRNAME/../../.claude/ccanvil.local.json"
  [ -f "$hub_local" ]
  jq -e '.integrations.routing.idea == "linear"' "$hub_local"
  jq -e '.integrations.providers.linear.project == "ccanvil"' "$hub_local"
  jq -e '.integrations.providers.linear.team == "Blocktech Solutions"' "$hub_local"
}

@test "AC-3: merged config combines shared defaults + node overrides" {
  set -e
  # Fixture: copy hub configs into a temp PROJECT and merge.
  mkdir -p "$PROJECT/.claude"
  cp "$BATS_TEST_DIRNAME/../../.claude/ccanvil.json" "$PROJECT/.claude/ccanvil.json"
  cp "$BATS_TEST_DIRNAME/../../.claude/ccanvil.local.json" "$PROJECT/.claude/ccanvil.local.json"

  local merged
  merged=$(bash "$SCRIPT" merge-config --project-dir "$PROJECT")
  # Provider defaults (from shared) survive
  echo "$merged" | jq -e '.integrations.providers.linear.mechanism == "mcp"'
  echo "$merged" | jq -e '.integrations.providers.linear.idea_label == "idea"'
  # Node overrides (from local) survive
  echo "$merged" | jq -e '.integrations.routing.idea == "linear"'
  echo "$merged" | jq -e '.integrations.providers.linear.project == "ccanvil"'
  echo "$merged" | jq -e '.integrations.providers.linear.team == "Blocktech Solutions"'
}

@test "AC-3: resolve idea.add on hub config → Linear http save-issue with full params (BTS-166)" {
  set -e
  mkdir -p "$PROJECT/.claude"
  cp "$BATS_TEST_DIRNAME/../../.claude/ccanvil.json" "$PROJECT/.claude/ccanvil.json"
  cp "$BATS_TEST_DIRNAME/../../.claude/ccanvil.local.json" "$PROJECT/.claude/ccanvil.local.json"

  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  echo "$output" | jq -e '.mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("save-issue")'
  echo "$output" | jq -e '.invocation.command | contains("ccanvil")'
  echo "$output" | jq -e '.invocation.command | contains("Blocktech Solutions")'
  # Post-BTS-121 + BTS-166: --state is PRESENT (the Triage UUID from
  # state_ids.triage in ccanvil.local.json). The legacy stateId / --state-id
  # form must never appear (BTS-139 guard).
  echo "$output" | jq -e '.invocation.command | contains("--state") and (contains("--state-id") | not) and (contains("stateId") | not)'
  echo "$output" | jq -e '.invocation.command | contains("--labels") and contains("idea")'
}

@test "AC-29: shared ccanvil.json alone (no local override) → local provider" {
  # A downstream node that has only the shared file and hasn't created
  # ccanvil.local.json yet. routing.idea is absent → local.
  mkdir -p "$PROJECT/.claude"
  cp "$BATS_TEST_DIRNAME/../../.claude/ccanvil.json" "$PROJECT/.claude/ccanvil.json"

  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
}

# =========================================================================
# AC-4/5/6/7/8/22/23: /idea skill wiring for the dual-provider flow
# Grep assertions on .claude/skills/idea/SKILL.md.
# =========================================================================

SKILL_FILE="$BATS_TEST_DIRNAME/../../.claude/skills/idea/SKILL.md"

@test "AC-23: skill file exists and has yaml frontmatter" {
  [ -f "$SKILL_FILE" ]
  head -5 "$SKILL_FILE" | grep -q '^name: idea$'
}

@test "AC-23: skill references operations.sh resolve idea.add" {
  grep -q 'operations.sh resolve idea.add' "$SKILL_FILE"
}

@test "AC-23: skill references operations.sh resolve idea.list / idea.triage / idea.sync" {
  grep -q 'operations.sh resolve idea.list' "$SKILL_FILE"
  grep -q 'operations.sh resolve idea.triage' "$SKILL_FILE"
  grep -q 'operations.sh resolve idea.sync' "$SKILL_FILE"
}

@test "AC-23: skill describes mechanism field (BTS-166: http for Linear, bash for local)" {
  grep -qE 'mechanism.*(http|bash)|\.mechanism' "$SKILL_FILE"
  grep -q 'http' "$SKILL_FILE"
  grep -q 'bash' "$SKILL_FILE"
}

@test "AC-23: skill dispatches Linear ops via linear-query.sh substrate (BTS-166)" {
  # BTS-166 migrated capture/list/triage/review-icebox from MCP to the http
  # substrate. Skill prose must reference the wrapper and the eval pattern,
  # not the legacy mcp__claude_ai_Linear__* tool names on the linear path.
  grep -q 'linear-query.sh' "$SKILL_FILE"
  grep -qE 'eval .*invocation\.command' "$SKILL_FILE"
  # Negative guard: capture/list paths must NOT call MCP tools directly.
  ! grep -qE 'mcp__claude_ai_Linear__(save_issue|list_issues)' "$SKILL_FILE"
}

@test "AC-23: skill writes to .ccanvil/ideas.log for the local path" {
  grep -q '.ccanvil/ideas.log' "$SKILL_FILE"
}

@test "AC-4: skill describes title-summarization step" {
  grep -qiE 'summar|concise title|title.*body' "$SKILL_FILE"
}

@test "AC-22: skill describes short-text fast path (no summarization)" {
  grep -qE '80 chars|short.*(skip|direct)|single-line' "$SKILL_FILE"
}

@test "AC-5: skill documents that capture avoids git entirely" {
  grep -qiE 'no (git|commits|branch)|without a (commit|branch)|never (commits|touches git)' "$SKILL_FILE"
}

@test "AC-6: skill reports Linear issue ID on capture" {
  grep -qE 'BTS-|issue ID|\.identifier' "$SKILL_FILE"
}

@test "AC-8: skill maps triage outcomes to Linear actions" {
  grep -qiE 'promote' "$SKILL_FILE"
  grep -qiE 'merge.*duplicate|Mark.*duplicate|duplicateOf' "$SKILL_FILE"
  grep -qiE 'park.*Icebox|Icebox' "$SKILL_FILE"
  grep -qiE 'dismiss.*Cancel|state.*Cancel|Decline' "$SKILL_FILE"
}

@test "AC-7: skill documents idea.list rendering" {
  grep -qE 'ID.*Created.*Title|ID.*Title.*Status|table' "$SKILL_FILE"
}

@test "AC-9/20: skill describes pending-log fallback on MCP failure" {
  grep -q 'ideas-pending.log' "$SKILL_FILE"
}

@test "AC-23: skill file remains a hub-shared asset (has NODE-SPECIFIC-START delimiter)" {
  grep -q '<!-- NODE-SPECIFIC-START -->' "$SKILL_FILE"
}

# =========================================================================
# AC-9/10/11: pending log + idea-sync primitives
# =========================================================================

@test "AC-10: idea-sync with empty/absent pending log reports zero" {
  set -e
  run bash "$DOCS_CHECK" idea-sync "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pending == 0'
  echo "$output" | jq -e '.entries | length == 0'
}

@test "AC-10: idea-sync lists pending entries as JSON" {
  set -e
  cat > "$PROJECT/.ccanvil/ideas-pending.log" <<'EOF'
{"op":"add","args":{"title":"first","body":"first idea"},"ts":1776000001}
{"op":"add","args":{"title":"second","body":"second idea"},"ts":1776000002}
EOF
  run bash "$DOCS_CHECK" idea-sync "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pending == 2'
  echo "$output" | jq -e '.entries | length == 2'
  echo "$output" | jq -e '.entries[0].args.title == "first"'
}

@test "AC-10: idea-sync --ack <ts> removes the matching entry" {
  cat > "$PROJECT/.ccanvil/ideas-pending.log" <<'EOF'
{"op":"add","args":{"title":"keep"},"ts":1776000001}
{"op":"add","args":{"title":"drop"},"ts":1776000002}
{"op":"add","args":{"title":"also-keep"},"ts":1776000003}
EOF
  run bash "$DOCS_CHECK" idea-sync --ack 1776000002 "$PROJECT"
  [ "$status" -eq 0 ]
  local remaining
  remaining=$(wc -l < "$PROJECT/.ccanvil/ideas-pending.log")
  [ "$remaining" -eq 2 ]
  ! grep -q '"drop"' "$PROJECT/.ccanvil/ideas-pending.log"
  grep -q '"keep"' "$PROJECT/.ccanvil/ideas-pending.log"
  grep -q '"also-keep"' "$PROJECT/.ccanvil/ideas-pending.log"
}

@test "AC-11: idea-sync --ack missing-ts is a no-op (entries unchanged)" {
  cat > "$PROJECT/.ccanvil/ideas-pending.log" <<'EOF'
{"op":"add","args":{"title":"only"},"ts":1776000001}
EOF
  run bash "$DOCS_CHECK" idea-sync --ack 9999999999 "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q '"only"' "$PROJECT/.ccanvil/ideas-pending.log"
}

# =========================================================================
# AC-12/13/27: idea-migrate
# =========================================================================

@test "AC-13: idea-migrate on project with no docs/ideas.md → exit 0, 'Nothing to migrate'" {
  run bash "$DOCS_CHECK" idea-migrate "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "nothing to migrate"
}

@test "AC-12: idea-migrate (local mode) moves entries to .ccanvil/ideas.log" {
  mkdir -p "$PROJECT/docs"
  cat > "$PROJECT/docs/ideas.md" <<'EOF'
# Ideas

- [ ] a1b2 1776000001: first migrated idea <!-- status:new -->
- [ ] c3d4 1776000002: second migrated idea <!-- status:new -->
EOF
  # Init git repo so 'git rm' works in the finalize step
  (cd "$PROJECT" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "init")

  run bash "$DOCS_CHECK" idea-migrate "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.ccanvil/ideas.log" ]
  local count
  count=$(wc -l < "$PROJECT/.ccanvil/ideas.log")
  [ "$count" -eq 2 ]
  grep -q "first migrated idea" "$PROJECT/.ccanvil/ideas.log"
  grep -q "second migrated idea" "$PROJECT/.ccanvil/ideas.log"
}

@test "AC-12: idea-migrate (local mode) removes docs/ideas.md and updates .gitignore" {
  mkdir -p "$PROJECT/docs"
  cat > "$PROJECT/docs/ideas.md" <<'EOF'
- [ ] a1b2 1776000001: some idea <!-- status:new -->
EOF
  (cd "$PROJECT" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "init")

  run bash "$DOCS_CHECK" idea-migrate "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/docs/ideas.md" ]
  grep -qxF "docs/ideas.md" "$PROJECT/.gitignore"
  grep -qxF ".ccanvil/ideas.log" "$PROJECT/.gitignore"
  grep -qxF ".ccanvil/ideas-pending.log" "$PROJECT/.gitignore"
}

@test "AC-12: idea-migrate --extract emits JSONL intents without removing anything" {
  set -e
  mkdir -p "$PROJECT/docs"
  cat > "$PROJECT/docs/ideas.md" <<'EOF'
- [ ] a1b2 1776000001: extract me <!-- status:new -->
- [ ] c3d4 1776000002: and me <!-- status:new -->
EOF

  run bash "$DOCS_CHECK" idea-migrate --extract "$PROJECT"
  [ "$status" -eq 0 ]
  # File still present (no side effects)
  [ -f "$PROJECT/docs/ideas.md" ]
  # Output is JSONL of intents
  local count
  count=$(echo "$output" | wc -l)
  [ "$count" -ge 2 ]
  echo "$output" | head -1 | jq -e '.title == "extract me"'
  echo "$output" | head -1 | jq -e '.body == "extract me"'
}

@test "AC-12: idea-migrate --finalize removes docs/ideas.md + updates .gitignore" {
  mkdir -p "$PROJECT/docs"
  echo "- [ ] a1b2 1776000001: x <!-- status:new -->" > "$PROJECT/docs/ideas.md"
  (cd "$PROJECT" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "init")

  run bash "$DOCS_CHECK" idea-migrate --finalize "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/docs/ideas.md" ]
  grep -qxF "docs/ideas.md" "$PROJECT/.gitignore"
}

@test "AC-13: idea-migrate --finalize when docs/ideas.md is already absent → idempotent" {
  run bash "$DOCS_CHECK" idea-migrate --finalize "$PROJECT"
  [ "$status" -eq 0 ]
}

# =========================================================================
# AC-25: cmd_activate dirty-worktree allowlist no longer tolerates ideas.md
# =========================================================================

# =========================================================================
# idea-setup: scaffold the per-node Linear / local config
# =========================================================================

@test "idea-setup --provider local writes routing.idea=local + gitignore" {
  run bash "$DOCS_CHECK" idea-setup --provider local "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.claude/ccanvil.local.json" ]
  jq -e '.integrations.routing.idea == "local"' "$PROJECT/.claude/ccanvil.local.json"
  # Gitignore entries
  grep -qxF ".ccanvil/ideas.log" "$PROJECT/.gitignore"
  grep -qxF ".ccanvil/ideas-pending.log" "$PROJECT/.gitignore"
  grep -qxF "docs/ideas.md" "$PROJECT/.gitignore"
}

@test "idea-setup --provider linear requires --team and --project" {
  run bash "$DOCS_CHECK" idea-setup --provider linear "$PROJECT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "team"

  run bash "$DOCS_CHECK" idea-setup --provider linear --team X "$PROJECT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "project"
}

@test "idea-setup --provider linear writes routing.idea=linear + provider config" {
  set -e
  run bash "$DOCS_CHECK" idea-setup --provider linear --team "BTS Team" --project "my-project" "$PROJECT"
  [ "$status" -eq 0 ]
  jq -e '.integrations.routing.idea == "linear"' "$PROJECT/.claude/ccanvil.local.json"
  jq -e '.integrations.providers.linear.team == "BTS Team"' "$PROJECT/.claude/ccanvil.local.json"
  jq -e '.integrations.providers.linear.project == "my-project"' "$PROJECT/.claude/ccanvil.local.json"
}

@test "idea-setup preserves pre-existing ccanvil.local.json fields (deep merge)" {
  set -e
  mkdir -p "$PROJECT/.claude"
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{
  "node_uuid": "c0ffee00-0000-4000-8000-000000000001",
  "other_thing": {"keep_me": true}
}
JSON
  run bash "$DOCS_CHECK" idea-setup --provider local "$PROJECT"
  [ "$status" -eq 0 ]
  # Existing fields survive
  jq -e '.node_uuid == "c0ffee00-0000-4000-8000-000000000001"' "$PROJECT/.claude/ccanvil.local.json"
  jq -e '.other_thing.keep_me == true' "$PROJECT/.claude/ccanvil.local.json"
  # New routing is present
  jq -e '.integrations.routing.idea == "local"' "$PROJECT/.claude/ccanvil.local.json"
}

@test "idea-setup is idempotent (no duplicate gitignore lines)" {
  bash "$DOCS_CHECK" idea-setup --provider local "$PROJECT" >/dev/null
  bash "$DOCS_CHECK" idea-setup --provider local "$PROJECT" >/dev/null

  local log_count pending_count md_count
  log_count=$(grep -cxF ".ccanvil/ideas.log" "$PROJECT/.gitignore")
  pending_count=$(grep -cxF ".ccanvil/ideas-pending.log" "$PROJECT/.gitignore")
  md_count=$(grep -cxF "docs/ideas.md" "$PROJECT/.gitignore")
  [ "$log_count" -eq 1 ]
  [ "$pending_count" -eq 1 ]
  [ "$md_count" -eq 1 ]
}

@test "idea-setup output names the manual next steps (Linear statuses + migrate)" {
  run bash "$DOCS_CHECK" idea-setup --provider linear --team T --project P "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE "Idea.*status|create.*status"
  echo "$output" | grep -qi "idea-migrate"
}

@test "migration guide exists and names the setup/migrate commands" {
  local guide="$BATS_TEST_DIRNAME/../../.ccanvil/guide/ideas-migration.md"
  [ -f "$guide" ]
  grep -q 'idea-setup' "$guide"
  grep -q 'idea-migrate' "$guide"
  grep -q 'routing.idea' "$guide"
  # Has the hub-managed delimiter so it distributes cleanly
  grep -q '<!-- NODE-SPECIFIC-START -->' "$guide"
}

@test "command-reference.md documents idea-setup and points to the migration guide" {
  local ref="$BATS_TEST_DIRNAME/../../.ccanvil/guide/command-reference.md"
  grep -q 'idea-setup' "$ref"
  grep -q 'ideas-migration.md' "$ref"
}

@test "idea-setup --provider linear resolves cleanly via operations.sh" {
  set -e
  bash "$DOCS_CHECK" idea-setup --provider linear --team "BTS Team" --project "my-project" "$PROJECT" >/dev/null
  # Also copy shared ccanvil.json so merge has the provider defaults
  cp "$BATS_TEST_DIRNAME/../../.claude/ccanvil.json" "$PROJECT/.claude/ccanvil.json"

  run bash "$SCRIPT" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  # BTS-166: idea.add now emits mechanism=http with team/project on the command.
  echo "$output" | jq -e '.mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("BTS Team")'
  echo "$output" | jq -e '.invocation.command | contains("my-project")'
}

@test "AC-25: activate halts when docs/ideas.md is uncommitted (no longer allowlisted)" {
  # Build a minimal repo fixture with a valid spec so activate progresses
  # past the spec-lookup step and reaches the dirty-worktree check.
  local ACT
  ACT=$(mktemp -d)
  git -C "$ACT" init -q -b main
  mkdir -p "$ACT/docs/specs"
  cat > "$ACT/docs/specs/some-spec.md" <<'SPEC'
# Feature: some-spec

> Feature: some-spec
> Created: 1776000000
> Status: Draft

## Summary

Test fixture.
SPEC
  git -C "$ACT" add -A
  git -C "$ACT" -c user.email=t@t -c user.name=t commit -q -m "init"

  # Uncommitted docs/ideas.md — used to be allowed, now must block.
  echo "- [ ] a1b2 1776000001: stale <!-- status:new -->" > "$ACT/docs/ideas.md"

  cd "$ACT"
  run bash "$DOCS_CHECK" activate some-spec "$ACT/docs"
  [ "$status" -eq 1 ]
  # Spec was found (dirty check runs after spec-lookup). Failure must be
  # the dirty-worktree path, not spec-not-found.
  ! echo "$output" | grep -q "not found in"
  echo "$output" | grep -qiE "dirty|uncommitted|worktree|clean"

  rm -rf "$ACT"
}

@test "AC-16: legacy docs/ideas.md is NOT consulted by new code paths" {
  # A stale docs/ideas.md should be ignored — the new store is
  # .ccanvil/ideas.log only.
  mkdir -p "$PROJECT/docs"
  echo "- [ ] dead 1700000000: stale legacy entry <!-- status:new -->" \
    > "$PROJECT/docs/ideas.md"

  run bash "$DOCS_CHECK" idea-list "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 0 ]

  run bash "$DOCS_CHECK" idea-count "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 0'
}
