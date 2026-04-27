#!/usr/bin/env bats
# BTS-204 — drift-guards for SSOT-Linear: routing of spec/plan/stasis to Linear Documents
# (vs Issue.description) via provider-driven configuration. Local-routed nodes preserve
# file-based flow unchanged.

bats_require_minimum_version 1.5.0

LQ="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/linear-query.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  unset LINEAR_API_KEY
  unset LINEAR_QUERY_ENDPOINT
}

# =========================================================================
# AC-4 / Step 1: resolve-document-id — deterministic UUID derivation
# =========================================================================

@test "BTS-204 Step 1: resolve-document-id returns a valid UUID-format string" {
  run bash "$LQ" resolve-document-id --kind spec --ticket BTS-204
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "BTS-204 Step 1: resolve-document-id is deterministic across invocations" {
  run bash "$LQ" resolve-document-id --kind spec --ticket BTS-204
  first="$output"
  run bash "$LQ" resolve-document-id --kind spec --ticket BTS-204
  [ "$output" = "$first" ]
}

@test "BTS-204 Step 1: resolve-document-id differs per kind for same ticket" {
  run bash "$LQ" resolve-document-id --kind spec --ticket BTS-204
  spec_id="$output"
  run bash "$LQ" resolve-document-id --kind plan --ticket BTS-204
  plan_id="$output"
  [ "$spec_id" != "$plan_id" ]
}

@test "BTS-204 Step 1: resolve-document-id differs per ticket for same kind" {
  run bash "$LQ" resolve-document-id --kind spec --ticket BTS-204
  a="$output"
  run bash "$LQ" resolve-document-id --kind spec --ticket BTS-205
  b="$output"
  [ "$a" != "$b" ]
}

@test "BTS-204 Step 1: resolve-document-id accepts all four kinds" {
  for kind in spec plan feature-stasis session-stasis; do
    run bash "$LQ" resolve-document-id --kind "$kind" --ticket BTS-204
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
  done
}

@test "BTS-204 Step 1: resolve-document-id rejects unknown kind with exit 2" {
  run --separate-stderr bash "$LQ" resolve-document-id --kind bogus --ticket BTS-204
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "Unknown kind" ]] || [[ "$stderr" =~ "kind" ]]
}

@test "BTS-204 Step 1: resolve-document-id requires --kind and --ticket" {
  run --separate-stderr bash "$LQ" resolve-document-id --kind spec
  [ "$status" -eq 2 ]
  run --separate-stderr bash "$LQ" resolve-document-id --ticket BTS-204
  [ "$status" -eq 2 ]
}

# =========================================================================
# Step 2: get-document — read by id-or-slug
# =========================================================================

_setup_stub() {
  STUB_FIXTURE="$BATS_TEST_DIRNAME/fixtures/linear-stub.sh"
  export LINEAR_STUB_CAPTURE="$BATS_TEST_TMPDIR/curl-args"
  export LINEAR_STUB_RESPONSE="$BATS_TEST_TMPDIR/curl-response.json"
  export LINEAR_API_KEY="test-key-abc123"
  export LINEAR_QUERY_ENDPOINT="https://stub.example.test/graphql"
}

_get_body() {
  awk '/<<BODY>>/{flag=1;next} flag' "$LINEAR_STUB_CAPTURE"
}

@test "BTS-204 Step 2: get-document parses canonical shape from stub" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"document":{
  "id":"5b8e4a8e-4f3c-4d2a-9c1e-bf204550b91d",
  "title":"Spec: BTS-204",
  "content":"# spec body\n",
  "slugId":"spec-bts-204",
  "url":"https://linear.app/team/document/spec-bts-204",
  "updatedAt":"2026-04-26T20:00:00.000Z",
  "createdAt":"2026-04-26T19:00:00.000Z",
  "updatedBy":{"id":"user-1","name":"Test"},
  "creator":{"id":"user-1","name":"Test"},
  "project":{"id":"proj-1"},
  "issue":{"id":"issue-1","identifier":"BTS-204"}
}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' get-document 5b8e4a8e-4f3c-4d2a-9c1e-bf204550b91d"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "5b8e4a8e-4f3c-4d2a-9c1e-bf204550b91d"'
  echo "$output" | jq -e '.title == "Spec: BTS-204"'
  echo "$output" | jq -e '.content == "# spec body\n"'
  echo "$output" | jq -e '.updatedAt == "2026-04-26T20:00:00.000Z"'
  echo "$output" | jq -e '.updatedBy.id == "user-1"'
  echo "$output" | jq -e '.issue.identifier == "BTS-204"'
}

@test "BTS-204 Step 2: get-document GraphQL body uses document(id:) query" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"document":{"id":"x","title":"t","content":"c","slugId":"s","url":"u","updatedAt":"2026-04-26T20:00:00.000Z","createdAt":"2026-04-26T19:00:00.000Z","updatedBy":null,"creator":null,"project":null,"issue":null}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' get-document spec-bts-204"
  [ "$status" -eq 0 ]
  body=$(_get_body)
  echo "$body" | jq -e '.query | test("document\\(id:")'
  echo "$body" | jq -e '.variables.id == "spec-bts-204"'
}

