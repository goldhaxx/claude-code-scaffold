#!/usr/bin/env bats
# BTS-219 — drift-guards for cmd_artifact_read WARN-on-failure across the
# four failure classes (auth-missing, not-found, network-error, parse-error).
#
# Tests use a fixture project dir with routing.spec=linear so cmd_artifact_read
# enters the linear branch. Auth/network failures are reproduced by:
#   - auth-missing: unset LINEAR_API_KEY
#   - network-error: set LINEAR_QUERY_ENDPOINT to a bogus localhost port
# not-found and parse-error are tested via the `_classify_linear_failure`
# helper directly (awk-extract pattern, no live API needed) — see below.

bats_require_minimum_version 1.5.0

DC="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  unset LINEAR_API_KEY
  unset LINEAR_QUERY_ENDPOINT
  # BTS-331: isolate ~/.env and Keychain tiers so missing-key tests don't
  # silently resolve via the operator's real fallbacks.
  export HOME="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$HOME"
  local stub_bin="$BATS_TEST_TMPDIR/stub-bin"
  mkdir -p "$stub_bin"
  printf '#!/usr/bin/env bash\nexit 44\n' > "$stub_bin/security"
  chmod +x "$stub_bin/security"
  export PATH="$stub_bin:$PATH"
}

# Fixture: linear-routed project dir.
_make_linear_fx() {
  local fx="$BATS_TEST_TMPDIR/lr-fx"
  mkdir -p "$fx/.claude" "$fx/.ccanvil/state" "$fx/docs/specs"
  cat > "$fx/.claude/ccanvil.json" <<'JSON'
{
  "integrations": {
    "providers": {
      "linear": {
        "mechanism": "http",
        "project": "ccanvil",
        "team": "Blocktech Solutions",
        "project_id": "305b7cbe-cd8d-4fce-bcff-bbfee74b2e44"
      }
    },
    "routing": { "spec": "linear", "plan": "linear", "stasis": "linear" }
  }
}
JSON
  printf '%s' "$fx"
}

# =========================================================================
# AC-2: auth-missing — LINEAR_API_KEY unset
# =========================================================================

@test "BTS-219 AC-2: auth-missing emits WARN with retry recipe" {
  set -e
  fx=$(_make_linear_fx)
  # cd into fixture (no .git/.env) so linear-query.sh's _load_env_if_needed
  # doesn't auto-source the project's real .env.
  cd "$fx"
  run bash "$DC" artifact-read --kind spec --feature BTS-219 --project-dir "$fx"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'WARN: artifact-read: auth-missing'
  echo "$output" | grep -qE 'Retry: Set LINEAR_API_KEY'
}

# =========================================================================
# Network-error: bogus endpoint
# =========================================================================

@test "BTS-219: network-error emits WARN when endpoint is unreachable" {
  set -e
  fx=$(_make_linear_fx)
  cd "$fx"
  export LINEAR_API_KEY="dummy_for_test"
  export LINEAR_QUERY_ENDPOINT="http://127.0.0.1:9/nonexistent"
  run bash "$DC" artifact-read --kind spec --feature BTS-219 --project-dir "$fx"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'WARN: artifact-read: network-error'
  echo "$output" | grep -qE 'Retry: '
}

# =========================================================================
# Classification helper: not-found, parse-error, fallback
# =========================================================================
# Tests the internal _classify_linear_failure helper directly via awk-extract
# (BTS-217 helper-test pattern — sources the function without triggering the
# script's tail dispatcher).

_extract_classify_helper() {
  awk '/^_classify_linear_failure\(\)/,/^}$/' "$DC"
}

@test "BTS-219: _classify_linear_failure detects auth-missing from stderr" {
  set -e
  helper=$(_extract_classify_helper)
  errfile=$(mktemp)
  echo "ERROR: LINEAR_API_KEY not set. Export it..." > "$errfile"
  result=$(bash -c "$helper; _classify_linear_failure '$errfile'")
  [ "$result" = "auth-missing" ]
  rm -f "$errfile"
}

@test "BTS-219: _classify_linear_failure detects not-found from stderr" {
  set -e
  helper=$(_extract_classify_helper)
  errfile=$(mktemp)
  echo "Entity not found: Document - 1ec607ad-7487-43e2-8be5-8c19eb5eec2b" > "$errfile"
  result=$(bash -c "$helper; _classify_linear_failure '$errfile'")
  [ "$result" = "not-found" ]
  rm -f "$errfile"
}

@test "BTS-219: _classify_linear_failure detects network-error from stderr" {
  set -e
  helper=$(_extract_classify_helper)
  errfile=$(mktemp)
  echo "curl: (6) Could not resolve host: api.linear.app" > "$errfile"
  result=$(bash -c "$helper; _classify_linear_failure '$errfile'")
  [ "$result" = "network-error" ]
  rm -f "$errfile"
}

@test "BTS-219: _classify_linear_failure falls back to parse-error" {
  set -e
  helper=$(_extract_classify_helper)
  errfile=$(mktemp)
  echo "Some unexpected output that doesn't match any known class" > "$errfile"
  result=$(bash -c "$helper; _classify_linear_failure '$errfile'")
  [ "$result" = "parse-error" ]
  rm -f "$errfile"
}

@test "BTS-219: _classify_linear_failure handles empty stderr (parse-error)" {
  set -e
  helper=$(_extract_classify_helper)
  errfile=$(mktemp)
  : > "$errfile"
  result=$(bash -c "$helper; _classify_linear_failure '$errfile'")
  [ "$result" = "parse-error" ]
  rm -f "$errfile"
}
