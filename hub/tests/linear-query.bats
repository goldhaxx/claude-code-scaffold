#!/usr/bin/env bats
# BTS-164 — linear-query.sh: Linear GraphQL client wrapper for bash scripts.
# Provides curl + jq + LINEAR_API_KEY env-var auth so docs-check.sh, radar-gather,
# operations.sh resolvers, etc. can read+write Linear without going through MCP.

bats_require_minimum_version 1.5.0

LQ="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/linear-query.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  # Ensure tests start with a clean env — no leaked LINEAR_API_KEY from operator shell.
  unset LINEAR_API_KEY
  unset LINEAR_QUERY_ENDPOINT
}

# ===========================================================================
# AC-1, AC-2: skeleton + auth gate
# ===========================================================================

@test "BTS-164 AC-1: --help exits 0 with usage text" {
  run bash "$LQ" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  [[ "$output" =~ "linear-query.sh" ]]
}

@test "BTS-164 AC-1: bare invocation (no subcommand) exits 2 with usage to stderr" {
  run --separate-stderr bash "$LQ"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "Usage:" ]]
}

@test "BTS-164 AC-1: unknown subcommand exits 2 with error to stderr" {
  run --separate-stderr bash "$LQ" not-a-real-subcommand
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "Unknown subcommand" ]]
}

@test "BTS-164 AC-2: list-issues without LINEAR_API_KEY exits 2 with clear message" {
  # cd into tmpdir so BTS-167's $PWD-anchored auto-source can't reach a real
  # .env up the tree (e.g., the operator's repo when running locally).
  run --separate-stderr bash -c "cd '$BATS_TEST_TMPDIR' && bash '$LQ' list-issues"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "LINEAR_API_KEY not set" ]]
}

@test "BTS-164 AC-2: viewer without LINEAR_API_KEY exits 2 with clear message" {
  run --separate-stderr bash -c "cd '$BATS_TEST_TMPDIR' && bash '$LQ' viewer"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "LINEAR_API_KEY not set" ]]
}

@test "BTS-164 AC-2: --help bypasses LINEAR_API_KEY check" {
  # Even with no key set, --help must succeed so operators can discover the tool.
  unset LINEAR_API_KEY
  run bash "$LQ" --help
  [ "$status" -eq 0 ]
}

# ===========================================================================
# AC-3: curl transport + viewer subcommand (auth smoke test)
# ===========================================================================
#
# The stub fixture (hub/tests/fixtures/linear-stub.sh) shadows curl with a
# bash function exported into the subshell. Side-channel env vars:
#   LINEAR_STUB_CAPTURE   path to capture raw curl args (one per line)
#   LINEAR_STUB_RESPONSE  path containing the JSON the stub will echo
#
# Tests stage a response file, run the subcommand, then grep the capture file
# for headers, URL, and body.

_setup_stub() {
  STUB_FIXTURE="$BATS_TEST_DIRNAME/fixtures/linear-stub.sh"
  export LINEAR_STUB_CAPTURE="$BATS_TEST_TMPDIR/curl-args"
  export LINEAR_STUB_RESPONSE="$BATS_TEST_TMPDIR/curl-response.json"
  export LINEAR_API_KEY="test-key-abc123"
  export LINEAR_QUERY_ENDPOINT="https://stub.example.test/graphql"
}

@test "BTS-164 AC-3: viewer returns parsed identity from stub response" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"viewer":{"id":"user-123","name":"Test User"}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "user-123" and .name == "Test User"'
}

@test "BTS-164 AC-3: viewer sends Authorization header with LINEAR_API_KEY value" {
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"viewer":{"id":"u","name":"n"}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  grep -F "Authorization: test-key-abc123" "$LINEAR_STUB_CAPTURE"
}

@test "BTS-164 AC-3: viewer POSTs to LINEAR_QUERY_ENDPOINT (stub override honored)" {
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"viewer":{"id":"u","name":"n"}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  grep -F "https://stub.example.test/graphql" "$LINEAR_STUB_CAPTURE"
}

