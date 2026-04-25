#!/usr/bin/env bats
# BTS-136 — cmd_auto_transition_emit + cmd_activate's AUTO-TRANSITION marker.
# Mirror of BTS-119's auto-close-emit tests (hub/tests/auto-close-linear-on-merge.bats).

bats_require_minimum_version 1.5.0

DOCS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"
OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude" "$PROJECT/docs/specs"
}

teardown() {
  rm -rf "$PROJECT"
}

_spec_linear() {
  local id="$1" slug="$2"
  cat > "$PROJECT/docs/specs/$slug.md" <<MD
# Feature: Fixture
> Feature: $slug
> Work: linear:$id
> Created: 1777004190
> Status: In Progress
MD
}

_spec_local() {
  local uid="$1" slug="$2"
  cat > "$PROJECT/docs/specs/$slug.md" <<MD
# Feature: Fixture
> Feature: $slug
> Work: local:$uid
> Created: 1777004190
> Status: In Progress
MD
}

_spec_no_work() {
  local slug="$1"
  cat > "$PROJECT/docs/specs/$slug.md" <<MD
# Feature: Fixture (legacy)
> Feature: $slug
> Created: 1777004190
> Status: In Progress
MD
}

# ===========================================================================
# AC-2: ticket.transition accepts new roles
# ===========================================================================

@test "BTS-136 AC-2: ticket.transition accepts role=todo" {
  set -e
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"P","team":"T","state_ids":{"todo":"todo-uuid","in_progress":"prog-uuid"}}}}}
JSON
  run bash "$OPS" resolve ticket.transition BTS-X todo --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "todo-uuid"'
}

@test "BTS-136 AC-2: ticket.transition accepts role=in_progress" {
  set -e
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"P","team":"T","state_ids":{"todo":"todo-uuid","in_progress":"prog-uuid"}}}}}
JSON
  run bash "$OPS" resolve ticket.transition BTS-X in_progress --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.state == "prog-uuid"'
}

@test "BTS-136 AC-2: error message lists todo + in_progress in the valid roles" {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"P","team":"T","state_ids":{"done":"d"}}}}}
JSON
  run --separate-stderr bash "$OPS" resolve ticket.transition BTS-X bogus --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "todo" ]]
  [[ "$stderr" =~ "in_progress" ]]
}

# ===========================================================================
# AC-3 + AC-4: cmd_auto_transition_emit emits the marker
# ===========================================================================

@test "BTS-136 AC-3/AC-4: auto-transition-emit prints AUTO-TRANSITION marker for linear Work" {
  set -e
  _spec_linear "BTS-136" "bts-136-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/bts-136-foo in_progress"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "AUTO-TRANSITION: " ]]
  echo "$output" | grep "^AUTO-TRANSITION: " | sed 's/^AUTO-TRANSITION: //' | \
    jq -e '.provider == "linear" and .id == "BTS-136" and .role == "in_progress"'
}

@test "BTS-136 AC-3: auto-transition-emit silent for spec without Work: (legacy)" {
  _spec_no_work "legacy-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/legacy-foo in_progress"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-136 AC-3: auto-transition-emit silent for local-provider Work" {
  _spec_local "idea-29" "bts-local-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/bts-local-foo in_progress"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-136 AC-3: auto-transition-emit silent for non-claude branch" {
  _spec_linear "BTS-136" "bts-136-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit hotfix/urgent in_progress"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-136 AC-3: auto-transition-emit role parameter flows into marker JSON" {
  set -e
  _spec_linear "BTS-136" "bts-136-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/bts-136-foo todo"
  [ "$status" -eq 0 ]
  echo "$output" | grep "^AUTO-TRANSITION: " | sed 's/^AUTO-TRANSITION: //' | \
    jq -e '.role == "todo"'
}

# ===========================================================================
# BTS-149 AC-10/12: auto-transition-emit no longer pre-enqueues. The marker
# is the sole side effect; the /activate skill enqueues only on MCP failure
# via idea-pending-append. Inverts the BTS-148 "enqueue on every call"
# behavior to "enqueue only on dispatch failure" — eliminates write+ack
# churn on the success path.
# ===========================================================================

@test "BTS-149 AC-10: auto-transition-emit does NOT enqueue for linear Work (success path)" {
  _spec_linear "BTS-149" "bts-149-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/bts-149-foo in_progress"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "AUTO-TRANSITION: " ]]
  [ ! -f "$PROJECT/.ccanvil/ideas-pending.log" ] || [ "$(wc -c < "$PROJECT/.ccanvil/ideas-pending.log" | tr -d ' ')" -eq 0 ]
}

@test "BTS-149 AC-10: auto-transition-emit does NOT enqueue for local-provider Work" {
  _spec_local "idea-29" "bts-local-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/bts-local-foo in_progress"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.ccanvil/ideas-pending.log" ] || [ "$(wc -c < "$PROJECT/.ccanvil/ideas-pending.log" | tr -d ' ')" -eq 0 ]
}

@test "BTS-149 AC-10: auto-transition-emit does NOT enqueue for legacy spec without Work:" {
  _spec_no_work "legacy-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/legacy-foo in_progress"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.ccanvil/ideas-pending.log" ] || [ "$(wc -c < "$PROJECT/.ccanvil/ideas-pending.log" | tr -d ' ')" -eq 0 ]
}

@test "BTS-149 AC-12: two consecutive emits still leave pending log empty" {
  _spec_linear "BTS-149" "bts-149-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/bts-149-foo in_progress"
  [ "$status" -eq 0 ]
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/bts-149-foo in_progress"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.ccanvil/ideas-pending.log" ] || [ "$(wc -c < "$PROJECT/.ccanvil/ideas-pending.log" | tr -d ' ')" -eq 0 ]
}

@test "BTS-149 AC-10: marker carries role=todo without enqueue side-effect" {
  set -e
  _spec_linear "BTS-149" "bts-149-foo"
  run bash -c "cd \"$PROJECT\" && bash \"$DOCS\" auto-transition-emit claude/feat/bts-149-foo todo"
  [ "$status" -eq 0 ]
  echo "$output" | grep "^AUTO-TRANSITION: " | sed 's/^AUTO-TRANSITION: //' | \
    jq -e '.role == "todo"'
  [ ! -f "$PROJECT/.ccanvil/ideas-pending.log" ] || [ "$(wc -c < "$PROJECT/.ccanvil/ideas-pending.log" | tr -d ' ')" -eq 0 ]
}
