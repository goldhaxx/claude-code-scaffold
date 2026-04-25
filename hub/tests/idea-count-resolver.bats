#!/usr/bin/env bats
# BTS-164 Step 5 — cmd_idea_count + radar-gather become resolver-aware.
# Local-routed projects continue reading the JSONL log; Linear-routed
# projects shell out to linear-query.sh and aggregate counts by status.

bats_require_minimum_version 1.5.0

DOCS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"
STUB_FIXTURE="$BATS_TEST_DIRNAME/fixtures/linear-stub.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude" "$PROJECT/.ccanvil/scripts"
  # The resolver emits relative-path invocations like
  # `bash .ccanvil/scripts/linear-query.sh ...` — for tests where cwd
  # becomes $PROJECT (radar-gather case), the scripts need to be reachable
  # there. Real ccanvil-managed projects get these via /init's hub copy;
  # tests cp to mirror that environment. (Symlinks intentionally avoided
  # per project memory feedback_no_symlinks — they cause git-operation
  # bugs in this repo's lifecycle.)
  cp "$BATS_TEST_DIRNAME/../../.ccanvil/scripts/linear-query.sh" "$PROJECT/.ccanvil/scripts/linear-query.sh"
  unset LINEAR_API_KEY LINEAR_QUERY_ENDPOINT
}

teardown() {
  rm -rf "$PROJECT"
}

_with_local_routing() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"local":{"mechanism":"bash"}}}}
JSON
  cat > "$PROJECT/.ccanvil/ideas.log" <<'JSONL'
{"uid":"a1","created":1700000000,"status":"triage","title":"first","body":"first"}
{"uid":"a2","created":1700000001,"status":"backlog","title":"second","body":"second"}
{"uid":"a3","created":1700000002,"status":"backlog","title":"third","body":"third"}
{"uid":"a4","created":1700000003,"status":"icebox","title":"fourth","body":"fourth"}
{"uid":"a5","created":1700000004,"status":"canceled","title":"fifth","body":"fifth"}
JSONL
}

_with_linear_routing() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"P","team":"T","idea_label":"idea"}}}}
JSON
  export LINEAR_API_KEY="test-key"
  export LINEAR_QUERY_ENDPOINT="https://stub.example.test/graphql"
  export LINEAR_STUB_CAPTURE="$BATS_TEST_TMPDIR/curl-args"
  export LINEAR_STUB_RESPONSE="$BATS_TEST_TMPDIR/curl-response.json"
}

# ===========================================================================
# AC-9: local routing (existing behavior preserved under new dispatcher)
# ===========================================================================

@test "BTS-164 AC-9: idea-count-local emits counts from .ccanvil/ideas.log" {
  set -e
  _with_local_routing
  run bash "$DOCS" idea-count-local "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 5 and .triage == 1 and .backlog == 2 and .icebox == 1 and .canceled == 1'
}

@test "BTS-164 AC-9: idea-count on local-routed project equals idea-count-local" {
  set -e
  _with_local_routing
  local local_output
  local_output=$(bash "$DOCS" idea-count-local "$PROJECT")
  run bash "$DOCS" idea-count "$PROJECT"
  [ "$status" -eq 0 ]
  # Same JSON shape and same counts
  diff <(echo "$output") <(echo "$local_output")
}

@test "BTS-164 AC-9: idea-count-local with no ideas.log returns zero counts" {
  set -e
  _with_local_routing
  rm -f "$PROJECT/.ccanvil/ideas.log"
  run bash "$DOCS" idea-count-local "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 0 and .triage == 0 and .backlog == 0'
}

# ===========================================================================
# AC-5: linear routing (Linear-derived counts via stub endpoint)
# ===========================================================================

@test "BTS-164 AC-5: idea-count on linear-routed project queries Linear via wrapper" {
  set -e
  _with_linear_routing
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issues":{"nodes":[
  {"identifier":"BTS-1","title":"a","priority":1,"createdAt":"2026-04-01","updatedAt":"2026-04-01","state":{"name":"Triage","type":"triage","id":"s1"},"labels":{"nodes":[{"name":"idea"}]}},
  {"identifier":"BTS-2","title":"b","priority":2,"createdAt":"2026-04-02","updatedAt":"2026-04-02","state":{"name":"Triage","type":"triage","id":"s1"},"labels":{"nodes":[{"name":"idea"}]}},
  {"identifier":"BTS-3","title":"c","priority":3,"createdAt":"2026-04-03","updatedAt":"2026-04-03","state":{"name":"Backlog","type":"backlog","id":"s2"},"labels":{"nodes":[{"name":"idea"}]}},
  {"identifier":"BTS-4","title":"d","priority":4,"createdAt":"2026-04-04","updatedAt":"2026-04-04","state":{"name":"Icebox","type":"backlog","id":"s3"},"labels":{"nodes":[{"name":"idea"}]}},
  {"identifier":"BTS-5","title":"e","priority":0,"createdAt":"2026-04-05","updatedAt":"2026-04-05","state":{"name":"Canceled","type":"canceled","id":"s4"},"labels":{"nodes":[{"name":"idea"}]}},
  {"identifier":"BTS-6","title":"f","priority":0,"createdAt":"2026-04-06","updatedAt":"2026-04-06","state":{"name":"Duplicate","type":"canceled","id":"s5"},"labels":{"nodes":[{"name":"idea"}]}}
]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$DOCS' idea-count '$PROJECT'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 6'
  echo "$output" | jq -e '.triage == 2 and .backlog == 1 and .icebox == 1 and .canceled == 1 and .duplicate == 1'
}

@test "BTS-164 AC-5: idea-count on linear-routed project without LINEAR_API_KEY exits non-zero" {
  _with_linear_routing
  unset LINEAR_API_KEY
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && bash '$DOCS' idea-count '$PROJECT'"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "LINEAR_API_KEY" ]]
}

# ===========================================================================
# AC-6: radar-gather inherits the fix (because it calls cmd_idea_count)
# ===========================================================================

@test "BTS-164 AC-6: radar-gather on linear-routed project reports Linear-derived counts" {
  set -e
  _with_linear_routing
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issues":{"nodes":[
  {"identifier":"BTS-1","title":"a","priority":1,"createdAt":"2026-04-01","updatedAt":"2026-04-01","state":{"name":"Triage","type":"triage","id":"s1"},"labels":{"nodes":[]}},
  {"identifier":"BTS-2","title":"b","priority":1,"createdAt":"2026-04-01","updatedAt":"2026-04-01","state":{"name":"Triage","type":"triage","id":"s1"},"labels":{"nodes":[]}},
  {"identifier":"BTS-3","title":"c","priority":1,"createdAt":"2026-04-01","updatedAt":"2026-04-01","state":{"name":"Backlog","type":"backlog","id":"s2"},"labels":{"nodes":[]}}
]}}}
JSON
  run bash -c "cd '$PROJECT' && source '$STUB_FIXTURE' && bash '$DOCS' radar-gather"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ideas.triage == 2 and .ideas.backlog == 1 and .ideas.total == 3'
}