@test "BTS-164 AC-3: viewer body contains the viewer GraphQL query" {
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"viewer":{"id":"u","name":"n"}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  # Body line in capture file should contain the viewer GraphQL query.
  grep -F "viewer" "$LINEAR_STUB_CAPTURE"
}

@test "BTS-164 AC-3: viewer surfaces GraphQL errors as exit 3" {
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"errors":[{"message":"Invalid API key"}]}
JSON
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 3 ]
  [[ "$stderr" =~ "Invalid API key" ]]
}

# ===========================================================================
# AC-1, AC-8: read subcommands (list-issues, get-issue, list-states, list-labels)
# ===========================================================================

# Helper: extract the body sent to curl (after the <<BODY>> sentinel).
_get_body() {
  awk '/<<BODY>>/{flag=1;next} flag' "$LINEAR_STUB_CAPTURE"
}

@test "BTS-164 AC-1: list-issues parses .issues.nodes into canonical shape" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issues":{"nodes":[
  {"id":"u1","identifier":"BTS-100","title":"first","priority":2,"createdAt":"2026-04-25","state":{"name":"Triage","type":"triage","id":"s1"},"labels":{"nodes":[{"name":"idea"}]}},
  {"id":"u2","identifier":"BTS-101","title":"second","priority":3,"createdAt":"2026-04-26","state":{"name":"Backlog","type":"backlog","id":"s2"},"labels":{"nodes":[]}}
]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-issues"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].id == "BTS-100" and .[0].status == "Triage" and .[0].statusType == "triage"'
  echo "$output" | jq -e '.[0].labels == ["idea"]'
}

@test "BTS-164 AC-1: list-issues --state triage --label idea --project P --team T builds combined filter" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issues":{"nodes":[]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-issues --state triage --label idea --project P --team T"
  [ "$status" -eq 0 ]
  local body
  body=$(_get_body)
  echo "$body" | jq -e '.variables.filter.state.type.eq == "triage"'
  echo "$body" | jq -e '.variables.filter.labels.some.name.eq == "idea"'
  echo "$body" | jq -e '.variables.filter.project.name.eq == "P"'
  echo "$body" | jq -e '.variables.filter.team.name.eq == "T"'
}

@test "BTS-164 AC-1: list-issues --limit overrides default first" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issues":{"nodes":[]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-issues --limit 10"
  [ "$status" -eq 0 ]
  _get_body | jq -e '.variables.first == 10'
}

@test "BTS-164 AC-1: list-issues unknown flag exits 2" {
  _setup_stub
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-issues --bogus x"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "unknown flag" ]]
}

@test "BTS-164 AC-1: get-issue requires identifier arg" {
  _setup_stub
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && bash '$LQ' get-issue"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "requires" ]]
}

@test "BTS-164 AC-1: get-issue BTS-100 sends issue(id) query and parses response" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issue":{"id":"u1","identifier":"BTS-100","title":"first","priority":2,"createdAt":"2026-04-25","state":{"name":"Triage","type":"triage","id":"s1"},"labels":{"nodes":[{"name":"idea"}]}}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' get-issue BTS-100"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "BTS-100" and .title == "first" and .status == "Triage"'
  _get_body | jq -e '.variables.id == "BTS-100"'
}

@test "BTS-164 AC-1: list-states --team T sends workflowStates query and parses nodes" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"workflowStates":{"nodes":[
  {"id":"s1","name":"Triage","type":"triage"},
  {"id":"s2","name":"Backlog","type":"backlog"}
]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-states --team T"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].id == "s1" and .[0].name == "Triage" and .[0].type == "triage"'
  _get_body | jq -e '.variables.filter.team.name.eq == "T"'
}

@test "BTS-166 AC-2: list-teams sends teams query and parses nodes" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"teams":{"nodes":[
  {"id":"t1","name":"Blocktech Solutions","key":"BTS"},
  {"id":"t2","name":"Other Team","key":"OTH"}
]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-teams"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].id == "t1" and .[0].name == "Blocktech Solutions"'
  _get_body | jq -e '.query | contains("teams")'
}

