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

# =========================================================================
# Step 5a: trash-document — soft delete via documentDelete
# =========================================================================

@test "BTS-204 Step 5a: trash-document calls documentDelete and returns success" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documentDelete":{"success":true}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' trash-document doc-id-1"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true'
  body=$(_get_body)
  echo "$body" | jq -e '.query | test("documentDelete")'
  echo "$body" | jq -e '.variables.id == "doc-id-1"'
}

@test "BTS-204 Step 5a: trash-document requires id" {
  run --separate-stderr bash "$LQ" trash-document
  [ "$status" -eq 2 ]
}

# =========================================================================
# Step 5b: list-documents — filter by --project, --issue, --initiative
# =========================================================================

@test "BTS-204 Step 5b: list-documents returns canonical array shape" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documents":{"nodes":[
  {"id":"d1","title":"Spec: BTS-204","slugId":"spec-204","updatedAt":"t1","createdAt":"t0"},
  {"id":"d2","title":"Plan: BTS-204","slugId":"plan-204","updatedAt":"t2","createdAt":"t0"}
]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-documents"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].id == "d1" and .[0].title == "Spec: BTS-204"'
}

@test "BTS-204 Step 5b: list-documents --project filters by project" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documents":{"nodes":[]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-documents --project proj-1"
  [ "$status" -eq 0 ]
  body=$(_get_body)
  echo "$body" | jq -e '.variables.filter.project.id.eq == "proj-1"'
}

@test "BTS-204 Step 5b: list-documents --issue filters by issue" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documents":{"nodes":[]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-documents --issue issue-1"
  [ "$status" -eq 0 ]
  body=$(_get_body)
  echo "$body" | jq -e '.variables.filter.issue.id.eq == "issue-1"'
}

@test "BTS-204 Step 5b: list-documents --limit overrides default first" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documents":{"nodes":[]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' list-documents --limit 5"
  [ "$status" -eq 0 ]
  body=$(_get_body)
  echo "$body" | jq -e '.variables.first == 5'
}

# =========================================================================
# Step 5c: document-history — content version snapshots
# =========================================================================

@test "BTS-204 Step 5c: document-history returns canonical array shape" {
  set -e
  _setup_stub
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"documentContentHistory":{"history":[
  {"id":"h1","contentDataSnapshotAt":"2026-04-26T20:00:00.000Z","actorIds":["u1"]},
  {"id":"h2","contentDataSnapshotAt":"2026-04-26T19:00:00.000Z","actorIds":[]}
]}}}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$LQ' document-history doc-1"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '.[0].id == "h1"'
  echo "$output" | jq -e '.[0].snapshotAt == "2026-04-26T20:00:00.000Z"'
  echo "$output" | jq -e '.[0].actorIds == ["u1"]'
}

@test "BTS-204 Step 5c: document-history requires id" {
  run --separate-stderr bash "$LQ" document-history
  [ "$status" -eq 2 ]
}

# =========================================================================
# Step 6+7: operations.sh routing for spec/plan/stasis
# =========================================================================

OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

_make_local_fx() {
  local fx="$BATS_TEST_TMPDIR/local-fx"
  mkdir -p "$fx/.claude"
  echo '{}' > "$fx/.claude/ccanvil.json"
  echo "$fx"
}

_make_linear_fx() {
  local fx="$BATS_TEST_TMPDIR/linear-fx"
  mkdir -p "$fx/.claude"
  cat > "$fx/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {
      "linear": {
        "mechanism": "http",
        "project": "ccanvil",
        "project_id": "test-project-uuid",
        "team": "Test Team",
        "state_ids": {"backlog":"backlog-state-id"}
      }
    }
  }
}
JSON
  cat > "$fx/.claude/ccanvil.local.json" <<'JSON'
{
  "integrations": {
    "routing": {
      "spec": "linear",
      "plan": "linear",
      "stasis": "linear"
    }
  }
}
JSON
  echo "$fx"
}

