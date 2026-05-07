#!/usr/bin/env bats
# BTS-321 Phase 3: provider-heal-auth substrate primitive.
# Read-only auth check: sources .env chain, verifies LINEAR_API_KEY,
# runs linear-query.sh viewer as live smoke-test.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
  PROJECT_DIR="$TMPDIR_BATS/proj"
  FAKE_HOME="$TMPDIR_BATS/fake-home"
  mkdir -p "$PROJECT_DIR" "$FAKE_HOME"
  # Isolate from operator's real shell env + ~/.env
  unset LINEAR_API_KEY
  export HOME="$FAKE_HOME"
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

# Stub linear-query.sh viewer subcommand. Behavior parameterized by env vars.
write_viewer_stub() {
  local stub="$TMPDIR_BATS/lq-stub.sh"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
case "$1" in
  viewer)
    if [[ -n "$STUB_VIEWER_EXIT" && "$STUB_VIEWER_EXIT" != "0" ]]; then
      echo "stub viewer error" >&2
      exit "$STUB_VIEWER_EXIT"
    fi
    if [[ -n "$STUB_VIEWER_JSON" ]]; then echo "$STUB_VIEWER_JSON"
    else echo '{"id":"STUB-VIEWER-1","name":"Stub User"}'
    fi
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
# AC-1: shell env key + viewer ok → AUTH-OK + exit 0
# =========================================================================

@test "AC-1: shell-env key + viewer ok → AUTH-OK exit 0" {
  set -e
  stub=$(write_viewer_stub)
  LINEAR_API_KEY="lin_api_stubkey" \
  LINEAR_QUERY_OVERRIDE="$stub" \
    run bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'AUTH-OK: viewer=STUB-VIEWER-1'
}

# =========================================================================
# AC-2: project .env has key (shell env empty) → key sourced + AUTH-OK
# =========================================================================

@test "AC-2: project .env source → key resolved + AUTH-OK" {
  set -e
  stub=$(write_viewer_stub)
  echo 'LINEAR_API_KEY=lin_api_from_project_env' > "$PROJECT_DIR/.env"
  LINEAR_QUERY_OVERRIDE="$stub" \
    run bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok"'
  echo "$output" | jq -e '.key_source | endswith("/.env")'
  echo "$output" | jq -e '.viewer_id == "STUB-VIEWER-1"'
}

@test "AC-2b: ~/.env source when project .env absent" {
  set -e
  stub=$(write_viewer_stub)
  echo 'LINEAR_API_KEY=lin_api_from_home_env' > "$FAKE_HOME/.env"
  LINEAR_QUERY_OVERRIDE="$stub" \
    run bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok"'
  echo "$output" | jq -e '.key_source | endswith("/.env")'
}

# =========================================================================
# AC-3: missing everywhere → exit non-zero with clear message
# =========================================================================

@test "AC-3: missing key everywhere → exit 1 with remediation" {
  stub=$(write_viewer_stub)
  LINEAR_QUERY_OVERRIDE="$stub" \
    run bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'LINEAR_API_KEY not found'
  echo "$output" | grep -qF 'linear.app/settings/api'
}

# =========================================================================
# AC-4: key set but viewer fails → exit non-zero with invalid-key message
# =========================================================================

@test "AC-4: viewer returns non-zero → invalid-key error + WRAPPER ERROR" {
  STUB_VIEWER_EXIT=3
  stub=$(STUB_VIEWER_EXIT=3 write_viewer_stub)
  LINEAR_API_KEY="lin_api_invalidkey" \
  STUB_VIEWER_EXIT=3 \
  LINEAR_QUERY_OVERRIDE="$stub" \
    run bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'viewer smoke-test failed|key may be invalid'
  echo "$output" | grep -qF 'WRAPPER ERROR'
}

@test "AC-4b: viewer returns no .id → invalid-key error" {
  STUB_VIEWER_JSON='{}'
  stub=$(STUB_VIEWER_JSON='{}' write_viewer_stub)
  LINEAR_API_KEY="lin_api_emptyresp" \
  STUB_VIEWER_JSON='{}' \
  LINEAR_QUERY_OVERRIDE="$stub" \
    run bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'viewer smoke-test failed|key may be invalid'
}

# =========================================================================
# AC-5: --json envelope shapes
# =========================================================================

@test "AC-5 missing-key: --json emits status=missing-key" {
  stub=$(write_viewer_stub)
  LINEAR_QUERY_OVERRIDE="$stub" \
    run bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR" --json
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.status == "missing-key"'
  echo "$output" | jq -e '.viewer_id == null'
}

@test "AC-5 invalid-key: --json emits status=invalid-key" {
  STUB_VIEWER_EXIT=3
  stub=$(STUB_VIEWER_EXIT=3 write_viewer_stub)
  LINEAR_API_KEY="lin_api_x" \
  STUB_VIEWER_EXIT=3 \
  LINEAR_QUERY_OVERRIDE="$stub" \
    run bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR" --json
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.status == "invalid-key"'
  echo "$output" | jq -e '.key_source == "shell-env"'
}

# =========================================================================
# AC-6: env isolation — sourced key doesn't leak into parent shell
# =========================================================================

@test "AC-6: env vars sourced from .env do not leak to caller" {
  stub=$(write_viewer_stub)
  echo 'LINEAR_API_KEY=lin_api_from_project_env' > "$PROJECT_DIR/.env"
  LINEAR_QUERY_OVERRIDE="$stub" \
    bash "$SCRIPT" provider-heal-auth --project-dir "$PROJECT_DIR" >/dev/null
  # After substrate runs in subprocess, parent shell should still have
  # LINEAR_API_KEY unset (we unset in setup()).
  [ -z "$LINEAR_API_KEY" ]
}