@test "BTS-166 AC-2: list-teams --name <NAME> filters by team name" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"teams":{"nodes":[{"id":"t1","name":"Blocktech Solutions","key":"BTS"}]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-teams --name 'Blocktech Solutions'"
  [ "$status" -eq 0 ]
  _get_body | jq -e '.variables.filter.name.eq == "Blocktech Solutions"'
}

@test "BTS-166 AC-2: list-projects sends projects query and parses nodes" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"projects":{"nodes":[
  {"id":"p1","name":"ccanvil","slugId":"ccanvil"},
  {"id":"p2","name":"other","slugId":"other"}
]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-projects"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].id == "p1" and .[0].name == "ccanvil"'
  _get_body | jq -e '.query | contains("projects")'
}

@test "BTS-166 AC-2: list-projects --name <NAME> filters by project name" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"projects":{"nodes":[{"id":"p1","name":"ccanvil","slugId":"ccanvil"}]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-projects --name ccanvil"
  [ "$status" -eq 0 ]
  _get_body | jq -e '.variables.filter.name.eq == "ccanvil"'
}

@test "BTS-164 AC-1: list-labels --team T sends issueLabels query and parses nodes" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueLabels":{"nodes":[
  {"id":"l1","name":"idea"},
  {"id":"l2","name":"scaffold"}
]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-labels --team T"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].name == "idea"'
  _get_body | jq -e '.variables.filter.team.name.eq == "T"'
}

# ===========================================================================
# AC-7: save-issue (write mutations)
# ===========================================================================
# v1 takes IDs directly (--team-id, --project-id, --state, --label-ids). Name
# resolution is the resolver's job in Step 7 — config carries team_id, project_id,
# state_ids, etc., so the resolver pre-resolves and the wrapper stays focused
# on transport. Mode selector: presence of --id triggers update; absence triggers
# create.

@test "BTS-164 AC-7: save-issue create (no --id) sends issueCreate mutation" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueCreate":{"success":true,"issue":{"id":"u1","identifier":"BTS-200","title":"new"}}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --team-id team-uuid --project-id proj-uuid --title 'new' --description 'body'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "BTS-200"'
  local body
  body=$(_get_body)
  echo "$body" | jq -e '.query | contains("issueCreate")'
  echo "$body" | jq -e '.variables.input.teamId == "team-uuid"'
  echo "$body" | jq -e '.variables.input.projectId == "proj-uuid"'
  echo "$body" | jq -e '.variables.input.title == "new"'
}

@test "BTS-164 AC-7: save-issue --id <ID> --state <STATE_ID> sends issueUpdate (transition)" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueUpdate":{"success":true,"issue":{"id":"u1","identifier":"BTS-100","title":"t"}}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --id BTS-100 --state state-uuid-done"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "BTS-100"'
  local body
  body=$(_get_body)
  echo "$body" | jq -e '.query | contains("issueUpdate")'
  echo "$body" | jq -e '.variables.id == "BTS-100"'
  echo "$body" | jq -e '.variables.input.stateId == "state-uuid-done"'
}

@test "BTS-164 AC-7: save-issue --id <ID> --priority <N> sends issueUpdate" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueUpdate":{"success":true,"issue":{"id":"u1","identifier":"BTS-100","title":"t"}}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --id BTS-100 --priority 2"
  [ "$status" -eq 0 ]
  local body
  body=$(_get_body)
  echo "$body" | jq -e '.variables.input.priority == 2'
}

@test "BTS-164 AC-7: save-issue --id <ID> --label-ids l1,l2 sends issueUpdate with label array" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueUpdate":{"success":true,"issue":{"id":"u1","identifier":"BTS-100","title":"t"}}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --id BTS-100 --label-ids l1,l2"
  [ "$status" -eq 0 ]
  local body
  body=$(_get_body)
  echo "$body" | jq -e '.variables.input.labelIds == ["l1", "l2"]'
}

@test "BTS-164 AC-7: save-issue create requires --title (and --team-id)" {
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{}}
JSON
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --description 'no title'"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "title" ]] || [[ "$stderr" =~ "team" ]]
}