@test "BTS-204 Step 6: spec.read on local-routed node returns bash mechanism (unchanged)" {
  fx=$(_make_local_fx)
  run bash "$OPS" resolve spec.read --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "local"'
  echo "$output" | jq -e '.mechanism == "bash"'
  echo "$output" | jq -e '.invocation.command == "cat docs/spec.md"'
}

@test "BTS-204 Step 7: spec.read on linear-routed node returns http get-document" {
  fx=$(_make_linear_fx)
  run bash "$OPS" resolve spec.read BTS-204 --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.provider == "linear"'
  echo "$output" | jq -e '.mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | test("linear-query.sh get-document")'
  # The doc id is derived deterministically from --kind spec --ticket BTS-204
  expected_uuid=$(bash "$LQ" resolve-document-id --kind spec --ticket BTS-204)
  echo "$output" | jq -e --arg u "$expected_uuid" '.invocation.command | contains($u)'
}

@test "BTS-204 Step 7: spec.write on linear-routed node returns http save-document" {
  fx=$(_make_linear_fx)
  run bash "$OPS" resolve spec.write BTS-204 --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mechanism == "http"'
  echo "$output" | jq -e '.invocation.command | test("linear-query.sh save-document")'
  echo "$output" | jq -e '.invocation.command | test("--input-json -")'
}

@test "BTS-204 Step 7: plan.read/write linear-routed dispatch" {
  fx=$(_make_linear_fx)
  for verb in plan.read plan.write; do
    run bash "$OPS" resolve "$verb" BTS-204 --project-dir "$fx"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.mechanism == "http"'
  done
  expected_uuid=$(bash "$LQ" resolve-document-id --kind plan --ticket BTS-204)
  run bash "$OPS" resolve plan.read BTS-204 --project-dir "$fx"
  echo "$output" | jq -e --arg u "$expected_uuid" '.invocation.command | contains($u)'
}

@test "BTS-204 Step 7: stasis.read feature kind → issue-parented Document" {
  fx=$(_make_linear_fx)
  run bash "$OPS" resolve stasis.read feature BTS-204 --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mechanism == "http"'
  expected_uuid=$(bash "$LQ" resolve-document-id --kind feature-stasis --ticket BTS-204)
  echo "$output" | jq -e --arg u "$expected_uuid" '.invocation.command | contains($u)'
}

@test "BTS-204 Step 7: stasis.read session kind → project-parented Document" {
  fx=$(_make_linear_fx)
  run bash "$OPS" resolve stasis.read session --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mechanism == "http"'
  expected_uuid=$(bash "$LQ" resolve-document-id --kind session-stasis --ticket test-project-uuid)
  echo "$output" | jq -e --arg u "$expected_uuid" '.invocation.command | contains($u)'
}

@test "BTS-204 Step 7: stasis.write feature on linear → save-document with --issue-id" {
  fx=$(_make_linear_fx)
  run bash "$OPS" resolve stasis.write feature BTS-204 --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | test("save-document")'
  # The skill will pipe input-json with title + content + issueId. The resolver
  # surfaces the parent kind via the contract so the skill knows which to set.
  echo "$output" | jq -e '.contract.parent_kind == "issue"'
}

@test "BTS-204 Step 7: stasis.write session on linear → save-document with --project-id" {
  fx=$(_make_linear_fx)
  run bash "$OPS" resolve stasis.write session --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | test("save-document")'
  echo "$output" | jq -e '.contract.parent_kind == "project"'
}

@test "BTS-204 Step 7: spec.read on linear-routed without ticket arg errors loudly" {
  fx=$(_make_linear_fx)
  run --separate-stderr bash "$OPS" resolve spec.read --project-dir "$fx"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "ticket" ]] || [[ "$stderr" =~ "BTS" ]]
}

@test "BTS-204 Step 7: stasis.read with unknown kind errors loudly" {
  fx=$(_make_linear_fx)
  run --separate-stderr bash "$OPS" resolve stasis.read bogus --project-dir "$fx"
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "kind" ]] || [[ "$stderr" =~ "feature" ]] || [[ "$stderr" =~ "session" ]]
}

