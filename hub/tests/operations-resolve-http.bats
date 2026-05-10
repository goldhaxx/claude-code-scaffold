#!/usr/bin/env bats
# BTS-164 — operations.sh resolver: http mechanism for Linear-routed verbs.
#
# Validates the resolver returns mechanism=http with linear-query.sh-shaped
# invocation when routing.<group> = linear. Mirror of the existing mcp tests
# but for the new substrate path.

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
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"ccanvil","team":"Blocktech Solutions","idea_label":"idea"}}}}
JSON
}

_with_local_routing() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"local":{"mechanism":"bash"}}}}
JSON
}

# ===========================================================================
# AC-4, AC-9, AC-10: idea.count resolver branching
# ===========================================================================

@test "BTS-164 AC-4: idea.count on linear-routed project emits mechanism=http" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear" and .mechanism == "http"'
}

@test "BTS-164 AC-4: idea.count http invocation carries linear-query.sh command" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("linear-query.sh")'
  echo "$output" | jq -e '.invocation.command | contains("list-issues")'
}

@test "BTS-164 AC-4: idea.count http invocation includes auth_env hint" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.auth_env == "LINEAR_API_KEY"'
}

@test "BTS-164 AC-4: idea.count http invocation includes endpoint" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.endpoint | contains("api.linear.app")'
}

@test "BTS-164 AC-4: idea.count http command interpolates project, team, label from config" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("ccanvil")'
  echo "$output" | jq -e '.invocation.command | contains("Blocktech Solutions")'
  echo "$output" | jq -e '.invocation.command | contains("idea")'
}

@test "BTS-164 AC-9: idea.count on local-routed project emits mechanism=bash" {
  set -e
  _with_local_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local" and .mechanism == "bash"'
}

@test "BTS-164 AC-9: idea.count bash invocation points to docs-check.sh idea-count-local" {
  set -e
  _with_local_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("idea-count-local")'
}

# ===========================================================================
# BTS-166 AC-4..AC-7: idea.{add,list,triage,review-icebox} migrated to http
# ===========================================================================

@test "BTS-166 AC-5: idea.list on linear-routed project emits mechanism=http" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear" and .mechanism == "http"'
}

@test "BTS-166 AC-5: idea.list http command carries linear-query.sh list-issues with project/team/label" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("linear-query.sh")'
  echo "$output" | jq -e '.invocation.command | contains("list-issues")'
  echo "$output" | jq -e '.invocation.command | contains("ccanvil")'
  echo "$output" | jq -e '.invocation.command | contains("Blocktech Solutions")'
  echo "$output" | jq -e '.invocation.command | contains("idea")'
}

@test "BTS-166 AC-6: idea.triage on linear-routed project emits mechanism=http with --state filter" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear" and .mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("list-issues")'
  echo "$output" | jq -e '.invocation.command | contains("--state")'
}

@test "BTS-166 AC-7: idea.review-icebox on linear-routed project emits mechanism=http with --state icebox" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear" and .mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("list-issues")'
  echo "$output" | jq -e '.invocation.command | contains("--state")'
}

@test "BTS-166 AC-4: idea.add on linear-routed project emits mechanism=http with save-issue" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear" and .mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | contains("save-issue")'
  echo "$output" | jq -e '.invocation.command | contains("--team")'
  echo "$output" | jq -e '.invocation.command | contains("--project")'
  echo "$output" | jq -e '.invocation.command | contains("--labels")'
  echo "$output" | jq -e '.invocation.command | contains("Blocktech Solutions")'
}

@test "BTS-166 AC-4: idea.add http command does NOT carry --title or --description (consumer fills via stdin-JSON)" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--title") | not'
  echo "$output" | jq -e '.invocation.command | contains("--description") | not'
}

@test "BTS-166: idea.add @sh-quoted command-line values handle team name with apostrophe" {
  set -e
  # Defensive regression — none of our current providers have apostrophes
  # in their names, but the resolver builds a shell-eval'd command string
  # and a future workspace name like "Blocktech's Solutions" must not break
  # the eval. The @sh filter generates valid POSIX-quoted output:
  #   Blocktech's Solutions  →  'Blocktech'\''s Solutions'
  # which eval's back to the original string verbatim.
  mkdir -p "$PROJECT/.claude"
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"ccanvil","team":"Acme's Team","idea_label":"idea"}}}}
JSON
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  # The command is a complete shell-eval'd string. Extract it and run it
  # through bash's word-splitter (printf %q is the inverse of @sh) to
  # confirm the team token round-trips to the original string.
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  # Use eval to parse the quoting; "$@" then gives us the actual tokens.
  # We never actually invoke linear-query.sh — we just confirm the parse.
  eval "set -- $cmd"
  local found="false"
  while [ $# -gt 0 ]; do
    if [ "$1" = "--team" ]; then
      [ "$2" = "Acme's Team" ] && found="true"
      break
    fi
    shift
  done
  [ "$found" = "true" ]
}

