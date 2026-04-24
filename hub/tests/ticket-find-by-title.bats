#!/usr/bin/env bats
# BTS-129 — operations.sh exec ticket.find-by-title wrapper.

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

_linear_config() {
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{
  "integrations": {
    "routing": { "idea": "linear", "work": "linear" },
    "providers": {
      "linear": {
        "project": "Test Project",
        "team": "Test Team"
      }
    }
  }
}
JSON
}

# ----------------------------------------------------------------------------
# Step 1 — allowlist + basic resolve shape
# ----------------------------------------------------------------------------

@test "BTS-129: resolve ticket.find-by-title with Linear config emits list_issues invocation" {
  set -e
  _linear_config
  run bash "$OPS" resolve ticket.find-by-title "some title" --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  echo "$output" | jq -e '.mechanism == "mcp"'
  echo "$output" | jq -e '.invocation.tool == "mcp__claude_ai_Linear__list_issues"'
  echo "$output" | jq -e '.invocation.params.project == "Test Project"'
  echo "$output" | jq -e '.invocation.params.team == "Test Team"'
  echo "$output" | jq -e '.invocation.params.query == "some title"'
}

@test "BTS-129: resolve with empty title emits ERROR: canonical shape + non-zero exit" {
  _linear_config
  run --separate-stderr bash "$OPS" resolve ticket.find-by-title "" --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ ^ERROR: ]]
}

@test "BTS-129: resolve with missing title arg emits ERROR: + non-zero exit" {
  _linear_config
  run --separate-stderr bash "$OPS" resolve ticket.find-by-title --project-dir "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ ^ERROR: ]]
}

# ----------------------------------------------------------------------------
# Step 2 — client_filter emission (substring mode)
# ----------------------------------------------------------------------------

@test "BTS-129: resolve emits client_filter.mode=substring by default" {
  set -e
  _linear_config
  run bash "$OPS" resolve ticket.find-by-title "foo" --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.client_filter.mode == "substring"'
  echo "$output" | jq -e '.client_filter.jq_template | type == "string"'
  echo "$output" | jq -e '.client_filter.jq_template | contains("ascii_downcase")'
  echo "$output" | jq -e '.client_filter.jq_template | contains("contains")'
}

@test "BTS-129: client_filter template matches substring (case-insensitive) against mock Linear output" {
  set -e
  _linear_config
  # Query "assertions" matches both BTS-127 ("...assertions leak...") and
  # BTS-500 ("Some ASSERTIONS thing") regardless of case.
  run bash "$OPS" resolve ticket.find-by-title "assertions" --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local template title
  template=$(echo "$output" | jq -r '.client_filter.jq_template')
  title=$(echo "$output" | jq -r '.invocation.params.query')
  local mock='[
    {"id":"BTS-127","title":"Bats test convention: multiple jq -e assertions leak failures silently","state":{"name":"Backlog"},"status":"Backlog","url":"https://x/127"},
    {"id":"BTS-130","title":"Work identity","state":{"name":"Done"},"status":"Done","url":"https://x/130"},
    {"id":"BTS-500","title":"Some ASSERTIONS thing","state":{"name":"Backlog"},"status":"Backlog","url":"https://x/500"}
  ]'
  local matches
  matches=$(echo "$mock" | jq --arg title "$title" "$template")
  echo "$matches" | jq -e 'length == 2'
  echo "$matches" | jq -e 'any(.id == "BTS-127")'
  echo "$matches" | jq -e 'any(.id == "BTS-500")'
}

@test "BTS-129: client_filter returns empty array when no matches" {
  set -e
  _linear_config
  run bash "$OPS" resolve ticket.find-by-title "definitely no match XYZ" --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  local template title
  template=$(echo "$output" | jq -r '.client_filter.jq_template')
  title=$(echo "$output" | jq -r '.invocation.params.query')
  local mock='[{"id":"BTS-1","title":"unrelated","state":{"name":"Done"},"status":"Done","url":"u"}]'
  matches=$(echo "$mock" | jq --arg title "$title" "$template")
  echo "$matches" | jq -e 'length == 0'
}

@test "BTS-129: filter output has {id, title, status, url} shape (not the raw list_issues shape)" {
  set -e
  _linear_config
  run bash "$OPS" resolve ticket.find-by-title "foo" --project-dir "$PROJECT"
  local template title
  template=$(echo "$output" | jq -r '.client_filter.jq_template')
  title=$(echo "$output" | jq -r '.invocation.params.query')
  local mock='[{"id":"BTS-1","title":"foo bar","state":{"name":"Done"},"status":"Done","url":"u"}]'
  matches=$(echo "$mock" | jq --arg title "$title" "$template")
  echo "$matches" | jq -e '.[0].id == "BTS-1"'
  echo "$matches" | jq -e '.[0].title == "foo bar"'
  echo "$matches" | jq -e '.[0].status == "Done"'
  echo "$matches" | jq -e '.[0].url == "u"'
  # raw .state.name should NOT survive in output
  echo "$matches" | jq -e '.[0] | has("state") | not'
}

# ----------------------------------------------------------------------------
# Step 3 — --exact flag
# ----------------------------------------------------------------------------