# =========================================================================
# Step 8: lifecycle-state storage abstraction
# =========================================================================

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

_make_local_lifecycle_fx() {
  local fx="$BATS_TEST_TMPDIR/local-lc-fx"
  mkdir -p "$fx/.ccanvil" "$fx/docs/specs"
  echo '{}' > "$fx/.claude/ccanvil.json" 2>/dev/null
  mkdir -p "$fx/.claude"
  echo '{}' > "$fx/.claude/ccanvil.json"
  echo "$fx"
}

_make_linear_lifecycle_fx() {
  local fx="$BATS_TEST_TMPDIR/linear-lc-fx"
  mkdir -p "$fx/.ccanvil" "$fx/docs"
  mkdir -p "$fx/.claude"
  cat > "$fx/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {
      "linear": {
        "mechanism": "http",
        "project": "ccanvil",
        "project_id": "test-project-uuid"
      }
    },
    "routing": {
      "spec": "linear",
      "plan": "linear",
      "stasis": "linear"
    }
  }
}
JSON
  echo "$fx"
}

@test "BTS-204 Step 8: lifecycle-state on local-routed empty fx → no-active-spec (unchanged)" {
  set -e
  fx=$(_make_local_lifecycle_fx)
  run bash "$DC" lifecycle-state --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "no-active-spec"'
}

@test "BTS-204 Step 8: lifecycle-state on linear-routed fx with no Linear docs → no-active-spec" {
  set -e
  _setup_stub
  fx=$(_make_linear_lifecycle_fx)
  # Stub returns Document not found for any get-document / document-updated-at
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"errors":[{"message":"Entity not found: Document"}]}
JSON
  # The helper passes a feature_id via env override (test-only path).
  # Without an active feature on a fresh node, lifecycle-state should
  # return no-active-spec without making a network call.
  run bash -c "source '$STUB_FIXTURE' && bash '$DC' lifecycle-state --project-dir '$fx'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "no-active-spec"'
}

@test "BTS-204 Step 8: lifecycle-state on linear-routed fx with active feature reads Linear" {
  set -e
  _setup_stub
  fx=$(_make_linear_lifecycle_fx)
  # Inject an active feature via the test override env var (LIFECYCLE_FEATURE_ID_OVERRIDE).
  export LIFECYCLE_FEATURE_ID_OVERRIDE="BTS-TEST"
  # Stub: first call (spec) returns a doc; subsequent calls (plan, stasis) return errors.
  # Use a multi-response stub by writing a script that picks responses by call count.
  STUB_FIXTURE="$BATS_TEST_TMPDIR/multi-stub.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  local n
  n=$(cat "$BATS_TEST_TMPDIR/call-count" 2>/dev/null || echo 0)
  n=$((n + 1))
  echo "$n" > "$BATS_TEST_TMPDIR/call-count"
  if [[ "$n" == "1" ]]; then
    # spec.exists check → present
    echo '{"data":{"document":{"id":"x","updatedAt":"2026-04-26T20:00:00.000Z","updatedBy":null}}}'
  else
    echo '{"errors":[{"message":"Entity not found: Document"}]}'
  fi
  return 0
}
export -f curl
SHELL
  echo 0 > "$BATS_TEST_TMPDIR/call-count"
  run bash -c "source '$STUB_FIXTURE' && LIFECYCLE_FEATURE_ID_OVERRIDE='BTS-TEST' bash '$DC' lifecycle-state --project-dir '$fx'"
  [ "$status" -eq 0 ]
  # spec exists, plan + stasis don't → state should be "spec-activated"
  echo "$output" | jq -e '.state == "spec-activated"'
}

# =========================================================================
# Phase 4: artifact-read / artifact-write compound primitives
# =========================================================================

