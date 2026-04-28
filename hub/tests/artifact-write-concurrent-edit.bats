#!/usr/bin/env bats
# BTS-237: spec dispatch + activate concurrent-edit race fix.
# cmd_artifact_write must NOT cache updatedAt after the CREATE path, because
# Linear's eventual-consistency / async normalizer can advance the timestamp
# slightly after the save returns. Caching the create-response value produces
# a self-stale baseline that the next UPDATE writer (typically cmd_activate)
# trips against. Skipping cache on CREATE lets the next writer see an empty
# cache (treated as "first write — safe") and proceed.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
  PROJECT_DIR="$TMPDIR_BATS/proj"
  mkdir -p "$PROJECT_DIR/.claude"
  # Minimal Linear-routed config so cmd_artifact_write resolves spec→linear.
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'EOF'
{
  "integrations": {
    "routing": {"spec": "linear", "plan": "linear", "stasis": "linear"},
    "linear": {
      "team": "Blocktech Solutions",
      "project": "ccanvil",
      "project_id": "305b7cbe-cd8d-4fce-bcff-bbfee74b2e44",
      "team_id": "6d92fa03-7933-435c-81a4-95ad8b8b732a",
      "labels": "idea",
      "state_ids": {"triage":"0dc23450-abcf-4c08-a9d3-bcf787c62fbd"}
    }
  }
}
EOF
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

# Stub linear-query.sh that branches on subcommand. Behavior per call is
# controlled by directives written to $LQ_DIRECTIVES (one directive per call).
write_lq_stub() {
  local stub="$TMPDIR_BATS/lq-stub.sh"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
# Args: <subcmd> [<arg1>...]
case "$1" in
  resolve-document-id)
    # Return a fixed UUID for any --kind/--ticket combo
    echo "11111111-2222-3333-4444-555555555555"
    exit 0
    ;;
  document-updated-at)
    # Behavior controlled by $DOC_EXISTS env var
    if [[ "${DOC_EXISTS:-0}" == "1" ]]; then
      jq -n --arg ts "${REMOTE_UPDATED_AT:-2099-01-01T00:00:00.000Z}" '{updatedAt:$ts}'
      exit 0
    else
      exit 1
    fi
    ;;
  get-issue)
    # Return a fake UUID for the parent linkage
    jq -n '{uuid:"99999999-9999-9999-9999-999999999999"}'
    exit 0
    ;;
  save-document)
    # Read stdin (input-json), echo back with the response timestamp.
    input=$(cat)
    jq -n --arg id "$(echo "$input" | jq -r '.id')" \
          --arg ts "${SAVE_RESPONSE_TS:-2099-01-01T00:00:00.000Z}" \
          '{id:$id, updatedAt:$ts, content:"stub"}'
    exit 0
    ;;
  *)
    echo "stub: unsupported subcommand $1" >&2
    exit 2
    ;;
esac
STUBEOF
  chmod +x "$stub"
  echo "$stub"
}

# =========================================================================
# AC-2: CREATE path → cache NOT populated, second UPDATE call NOT raced
# =========================================================================

@test "BTS-237 AC-2: CREATE-path cmd_artifact_write does not cache updatedAt" {
  set -e
  stub=$(write_lq_stub)
  DOC_ID="11111111-2222-3333-4444-555555555555"

  # Configure stub: doc doesn't exist yet (forces create path), save returns T1.
  export DOC_EXISTS=0
  export SAVE_RESPONSE_TS="2099-01-01T00:00:00.000Z"

  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" \
    artifact-write --kind spec --feature BTS-9999 --project-dir "$PROJECT_DIR" <<<"# spec content"
  [ "$status" -eq 0 ]

  # Cache file must NOT contain the doc_id entry after CREATE
  cache_file="$PROJECT_DIR/.ccanvil/state/document-cache.json"
  if [[ -f "$cache_file" ]]; then
    if jq -e --arg id "$DOC_ID" '.[$id] // empty' "$cache_file" >/dev/null; then
      echo "FAIL: cache populated after CREATE — file contents:" >&2
      cat "$cache_file" >&2
      return 1
    fi
  fi
}