@test "BTS-164 AC-7: save-issue surfaces GraphQL errors as exit 3" {
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"errors":[{"message":"Field is required: title"}]}
JSON
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --id BTS-100 --priority 1"
  [ "$status" -eq 3 ]
  [[ "$stderr" =~ "Field is required" ]]
}

# ===========================================================================
# BTS-166 AC-2: name-based create flags --team / --project / --labels
# ===========================================================================
# When --team / --project / --labels are passed without their -id counterparts,
# save-issue does a one-shot lookup via the teams / projects / issueLabels
# queries and substitutes the resolved IDs. -id flags take precedence on collision.

@test "BTS-166 AC-2: save-issue --team NAME resolves NAME→teamId via list-teams query" {
  set -e
  _setup_stub
  # Sequence-aware stub: each curl invocation reads the next response file,
  # tracked via a counter file in TMPDIR. This lets us serve the team-lookup
  # response then the issueCreate response from a single test.
  local responses_dir="$BATS_TEST_TMPDIR/seq"
  mkdir -p "$responses_dir"
  cat > "$responses_dir/1.json" <<'JSON'
{"data":{"teams":{"nodes":[{"id":"team-uuid","name":"Blocktech Solutions","key":"BTS"}]}}}
JSON
  cat > "$responses_dir/2.json" <<'JSON'
{"data":{"issueCreate":{"success":true,"issue":{"id":"u","identifier":"BTS-300","title":"t"}}}}
JSON
  # Counter file persists across exported-function calls (linear-query.sh
  # invokes curl multiple times in a single bash subprocess).
  local counter="$BATS_TEST_TMPDIR/seq.count"
  echo 0 > "$counter"
  # Override LINEAR_STUB_RESPONSE per-call by writing a wrapper that updates
  # the symlink/path before invoking the real stub's curl. Easier: bypass the
  # stub fixture entirely with a stand-alone curl override.
  cat > "$BATS_TEST_TMPDIR/seq-stub.sh" <<EOF
curl() {
  local n
  n=\$(cat '$counter')
  n=\$((n + 1))
  echo "\$n" > '$counter'
  cat '$responses_dir/'"\$n"'.json'
  local body=""
  while [ \$# -gt 0 ]; do
    case "\$1" in
      --data|--data-raw|-d) body="\$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  printf 'BODY:%s\n' "\$body" >> "\$LINEAR_STUB_CAPTURE"
}
export -f curl
EOF
  run bash -c "source '$BATS_TEST_TMPDIR/seq-stub.sh' && bash '$LQ' save-issue --team 'Blocktech Solutions' --project-id proj-uuid --title 'new' --description 'body'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "BTS-300"'
  # The LAST captured BODY is the issueCreate; assert teamId resolved correctly.
  local last_body
  last_body=$(grep '^BODY:' "$LINEAR_STUB_CAPTURE" | tail -1 | sed 's/^BODY://')
  echo "$last_body" | jq -e '.variables.input.teamId == "team-uuid"'
}

@test "BTS-166 AC-2: save-issue --team-id wins when both --team and --team-id are passed" {
  set -e
  _setup_stub
  # Only one curl call (no lookup needed) since --team-id short-circuits.
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueCreate":{"success":true,"issue":{"id":"u","identifier":"BTS-301","title":"t"}}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --team 'Some Other Team' --team-id explicit-uuid --project-id p --title 'new' --description 'body'"
  [ "$status" -eq 0 ]
  local body
  body=$(_get_body)
  echo "$body" | jq -e '.variables.input.teamId == "explicit-uuid"'
}

# ===========================================================================
# BTS-166 AC-1: --input-json -  reads JSON from stdin and merges into input
# ===========================================================================
# The stdin-JSON path lets callers supply dynamic content (title, description)
# without shell-quoting friction. CLI flags take precedence on key collision.