@test "BTS-204 Phase 4: artifact-write spec on local route writes docs/spec.md" {
  set -e
  fx=$(_make_local_lifecycle_fx)
  cd "$fx"
  echo "# spec content" | bash "$DC" artifact-write --kind spec --feature BTS-204
  [ -f docs/spec.md ]
  grep -qF "# spec content" docs/spec.md
}

@test "BTS-204 Phase 4: artifact-read spec on local route reads docs/spec.md" {
  set -e
  fx=$(_make_local_lifecycle_fx)
  cd "$fx"
  mkdir -p docs
  echo "# read me" > docs/spec.md
  run bash "$DC" artifact-read --kind spec --feature BTS-204
  [ "$status" -eq 0 ]
  [[ "$output" =~ "# read me" ]]
}

@test "BTS-204 Phase 4: artifact-read on local route returns 2 when file missing" {
  set -e
  fx=$(_make_local_lifecycle_fx)
  cd "$fx"
  run bash "$DC" artifact-read --kind spec --feature BTS-204
  [ "$status" -eq 2 ]
}

# --- skill-prose drift-guards ---

@test "BTS-204 Phase 4: /plan skill prose dispatches via artifact-read --kind spec" {
  grep -qF 'artifact-read --kind spec' "$BATS_TEST_DIRNAME/../../.claude/commands/plan.md"
}

@test "BTS-204 Phase 4: /plan skill prose dispatches via artifact-write --kind plan" {
  grep -qF 'artifact-write --kind plan' "$BATS_TEST_DIRNAME/../../.claude/commands/plan.md"
}

@test "BTS-204 Phase 4: /stasis skill prose dispatches via artifact-write --kind stasis" {
  grep -qF 'artifact-write --kind stasis' "$BATS_TEST_DIRNAME/../../.claude/skills/stasis/SKILL.md"
}

@test "BTS-204 Phase 4: /stasis skill prose mentions both feature and session stasis kinds" {
  grep -qF 'stasis-kind feature' "$BATS_TEST_DIRNAME/../../.claude/skills/stasis/SKILL.md"
  grep -qF 'stasis-kind session' "$BATS_TEST_DIRNAME/../../.claude/skills/stasis/SKILL.md"
}

@test "BTS-204 Phase 4: /recall skill prose dispatches via artifact-read --kind stasis" {
  grep -qF 'artifact-read --kind stasis' "$BATS_TEST_DIRNAME/../../.claude/skills/recall/SKILL.md"
}

@test "BTS-204 Phase 4: /recall skill prose dispatches via artifact-read --kind spec" {
  grep -qF 'artifact-read --kind spec' "$BATS_TEST_DIRNAME/../../.claude/skills/recall/SKILL.md"
}

@test "BTS-204 Phase 5 Step 15: /pr skill prose embeds spec via artifact-read" {
  grep -qF 'artifact-read --kind spec' "$BATS_TEST_DIRNAME/../../.claude/commands/pr.md"
}

@test "BTS-204 Phase 6: ssot-migrate --to linear errors without --feature" {
  fx=$(_make_linear_lifecycle_fx)
  run --separate-stderr bash "$DC" ssot-migrate --to linear
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "feature" ]]
}

@test "BTS-204 Phase 6: ssot-migrate validates direction" {
  fx=$(_make_linear_lifecycle_fx)
  run --separate-stderr bash "$DC" ssot-migrate --to bogus --feature BTS-1
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ "linear" ]] || [[ "$stderr" =~ "local" ]]
}

@test "BTS-204 Phase 6: ssot-migrate --to local with no Linear docs reports skipped" {
  set -e
  _setup_stub
  fx=$(_make_linear_lifecycle_fx)
  cd "$fx"
  # Stub: every read returns "not found" → all skipped
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"errors":[{"message":"Entity not found: Document"}]}
JSON
  run bash -c "source '$STUB_FIXTURE' && bash '$DC' ssot-migrate --to local --feature BTS-204"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.direction == "local"'
  echo "$output" | jq -e '.skipped >= 1'
  echo "$output" | jq -e '.migrated == 0'
}

