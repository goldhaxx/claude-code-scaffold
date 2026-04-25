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