# =========================================================================
# AC-2 follow-up: After CREATE, an immediate UPDATE call does NOT trip the race
# =========================================================================

@test "BTS-237 AC-2b: UPDATE immediately after CREATE proceeds without race" {
  set -e
  stub=$(write_lq_stub)

  # First call: CREATE (doc doesn't exist), save returns T1.
  export DOC_EXISTS=0
  export SAVE_RESPONSE_TS="2099-01-01T00:00:00.000Z"
  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" \
    artifact-write --kind spec --feature BTS-9999 --project-dir "$PROJECT_DIR" <<<"# create content"
  [ "$status" -eq 0 ]

  # Second call: UPDATE (doc exists, remote returns T2 > T1).
  # If CREATE had cached T1, the pre-flight would compare T2 vs T1 and refuse.
  # Post-fix: cache is empty after CREATE, so the pre-flight short-circuits
  # with "no cache → safe" and the UPDATE proceeds.
  export DOC_EXISTS=1
  export REMOTE_UPDATED_AT="2099-01-01T00:00:01.000Z"  # T2 > T1
  export SAVE_RESPONSE_TS="2099-01-01T00:00:01.000Z"
  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" \
    artifact-write --kind spec --feature BTS-9999 --project-dir "$PROJECT_DIR" <<<"# update content"
  if [ "$status" -ne 0 ]; then
    echo "FAIL: UPDATE after CREATE tripped the race (exit $status):" >&2
    echo "$output" >&2
    return 1
  fi
}

# =========================================================================
# AC-3: UPDATE path STILL caches the response updatedAt
# =========================================================================

@test "BTS-237 AC-3: UPDATE path caches the response updatedAt" {
  set -e
  stub=$(write_lq_stub)
  DOC_ID="11111111-2222-3333-4444-555555555555"

  export DOC_EXISTS=1
  export REMOTE_UPDATED_AT="2099-01-01T00:00:00.000Z"
  export SAVE_RESPONSE_TS="2099-01-01T00:00:01.000Z"

  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" \
    artifact-write --kind spec --feature BTS-9999 --project-dir "$PROJECT_DIR" <<<"# update content"
  [ "$status" -eq 0 ]

  cache_file="$PROJECT_DIR/.ccanvil/state/document-cache.json"
  [ -f "$cache_file" ]
  cached=$(jq -r --arg id "$DOC_ID" '.[$id].updatedAt // empty' "$cache_file")
  [ "$cached" = "2099-01-01T00:00:01.000Z" ]
}

# =========================================================================
# AC-4: race detection still works when cache is populated
# =========================================================================

@test "BTS-237 AC-4: pre-flight refuses when remote updatedAt has advanced past cache" {
  stub=$(write_lq_stub)
  DOC_ID="11111111-2222-3333-4444-555555555555"

  # Pre-populate cache with T1
  mkdir -p "$PROJECT_DIR/.ccanvil/state"
  jq -n --arg id "$DOC_ID" --arg ts "2099-01-01T00:00:00.000Z" \
    '{($id): {updatedAt: $ts}}' > "$PROJECT_DIR/.ccanvil/state/document-cache.json"

  # Stub returns T2 > T1 from document-updated-at — simulates a real
  # concurrent writer.
  export DOC_EXISTS=1
  export REMOTE_UPDATED_AT="2099-01-01T00:01:00.000Z"

  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" \
    artifact-write --kind spec --feature BTS-9999 --project-dir "$PROJECT_DIR" <<<"# update content"
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi 'concurrent edit detected'
}

# =========================================================================
# Drift-guard
# =========================================================================

@test "BTS-237 drift: BTS-237 referenced inline in docs-check.sh" {
  grep -q "BTS-237" "$SCRIPT"
}