@test "BTS-204 Phase 7 Step 19: artifact-write refuses on concurrent edit" {
  set -e
  _setup_stub
  fx=$(_make_linear_lifecycle_fx)
  cd "$fx"
  doc_id=$(bash "$LQ" resolve-document-id --kind spec --ticket BTS-204)
  mkdir -p "$fx/.ccanvil/state"
  jq -n --arg id "$doc_id" '{($id): {updatedAt: "2026-04-26T19:00:00.000Z"}}' \
    > "$fx/.ccanvil/state/document-cache.json"
  # Multi-response stub: get-issue (parent UUID) → document-updated-at (NEWER → divergence)
  STUB_FIXTURE="$BATS_TEST_TMPDIR/conflict-stub.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  local n
  n=$(cat "$BATS_TEST_TMPDIR/cnt2" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$BATS_TEST_TMPDIR/cnt2"
  case "$n" in
    1) echo '{"data":{"issue":{"id":"issue-uuid","identifier":"BTS-204","title":"t","priority":2,"createdAt":"t0","updatedAt":"t1","description":"d","state":{"name":"x","type":"x","id":"s"},"labels":{"nodes":[]}}}}' ;;
    2) echo '{"data":{"document":{"id":"x","updatedAt":"2026-04-26T20:00:00.000Z","updatedBy":null}}}' ;;
    *) echo '{"data":{}}' ;;
  esac
  return 0
}
export -f curl
SHELL
  echo 0 > "$BATS_TEST_TMPDIR/cnt2"
  run --separate-stderr bash -c "source '$STUB_FIXTURE' && echo 'new' | bash '$DC' artifact-write --kind spec --feature BTS-204"
  [ "$status" -eq 4 ]
  [[ "$stderr" =~ "concurrent edit" ]]
}

@test "BTS-204 Phase 7 Step 19: ALLOW_CONCURRENT_EDIT_OVERRIDE=1 force-writes" {
  set -e
  _setup_stub
  fx=$(_make_linear_lifecycle_fx)
  cd "$fx"
  doc_id=$(bash "$LQ" resolve-document-id --kind spec --ticket BTS-204)
  mkdir -p "$fx/.ccanvil/state"
  jq -n --arg id "$doc_id" '{($id): {updatedAt: "2026-04-26T19:00:00.000Z"}}' \
    > "$fx/.ccanvil/state/document-cache.json"
  # Stub: divergent updatedAt + successful update path
  STUB_FIXTURE="$BATS_TEST_TMPDIR/override-stub.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  local n
  n=$(cat "$BATS_TEST_TMPDIR/cnt" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$BATS_TEST_TMPDIR/cnt"
  case "$n" in
    1) echo '{"data":{"issue":{"id":"issue-uuid","identifier":"BTS-204","title":"t","priority":2,"createdAt":"t0","updatedAt":"t1","description":"d","state":{"name":"x","type":"x","id":"s"},"labels":{"nodes":[]}}}}' ;;
    2) echo '{"data":{"document":{"id":"x","updatedAt":"t","updatedBy":null}}}' ;;
    3) echo '{"data":{"documentUpdate":{"success":true,"document":{"id":"x","title":"t","content":"new","updatedAt":"2026-04-26T21:00:00Z"}}}}' ;;
    *) echo '{"data":{}}' ;;
  esac
  return 0
}
export -f curl
SHELL
  echo 0 > "$BATS_TEST_TMPDIR/cnt"
  run bash -c "source '$STUB_FIXTURE' && echo 'new' | ALLOW_CONCURRENT_EDIT_OVERRIDE=1 bash '$DC' artifact-write --kind spec --feature BTS-204"
  [ "$status" -eq 0 ]
  # Cache should be updated to the new timestamp
  jq -e --arg id "$doc_id" '.[$id].updatedAt == "2026-04-26T21:00:00Z"' "$fx/.ccanvil/state/document-cache.json"
}