@test "BTS-129: --exact flag sets client_filter.mode=exact" {
  set -e
  _linear_config
  run bash "$OPS" resolve ticket.find-by-title "foo" --exact --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.client_filter.mode == "exact"'
  echo "$output" | jq -e '.client_filter.jq_template | contains("ascii_downcase") | not'
}

@test "BTS-129: --exact filter matches case-sensitive equality only" {
  set -e
  _linear_config
  run bash "$OPS" resolve ticket.find-by-title "foo" --exact --project-dir "$PROJECT"
  local template title
  template=$(echo "$output" | jq -r '.client_filter.jq_template')
  title=$(echo "$output" | jq -r '.invocation.params.query')
  local mock='[
    {"id":"BTS-1","title":"foo","state":{"name":"Done"},"status":"Done","url":"u1"},
    {"id":"BTS-2","title":"Foo","state":{"name":"Done"},"status":"Done","url":"u2"},
    {"id":"BTS-3","title":"foo bar","state":{"name":"Done"},"status":"Done","url":"u3"}
  ]'
  matches=$(echo "$mock" | jq --arg title "$title" "$template")
  # Only BTS-1 matches exactly.
  echo "$matches" | jq -e 'length == 1'
  echo "$matches" | jq -e '.[0].id == "BTS-1"'
}

# ----------------------------------------------------------------------------
# Step 4 — special characters in title
# ----------------------------------------------------------------------------

@test "BTS-129: special characters in title do not break resolve" {
  set -e
  _linear_config
  run bash "$OPS" resolve ticket.find-by-title 'a & b | c $x' --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.params.query == "a & b | c $x"'
}

@test "BTS-129: special characters in title still filter correctly" {
  set -e
  _linear_config
  run bash "$OPS" resolve ticket.find-by-title 'a & b' --project-dir "$PROJECT"
  local template title
  template=$(echo "$output" | jq -r '.client_filter.jq_template')
  title=$(echo "$output" | jq -r '.invocation.params.query')
  local mock='[
    {"id":"BTS-1","title":"things: a & b happen","state":{"name":"Done"},"status":"Done","url":"u"},
    {"id":"BTS-2","title":"unrelated","state":{"name":"Done"},"status":"Done","url":"u"}
  ]'
  matches=$(echo "$mock" | jq --arg title "$title" "$template")
  echo "$matches" | jq -e 'length == 1'
  echo "$matches" | jq -e '.[0].id == "BTS-1"'
}

# ----------------------------------------------------------------------------
# Step 5 — local-provider fast path
# ----------------------------------------------------------------------------

@test "BTS-129: local-provider resolve returns empty-array fast path" {
  set -e
  # No config file → local default
  run bash "$OPS" resolve ticket.find-by-title "anything" --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
}

@test "BTS-129: local-provider exec returns []" {
  set -e
  run bash "$OPS" exec ticket.find-by-title "anything" --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == []'
}

@test "BTS-129: null-status edge case — match returned with status: null, not dropped" {
  set -e
  _linear_config
  # If both .status and .state.name are missing/null, the filter emits
  # status: null rather than dropping the match. Dedup only needs id/title —
  # losing matches over a missing status field would defeat the primitive's
  # purpose. Callers can still act on {id, title, url}.
  run bash "$OPS" resolve ticket.find-by-title "missing-status-test" --project-dir "$PROJECT"
  local template title
  template=$(echo "$output" | jq -r '.client_filter.jq_template')
  title=$(echo "$output" | jq -r '.invocation.params.query')
  local mock='[{"id":"BTS-X","title":"missing-status-test issue","url":"u"}]'
  local matches
  matches=$(echo "$mock" | jq --arg title "$title" "$template")
  echo "$matches" | jq -e 'length == 1'
  echo "$matches" | jq -e '.[0].id == "BTS-X"'
  echo "$matches" | jq -e '.[0].status == null'
}

@test "BTS-129: filter unwraps Linear MCP {issues:[...]} shape AND reads top-level .status" {
  set -e
  _linear_config
  # Real Linear MCP list_issues response is wrapped in {issues, hasNextPage}
  # and each issue has top-level .status (string), not .state.name.
  run bash "$OPS" resolve ticket.find-by-title "assertion" --project-dir "$PROJECT"
  local template title
  template=$(echo "$output" | jq -r '.client_filter.jq_template')
  title=$(echo "$output" | jq -r '.invocation.params.query')
  local mock='{
    "issues": [
      {"id":"BTS-127","title":"Bats test convention: multiple jq -e assertions leak failures silently","status":"Done","url":"https://linear.app/BTS-127"},
      {"id":"BTS-130","title":"Work identity","status":"Done","url":"https://linear.app/BTS-130"}
    ],
    "hasNextPage": false
  }'
  local matches
  matches=$(echo "$mock" | jq --arg title "$title" "$template")
  echo "$matches" | jq -e 'length == 1'
  echo "$matches" | jq -e '.[0].id == "BTS-127"'
  echo "$matches" | jq -e '.[0].status == "Done"'
  echo "$matches" | jq -e '.[0].url == "https://linear.app/BTS-127"'
}