@test "BTS-166 AC-1: save-issue --input-json - reads stdin JSON into input" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueCreate":{"success":true,"issue":{"id":"u1","identifier":"BTS-201","title":"from-stdin"}}}}
JSON
  local stdin_json='{"title":"from-stdin","description":"body via stdin"}'
  run bash -c "source '$STUB_FIXTURE' && echo '$stdin_json' | bash '$LQ' save-issue --team-id team-uuid --project-id proj-uuid --input-json -"
  [ "$status" -eq 0 ]
  local body
  body=$(_get_body)
  echo "$body" | jq -e '.variables.input.title == "from-stdin"'
  echo "$body" | jq -e '.variables.input.description == "body via stdin"'
  echo "$body" | jq -e '.variables.input.teamId == "team-uuid"'
}

@test "BTS-166 AC-1: CLI flags override stdin-JSON fields on collision" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueCreate":{"success":true,"issue":{"id":"u1","identifier":"BTS-202","title":"cli-wins"}}}}
JSON
  # stdin says title=stdin-title, but --title cli-wins on the command line should win.
  local stdin_json='{"title":"stdin-title","description":"shared body"}'
  run bash -c "source '$STUB_FIXTURE' && echo '$stdin_json' | bash '$LQ' save-issue --team-id t --project-id p --title cli-wins --input-json -"
  [ "$status" -eq 0 ]
  local body
  body=$(_get_body)
  echo "$body" | jq -e '.variables.input.title == "cli-wins"'
  echo "$body" | jq -e '.variables.input.description == "shared body"'
}

# ===========================================================================
# BTS-166 AC-3: stdin-JSON preserves special characters verbatim
# ===========================================================================
# Newlines, double-quotes, single-quotes, backticks, $VAR, $(cmd) all
# need to round-trip without shell re-interpretation. jq -n owns the
# escaping; the wrapper must NOT interpolate the value through bash.

@test "BTS-166 AC-3: stdin-JSON preserves newlines, quotes, backticks, dollar-substitution" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueCreate":{"success":true,"issue":{"id":"u1","identifier":"BTS-203","title":"t"}}}}
JSON
  # Build the fixture via jq so escaping is deterministic. Description has:
  #  - embedded newline
  #  - double-quote
  #  - single-quote
  #  - backtick
  #  - literal $VAR (no expansion expected)
  #  - literal $(cmd) (no expansion expected)
  local stdin_json
  stdin_json=$(jq -n --arg desc "line1
line2 \"dq\" 'sq' \`bt\` \$VAR \$(cmd)" '{title:"t", description:$desc}')
  # Pipe via tmpfile so the shell layer doesn't see the metacharacters.
  local fixture="$BATS_TEST_TMPDIR/stdin.json"
  printf '%s' "$stdin_json" > "$fixture"
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --team-id t --project-id p --input-json - < '$fixture'"
  [ "$status" -eq 0 ]
  local body
  body=$(_get_body)
  # Round-trip: the description in the request body must equal the description in the input fixture.
  local input_desc body_desc
  input_desc=$(jq -r '.description' "$fixture")
  body_desc=$(echo "$body" | jq -r '.variables.input.description')
  [ "$input_desc" = "$body_desc" ]
}

# ===========================================================================
# BTS-166 AC-12: 6-byte UTF-8 emoji + triple-backtick markdown fence round-trip
# ===========================================================================

@test "BTS-166 AC-12: stdin-JSON preserves 6-byte UTF-8 sequence and triple-backtick fence" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"issueCreate":{"success":true,"issue":{"id":"u1","identifier":"BTS-204","title":"t"}}}}
JSON
  # 🚀 (U+1F680) is a 4-byte UTF-8 sequence; pair with another emoji for >6 bytes total.
  # Triple backticks for markdown-fence preservation.
  local stdin_json
  stdin_json=$(jq -n --arg desc 'before 🚀✨ after
\`\`\`bash
echo hi
\`\`\`' '{title:"t", description:$desc}')
  local fixture="$BATS_TEST_TMPDIR/stdin.json"
  printf '%s' "$stdin_json" > "$fixture"
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' save-issue --team-id t --project-id p --input-json - < '$fixture'"
  [ "$status" -eq 0 ]
  local body
  body=$(_get_body)
  local input_desc body_desc
  input_desc=$(jq -r '.description' "$fixture")
  body_desc=$(echo "$body" | jq -r '.variables.input.description')
  [ "$input_desc" = "$body_desc" ]
}