@test "BTS-204 Phase 5 Step 14: cmd_complete archives + trashes Linear documents" {
  set -e
  _setup_stub
  fx="$BATS_TEST_TMPDIR/complete-fx"
  mkdir -p "$fx/.ccanvil/state" "$fx/.claude" "$fx/docs/specs"
  cat > "$fx/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {"linear": {"mechanism": "http", "project_id": "p"}},
    "routing": {"spec": "linear", "plan": "linear", "stasis": "linear"}
  }
}
JSON
  # Minimal spec archive needed for cmd_complete to find feature_id + verify status
  cat > "$fx/docs/specs/bts-test-feature.md" <<'MD'
# Feature: Test
> Feature: bts-test-feature
> Status: In Progress
MD
  # Initialize git for the cmd_complete commit step.
  cd "$fx"
  git init -q . && git config user.email "t@t" && git config user.name "t"
  git add -A && git commit -q -m "init"

  # Stub: every get-document returns content; trash-document returns success.
  STUB_FIXTURE="$BATS_TEST_TMPDIR/complete-stub.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  echo '{"data":{"document":{"id":"x","title":"t","content":"# stored content","slugId":"s","url":"u","updatedAt":"t","createdAt":"t","updatedBy":null,"creator":null,"project":null,"issue":null,"documentDelete":{"success":true}}, "documentDelete":{"success":true}}}'
  return 0
}
export -f curl
SHELL
  # Run cmd_complete.
  run bash -c "source '$STUB_FIXTURE' && bash '$DC' complete bts-test-feature '$fx/docs'"
  [ "$status" -eq 0 ]
  # Archive files should now exist
  ls "$fx/docs/sessions/" | grep -q "bts-test-feature-spec.md"
  ls "$fx/docs/sessions/" | grep -q "bts-test-feature-plan.md"
  ls "$fx/docs/sessions/" | grep -q "bts-test-feature-stasis.md"
}

@test "BTS-204 Phase 4: artifact-write linear-routed dispatches to save-document" {
  set -e
  _setup_stub
  fx=$(_make_linear_lifecycle_fx)
  cd "$fx"
  # Multi-stub: get-issue UUID lookup → returns issue uuid
  #             document-updated-at on derived UUID → not found (404 → create path)
  #             documentCreate → success
  STUB_FIXTURE="$BATS_TEST_TMPDIR/multi-stub-write.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  local body
  body=$(awk '/^[{]/{flag=1} flag' "$LINEAR_STUB_CAPTURE" 2>/dev/null || cat)
  echo "$@" "<<BODY>>" >> "$LINEAR_STUB_CAPTURE"
  while IFS= read -r line; do echo "$line" >> "$LINEAR_STUB_CAPTURE"; done
  # Pick response by call count
  local n
  n=$(cat "$BATS_TEST_TMPDIR/call-count" 2>/dev/null || echo 0)
  n=$((n + 1))
  echo "$n" > "$BATS_TEST_TMPDIR/call-count"
  case "$n" in
    1) echo '{"data":{"issue":{"id":"issue-uuid-x","identifier":"BTS-204","title":"t","priority":2,"createdAt":"t0","updatedAt":"t1","description":"d","state":{"name":"In Progress","type":"started","id":"s"},"labels":{"nodes":[]}}}}' ;;
    2) echo '{"errors":[{"message":"Entity not found: Document"}]}' ;;
    3) echo '{"data":{"documentCreate":{"success":true,"document":{"id":"new-doc-uuid","title":"Spec: BTS-204","content":"# spec content","updatedAt":"t2"}}}}' ;;
    *) echo '{"data":{}}' ;;
  esac
  return 0
}
export -f curl
SHELL
  echo 0 > "$BATS_TEST_TMPDIR/call-count"
  run bash -c "source '$STUB_FIXTURE' && echo '# spec content' | bash '$DC' artifact-write --kind spec --feature BTS-204"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "new-doc-uuid"'
}