@test "BTS-166 AC-8: idea.{list,triage,add,review-icebox} on local-routed project still emit mechanism=bash" {
  set -e
  _with_local_routing
  for op in idea.list idea.triage idea.add idea.review-icebox; do
    run bash "$OPS" resolve "$op" --project-dir "$PROJECT"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.mechanism == "bash"'
  done
}

@test "BTS-164 AC-10: resolver output shape uniform across mechanisms" {
  # Both mechanisms must return the same top-level keys: provider, mechanism,
  # invocation, contract. Consumers can switch on mechanism without
  # provider-specific branches at the schema level.
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("provider") and has("mechanism") and has("invocation") and has("contract")'

  _with_local_routing
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("provider") and has("mechanism") and has("invocation") and has("contract")'
}

# ===========================================================================
# BTS-407: project_id preference — emit --project-id when configured, else
# fall back to --project <name>, else omit the flag entirely.
# ===========================================================================

_with_linear_routing_uuid_only() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project_id":"PROJ-UUID-1","team":"Blocktech Solutions","idea_label":"idea"}}}}
JSON
}

_with_linear_routing_both_set() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"ccanvil","project_id":"PROJ-UUID-1","team":"Blocktech Solutions","idea_label":"idea"}}}}
JSON
}

_with_linear_routing_neither() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"team":"Blocktech Solutions","idea_label":"idea"}}}}
JSON
}

@test "BTS-407 AC-1: idea.add with project_id only emits --project-id, never --project ''" {
  set -e
  _with_linear_routing_uuid_only
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  echo "$cmd" | grep -qF -- "--project-id 'PROJ-UUID-1'"
  ! echo "$cmd" | grep -qF -- "--project ''"
  ! echo "$cmd" | grep -qE -- "--project '[^-]"
}

@test "BTS-407 AC-2: idea.add with both project_id AND project prefers --project-id" {
  set -e
  _with_linear_routing_both_set
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  echo "$cmd" | grep -qF -- "--project-id 'PROJ-UUID-1'"
  ! echo "$cmd" | grep -qF -- "--project 'ccanvil'"
}

@test "BTS-407 AC-3: idea.add with project name only still emits --project (existing behavior)" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  echo "$cmd" | grep -qF -- "--project 'ccanvil'"
  ! echo "$cmd" | grep -qF -- "--project-id"
}

@test "BTS-407 AC-4: idea.list with project_id only emits --project-id" {
  set -e
  _with_linear_routing_uuid_only
  run bash "$OPS" resolve idea.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  echo "$cmd" | grep -qF -- "--project-id 'PROJ-UUID-1'"
  ! echo "$cmd" | grep -qF -- "--project ''"
}

@test "BTS-407 AC-4: idea.count with project_id only emits --project-id" {
  set -e
  _with_linear_routing_uuid_only
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  echo "$cmd" | grep -qF -- "--project-id 'PROJ-UUID-1'"
  ! echo "$cmd" | grep -qF -- "--project ''"
}

@test "BTS-407 AC-4: idea.triage with project_id only emits --project-id" {
  set -e
  _with_linear_routing_uuid_only
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  echo "$cmd" | grep -qF -- "--project-id 'PROJ-UUID-1'"
  ! echo "$cmd" | grep -qF -- "--project ''"
}

@test "BTS-407 AC-4: idea.review-icebox with project_id only emits --project-id" {
  set -e
  _with_linear_routing_uuid_only
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  echo "$cmd" | grep -qF -- "--project-id 'PROJ-UUID-1'"
  ! echo "$cmd" | grep -qF -- "--project ''"
}

@test "BTS-407 AC-4: backlog.list with project_id only emits --project-id" {
  set -e
  _with_linear_routing_uuid_only
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project_id":"PROJ-UUID-1","team":"Blocktech Solutions","idea_label":"idea","state_ids":{"backlog":"BACKLOG-STATE-1"}}}}}
JSON
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  echo "$cmd" | grep -qF -- "--project-id 'PROJ-UUID-1'"
  ! echo "$cmd" | grep -qF -- "--project ''"
}

@test "BTS-407 AC-5: when both project_id and project are empty, no --project flag is emitted" {
  set -e
  _with_linear_routing_neither
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  ! echo "$cmd" | grep -qE -- "--project[ -]"
}

@test "BTS-407 AC-6: project_id with shell-meta is @sh-quoted in resolved command" {
  set -e
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project_id":"uu'id","team":"Blocktech Solutions","idea_label":"idea"}}}}
JSON
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(echo "$output" | jq -r '.invocation.command')
  # @sh round-trip: uu'id  →  'uu'\''id'
  echo "$cmd" | grep -qF -- "--project-id 'uu'\\''id'"
  # Round-trip via eval to confirm the token parses back to the original string.
  eval "set -- $cmd"
  local found="false"
  while [ $# -gt 0 ]; do
    if [ "$1" = "--project-id" ]; then
      [ "$2" = "uu'id" ] && found="true"
      break
    fi
    shift
  done
  [ "$found" = "true" ]
}
