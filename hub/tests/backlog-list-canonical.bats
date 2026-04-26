#!/usr/bin/env bats
# BTS-175 — backlog.list resolver: http mechanism for Linear-routed projects,
# state-id filter (NOT label filter), routing.idea→backlog fallback, and
# explicit error when state_ids.backlog is missing.

bats_require_minimum_version 1.5.0

OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude"
}

teardown() {
  rm -rf "$PROJECT"
}

_with_linear_routing() {
  # routing.idea = linear, state_ids.backlog configured. NO routing.backlog —
  # the fallback should fire.
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"ccanvil","team":"Blocktech Solutions","idea_label":"idea","state_ids":{"backlog":"BACKLOG-UUID-123"}}}}}
JSON
}

_with_linear_routing_no_state_ids() {
  # routing.idea = linear but state_ids.backlog NOT configured (AC-10 case).
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"ccanvil","team":"Blocktech Solutions","idea_label":"idea"}}}}
JSON
}

_with_explicit_local_backlog_routing() {
  # routing.idea = linear AND routing.backlog = local. The explicit override
  # should win — fallback does NOT fire.
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear","backlog":"local"},"providers":{"linear":{"project":"ccanvil","team":"Blocktech Solutions","idea_label":"idea","state_ids":{"backlog":"BACKLOG-UUID-123"}}}}}
JSON
}

_with_local_only_routing() {
  # No Linear provider — pure local. Backwards-compat preserved.
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"local":{"mechanism":"bash"}}}}
JSON
}

# =========================================================================
# AC-1: idea→backlog routing fallback fires when routing.backlog unset
# =========================================================================

@test "AC-1: linear-routed project (routing.idea=linear, no routing.backlog) → backlog.list resolves to linear+http" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  echo "$output" | jq -e '.mechanism == "http"'
}

# =========================================================================
# AC-2: command shape — --state filter, NO --label filter
# =========================================================================

@test "AC-2: backlog.list http command uses --state with backlog state_id" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--state")'
  echo "$output" | jq -e '.invocation.command | contains("BACKLOG-UUID-123")'
}

@test "AC-2: backlog.list http command does NOT use --label filter" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  ! echo "$output" | jq -e '.invocation.command | contains("--label")'
}

@test "AC-2: backlog.list http command shells out to linear-query.sh list-issues" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("linear-query.sh")'
  echo "$output" | jq -e '.invocation.command | contains("list-issues")'
}

@test "AC-2: backlog.list http invocation includes endpoint and auth_env" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.endpoint | contains("api.linear.app")'
  echo "$output" | jq -e '.invocation.auth_env == "LINEAR_API_KEY"'
}

# =========================================================================
# AC-4: local-only project → mechanism=bash with list-specs
# =========================================================================

@test "AC-4: local-only project → backlog.list resolves to bash + list-specs" {
  set -e
  _with_local_only_routing
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
  echo "$output" | jq -e '.invocation.command | contains("list-specs")'
}

# =========================================================================
# AC-5: explicit routing.backlog=local overrides idea-fallback
# =========================================================================

@test "AC-5: explicit routing.backlog=local overrides idea-fallback" {
  set -e
  _with_explicit_local_backlog_routing
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
}

# =========================================================================
# AC-9: deduplication — Linear path uses http only, no MCP path remains
# =========================================================================

@test "AC-9: operations.sh has no remaining MCP-mechanism backlog.list resolver" {
  # Drift-guard: the http migration removed the mcp Linear backlog.list
  # block. Check by counting list_issues MCP tool references in the Linear
  # adapter section — should be zero references with backlog.list as the
  # case label.
  ! grep -B1 'mcp__claude_ai_Linear__list_issues' "$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh" \
    | grep -q 'backlog.list)'
}

# =========================================================================
# AC-10: state_ids.backlog missing → clear error
# =========================================================================

@test "AC-10: linear-routed but state_ids.backlog missing → exit non-zero with clear error" {
  _with_linear_routing_no_state_ids
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"state_ids.backlog"* ]] || [[ "$stderr" == *"state_ids.backlog"* ]]
}