@test "BTS-204 Step 8: lifecycle-state without any 'linear' routing skips Linear entirely" {
  # Critical regression check: when ALL routing keys are local/absent, the
  # lifecycle-state derivation must NOT reach for Linear (no API calls,
  # no curl invocation, no network attempt).
  set -e
  fx=$(_make_local_lifecycle_fx)
  # Use a stub that would FAIL (return non-zero exit) if curl were invoked.
  # If lifecycle-state still passes, we know the local path didn't reach curl.
  STUB_FIXTURE="$BATS_TEST_TMPDIR/fail-stub.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  echo "ERROR: curl should not be invoked on a local-routed node" >&2
  return 99
}
export -f curl
SHELL
  run bash -c "source '$STUB_FIXTURE' && bash '$DC' lifecycle-state --project-dir '$fx'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "no-active-spec"'
}

# =========================================================================
# BTS-213: /spec + activate route-aware dispatch on Linear-routed nodes
# =========================================================================

@test "BTS-213 Step 4a: route-of spec returns local on local-routed fixture" {
  set -e
  fx=$(_make_local_lifecycle_fx)
  run bash "$DC" route-of spec --project-dir "$fx"
  [ "$status" -eq 0 ]
  [ "$output" = "local" ]
}

@test "BTS-213 Step 4a: route-of spec returns linear on linear-routed fixture" {
  set -e
  fx=$(_make_linear_lifecycle_fx)
  run bash "$DC" route-of spec --project-dir "$fx"
  [ "$status" -eq 0 ]
  [ "$output" = "linear" ]
}

@test "BTS-213 Step 4a: route-of without kind exits 2 with usage" {
  run --separate-stderr bash "$DC" route-of
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "Usage" ]]
}

@test "BTS-213 Step 4a: route-of accepts plan and stasis kinds" {
  set -e
  fx=$(_make_linear_lifecycle_fx)
  run bash "$DC" route-of plan --project-dir "$fx"
  [ "$output" = "linear" ]
  run bash "$DC" route-of stasis --project-dir "$fx"
  [ "$output" = "linear" ]
}

@test "BTS-213 AC-1: /spec SKILL.md prose dispatches via artifact-write --kind spec when route-of=linear" {
  # Drift-guard: /spec is a skill at .claude/skills/spec/SKILL.md (no commands/spec.md
  # equivalent today). The skill MUST gate on route-of and dispatch via artifact-write
  # when linear-routed; otherwise post-/spec lifecycle-state silently mis-reports.
  grep -qF 'route-of spec' "$BATS_TEST_DIRNAME/../../.claude/skills/spec/SKILL.md"
  grep -qF 'artifact-write --kind spec' "$BATS_TEST_DIRNAME/../../.claude/skills/spec/SKILL.md"
}

@test "BTS-213 AC-2/AC-5: route-of spec on local fx never invokes curl" {
  set -e
  fx=$(_make_local_lifecycle_fx)
  STUB_FIXTURE="$BATS_TEST_TMPDIR/fail-stub-213.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  echo "ERROR: curl invoked on local-routed node" >&2
  return 99
}
export -f curl
SHELL
  run bash -c "source '$STUB_FIXTURE' && bash '$DC' route-of spec --project-dir '$fx'"
  [ "$status" -eq 0 ]
  [ "$output" = "local" ]
}