@test "BTS-204 Step 2: get-document requires an id arg" {
  run --separate-stderr bash "$LQ" get-document
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "id" ]]
}

@test "BTS-204 Step 2: get-document surfaces GraphQL errors as exit 3" {
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"errors":[{"message":"Document not found"}]}
JSON
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && bash '$LQ' get-document missing-id"
  [ "$status" -eq 3 ]
  [[ "$stderr" =~ "Document not found" ]]
}

# =========================================================================
# Step 3: save-document — create (no id) or update (id) via --input-json -
# =========================================================================

@test "BTS-204 Step 3: save-document without id triggers documentCreate mutation" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documentCreate":{"success":true,"document":{
  "id":"new-uuid","title":"Spec: BTS-204","content":"body","updatedAt":"2026-04-26T20:00:00.000Z"
}}}}
JSON
  body_json='{"title":"Spec: BTS-204","content":"body","issueId":"issue-1"}'
  run bash -c "source '$STUB_FIXTURE' && echo '$body_json' | bash '$LQ' save-document --input-json -"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "new-uuid"'
  echo "$output" | jq -e '.title == "Spec: BTS-204"'
  echo "$output" | jq -e '.updatedAt == "2026-04-26T20:00:00.000Z"'
  body=$(_get_body)
  echo "$body" | jq -e '.query | test("documentCreate")'
  echo "$body" | jq -e '.variables.input.title == "Spec: BTS-204"'
  echo "$body" | jq -e '.variables.input.issueId == "issue-1"'
}

@test "BTS-204 Step 3: save-document with id triggers documentUpdate mutation" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documentUpdate":{"success":true,"document":{
  "id":"existing-uuid","title":"Spec: BTS-204","content":"updated","updatedAt":"2026-04-26T21:00:00.000Z"
}}}}
JSON
  body_json='{"id":"existing-uuid","content":"updated"}'
  run bash -c "source '$STUB_FIXTURE' && echo '$body_json' | bash '$LQ' save-document --input-json -"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "existing-uuid"'
  echo "$output" | jq -e '.updatedAt == "2026-04-26T21:00:00.000Z"'
  body=$(_get_body)
  echo "$body" | jq -e '.query | test("documentUpdate")'
  echo "$body" | jq -e '.variables.id == "existing-uuid"'
  echo "$body" | jq -e '.variables.input.content == "updated"'
  # update input must NOT carry the id field (it's a path arg, not input field)
  echo "$body" | jq -e '.variables.input.id == null'
}

@test "BTS-204 Step 3: save-document --content flag layers on top of stdin" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documentCreate":{"success":true,"document":{"id":"x","title":"t","content":"c","updatedAt":"now"}}}}
JSON
  body_json='{"title":"t","content":"old","issueId":"i"}'
  run bash -c "source '$STUB_FIXTURE' && echo '$body_json' | bash '$LQ' save-document --input-json - --content 'flag-wins'"
  [ "$status" -eq 0 ]
  body=$(_get_body)
  echo "$body" | jq -e '.variables.input.content == "flag-wins"'
}

@test "BTS-204 Step 3: save-document create requires title" {
  _setup_stub
  body_json='{"content":"orphan"}'
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && echo '$body_json' | bash '$LQ' save-document --input-json -"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "title" ]]
}

@test "BTS-204 Step 3: save-document create requires a parent (issueId or projectId)" {
  _setup_stub
  body_json='{"title":"orphan","content":"x"}'
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && echo '$body_json' | bash '$LQ' save-document --input-json -"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "parent" ]]
}

@test "BTS-204 Step 3: save-document surfaces GraphQL errors as exit 3" {
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"errors":[{"message":"Document parent not found"}]}
JSON
  body_json='{"title":"t","content":"c","issueId":"missing"}'
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && echo '$body_json' | bash '$LQ' save-document --input-json -"
  [ "$status" -eq 3 ]
  [[ "$stderr" =~ "parent not found" ]]
}

# =========================================================================
# Step 4: document-updated-at — cheap projection for concurrent-edit checks
# =========================================================================

@test "BTS-204 Step 4: document-updated-at returns minimal projection" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"document":{"id":"x","updatedAt":"2026-04-26T20:00:00.000Z","updatedBy":{"id":"u1","name":"alice"}}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' document-updated-at x"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "x"'
  echo "$output" | jq -e '.updatedAt == "2026-04-26T20:00:00.000Z"'
  echo "$output" | jq -e '.updatedBy.id == "u1"'
}

@test "BTS-204 Step 4: document-updated-at GraphQL projection is minimal" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"document":{"id":"x","updatedAt":"now","updatedBy":null}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' document-updated-at x"
  [ "$status" -eq 0 ]
  body=$(_get_body)
  # Verify the projection requests ONLY id, updatedAt, updatedBy — not content/title/etc
  echo "$body" | jq -re '.query' | grep -v -E 'content|title|slugId|url|createdAt|creator|project|issue' >/dev/null
}

@test "BTS-204 Step 4: document-updated-at requires id arg" {
  run --separate-stderr bash "$LQ" document-updated-at
  [ "$status" -eq 2 ]
}