@test "BTS-213 AC-7: artifact-write spec is idempotent — second call takes update path" {
  set -e
  _setup_stub
  fx=$(_make_linear_lifecycle_fx)
  cd "$fx"
  STUB_FIXTURE="$BATS_TEST_TMPDIR/idempotency-stub.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  local n
  n=$(cat "$BATS_TEST_TMPDIR/idem-cnt" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$BATS_TEST_TMPDIR/idem-cnt"
  case "$n" in
    1) echo '{"data":{"issue":{"id":"issue-uuid","identifier":"BTS-213","title":"t","priority":2,"createdAt":"t0","updatedAt":"t1","description":"d","state":{"name":"x","type":"x","id":"s"},"labels":{"nodes":[]}}}}' ;;
    2) echo '{"errors":[{"message":"Entity not found: Document"}]}' ;;
    3) echo '{"data":{"documentCreate":{"success":true,"document":{"id":"d1","title":"t","content":"c","updatedAt":"t2"}}}}' ;;
    4) echo '{"data":{"issue":{"id":"issue-uuid","identifier":"BTS-213","title":"t","priority":2,"createdAt":"t0","updatedAt":"t1","description":"d","state":{"name":"x","type":"x","id":"s"},"labels":{"nodes":[]}}}}' ;;
    5) echo '{"data":{"document":{"id":"d1","updatedAt":"t2","updatedBy":null}}}' ;;
    6) echo '{"data":{"documentUpdate":{"success":true,"document":{"id":"d1","title":"t","content":"new","updatedAt":"t3"}}}}' ;;
    *) echo '{"data":{}}' ;;
  esac
  return 0
}
export -f curl
SHELL
  echo 0 > "$BATS_TEST_TMPDIR/idem-cnt"
  run bash -c "source '$STUB_FIXTURE' && echo '# v1' | ALLOW_CONCURRENT_EDIT_OVERRIDE=1 bash '$DC' artifact-write --kind spec --feature BTS-213"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "d1"'
  run bash -c "source '$STUB_FIXTURE' && echo '# v2' | ALLOW_CONCURRENT_EDIT_OVERRIDE=1 bash '$DC' artifact-write --kind spec --feature BTS-213"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "d1"'
  [ "$(cat "$BATS_TEST_TMPDIR/idem-cnt")" = "6" ]
}

@test "BTS-213 AC-3: cmd_activate body references _lifecycle_route or route-of for spec" {
  awk '/^cmd_activate\(\)/,/^cmd_complete\(\)/' "$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh" \
    | grep -qE '_lifecycle_route|route-of'
}

@test "BTS-213 AC-3: cmd_activate dispatches artifact-write/cmd_artifact_write for spec on linear route" {
  awk '/^cmd_activate\(\)/,/^cmd_complete\(\)/' "$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh" \
    | grep -qE 'cmd_artifact_write|artifact-write'
}

@test "BTS-213 AC-6: artifact-write spec failure leaves docs/specs archive untouched" {
  set -e
  _setup_stub
  fx=$(_make_linear_lifecycle_fx)
  cd "$fx"
  mkdir -p docs/specs
  printf '%s\n' '> Feature: bts-213' '> Status: Draft' 'body' > docs/specs/bts-213.md
  ARCHIVE_HASH=$(shasum -a 256 docs/specs/bts-213.md | awk '{print $1}')
  STUB_FIXTURE="$BATS_TEST_TMPDIR/err-stub.sh"
  cat > "$STUB_FIXTURE" <<'SHELL'
curl() {
  local n
  n=$(cat "$BATS_TEST_TMPDIR/err-cnt" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$BATS_TEST_TMPDIR/err-cnt"
  case "$n" in
    1) echo '{"data":{"issue":{"id":"issue-uuid","identifier":"BTS-213","title":"t","priority":2,"createdAt":"t0","updatedAt":"t1","description":"d","state":{"name":"x","type":"x","id":"s"},"labels":{"nodes":[]}}}}' ;;
    2) echo '{"errors":[{"message":"Entity not found: Document"}]}' ;;
    *) echo '{"errors":[{"message":"Internal server error"}]}' ;;
  esac
  return 0
}
export -f curl
SHELL
  echo 0 > "$BATS_TEST_TMPDIR/err-cnt"
  run bash -c "source '$STUB_FIXTURE' && cat docs/specs/bts-213.md | ALLOW_CONCURRENT_EDIT_OVERRIDE=1 bash '$DC' artifact-write --kind spec --feature BTS-213"
  [ "$status" -ne 0 ]
  [ -f docs/specs/bts-213.md ]
  AFTER_HASH=$(shasum -a 256 docs/specs/bts-213.md | awk '{print $1}')
  [ "$ARCHIVE_HASH" = "$AFTER_HASH" ]
}
