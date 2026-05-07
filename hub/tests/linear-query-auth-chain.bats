#!/usr/bin/env bats
# BTS-331 — linear-query.sh auth chain extension: 4-tier resolution
# (env var → project .env → ~/.env → macOS Keychain).
# Covers spec AC-1..AC-8. AC-9 is the existence of this file. AC-10 is
# the live-API validation gate, run outside bats.

bats_require_minimum_version 1.5.0

LQ="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/linear-query.sh"
STUB_FIXTURE="$BATS_TEST_DIRNAME/fixtures/linear-stub.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  unset LINEAR_API_KEY
  unset LINEAR_QUERY_ENDPOINT
  # Isolate HOME so any real ~/.env doesn't leak in.
  export HOME="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$HOME"
  # Stub bin dir prepended to PATH for the `security` interceptor.
  export STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
  mkdir -p "$STUB_BIN"
  # Default: stub responds with "item not found" exit unless overridden.
  unset STUB_KEYCHAIN_VALUE
  unset STUB_KEYCHAIN_EXIT
}

# Build a fake project: <root>/.git sentinel, optional .env. Caller cd's in.
_make_project() {
  local root="$BATS_TEST_TMPDIR/project"
  mkdir -p "$root/.git"
  echo "$root"
}

# Install a stub `security` binary on PATH. Behavior driven by
# STUB_KEYCHAIN_VALUE (string echoed on stdout) and STUB_KEYCHAIN_EXIT
# (rc; defaults to 0 when value set, 44 (errSecItemNotFound) when unset).
_install_security_stub() {
  cat > "$STUB_BIN/security" <<'STUBEOF'
#!/usr/bin/env bash
# Args we care about: find-generic-password ... -s <service> -w
if [[ -n "${STUB_KEYCHAIN_VALUE:-}" ]]; then
  printf '%s\n' "$STUB_KEYCHAIN_VALUE"
  exit "${STUB_KEYCHAIN_EXIT:-0}"
fi
exit "${STUB_KEYCHAIN_EXIT:-44}"
STUBEOF
  chmod +x "$STUB_BIN/security"
  export PATH="$STUB_BIN:$PATH"
}

# Helper: stage standard graphql stub and a successful viewer response.
_stage_viewer_stub() {
  export LINEAR_STUB_CAPTURE="$BATS_TEST_TMPDIR/curl-args"
  export LINEAR_STUB_RESPONSE="$BATS_TEST_TMPDIR/curl-response.json"
  export LINEAR_QUERY_ENDPOINT="https://stub.example.test/graphql"
  cat > "$LINEAR_STUB_RESPONSE" <<'JSON'
{"data":{"viewer":{"id":"u","name":"n"}}}
JSON
}

# ===========================================================================
# AC-1: exported env var wins; no walk-up, no ~/.env, no keychain.
# ===========================================================================

@test "AC-1: exported LINEAR_API_KEY beats all other tiers" {
  set -e
  PROJECT=$(_make_project)
  # Plant decoys at every other tier — none should win.
  cat > "$PROJECT/.env" <<EOF
LINEAR_API_KEY=loses-to-env-var-from-project-env
EOF
  cat > "$HOME/.env" <<EOF
LINEAR_API_KEY=loses-to-env-var-from-home-env
EOF
  STUB_KEYCHAIN_VALUE="loses-to-env-var-from-keychain" _install_security_stub
  export LINEAR_API_KEY="exported-wins"
  _stage_viewer_stub
  run bash -c "cd '$PROJECT' && source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  grep -F "Authorization: exported-wins" "$LINEAR_STUB_CAPTURE"
  ! grep -qE "loses-to-env-var" "$LINEAR_STUB_CAPTURE"
}

# ===========================================================================
# AC-2: project .env beats ~/.env and keychain when env var unset.
# ===========================================================================

@test "AC-2: project-root .env wins over ~/.env and keychain" {
  set -e
  PROJECT=$(_make_project)
  cat > "$PROJECT/.env" <<EOF
LINEAR_API_KEY=project-env-wins
EOF
  cat > "$HOME/.env" <<EOF
LINEAR_API_KEY=loses-to-project-env
EOF
  STUB_KEYCHAIN_VALUE="loses-to-project-env-from-keychain" _install_security_stub
  _stage_viewer_stub
  run bash -c "cd '$PROJECT' && source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  grep -F "Authorization: project-env-wins" "$LINEAR_STUB_CAPTURE"
}

# ===========================================================================
# AC-3: ~/.env fallback when project tree has no key.
# ===========================================================================

@test "AC-3: ~/.env wins when no env var and no project .env key" {
  set -e
  PROJECT=$(_make_project)
  # No project .env at all.
  cat > "$HOME/.env" <<EOF
LINEAR_API_KEY=home-env-wins
EOF
  STUB_KEYCHAIN_VALUE="loses-to-home-env" _install_security_stub
  _stage_viewer_stub
  run bash -c "cd '$PROJECT' && source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  grep -F "Authorization: home-env-wins" "$LINEAR_STUB_CAPTURE"
}

@test "AC-3: ~/.env wins when project .env exists but lacks LINEAR_API_KEY" {
  set -e
  PROJECT=$(_make_project)
  cat > "$PROJECT/.env" <<EOF
OTHER_VAR=irrelevant
EOF
  cat > "$HOME/.env" <<EOF
LINEAR_API_KEY=home-env-wins-after-partial-project
EOF
  _install_security_stub
  _stage_viewer_stub
  run bash -c "cd '$PROJECT' && source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  grep -F "Authorization: home-env-wins-after-partial-project" "$LINEAR_STUB_CAPTURE"
}

@test "AC-3: ~/.env wins when \$PWD has no .git ancestor" {
  set -e
  cat > "$HOME/.env" <<EOF
LINEAR_API_KEY=home-env-wins-no-git-tree
EOF
  _install_security_stub
  _stage_viewer_stub
  # cwd is BATS_TEST_TMPDIR — no .git anywhere up the tree.
  run bash -c "cd '$BATS_TEST_TMPDIR' && source '$STUB_FIXTURE' && bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  grep -F "Authorization: home-env-wins-no-git-tree" "$LINEAR_STUB_CAPTURE"
}

# ===========================================================================
# AC-4: macOS Keychain fallback when tiers 1-3 miss.
# ===========================================================================

@test "AC-4: keychain wins when no env var, no project .env, no ~/.env" {
  set -e
  PROJECT=$(_make_project)
  STUB_KEYCHAIN_VALUE="keychain-wins" _install_security_stub
  _stage_viewer_stub
  run bash -c "cd '$PROJECT' && source '$STUB_FIXTURE' && STUB_KEYCHAIN_VALUE='keychain-wins' bash '$LQ' viewer"
  [ "$status" -eq 0 ]
  grep -F "Authorization: keychain-wins" "$LINEAR_STUB_CAPTURE"
}

@test "AC-4: keychain non-zero exit (item-not-found) does NOT export" {
  PROJECT=$(_make_project)
  # No keychain value → stub exits 44.
  _install_security_stub
  run --separate-stderr bash -c "cd '$PROJECT' && bash '$LQ' viewer"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "LINEAR_API_KEY not set" ]]
}

# ===========================================================================
# AC-5: service-name mapping — script comment documents LINEAR_API_KEY → linear_api_key.
# ===========================================================================

@test "AC-5: linear-query.sh comments document the lowercase mapping rule" {
  grep -qE "LINEAR_API_KEY.*linear_api_key|linear_api_key.*lowercased" "$LQ"
}

# ===========================================================================
# AC-6: graceful no-op when `security` is not on PATH (non-macOS).
# ===========================================================================

@test "AC-6: security absent → keychain step skipped silently, falls through to tier-5 error" {
  PROJECT=$(_make_project)
  # Restrict PATH so `security` is unreachable. Keep coreutils for jq/curl.
  # Probe the real PATH dirs that hold the script's runtime deps.
  local restricted_path="/usr/bin:/bin"
  # Confirm `security` is not on the restricted path (sanity).
  ! PATH="$restricted_path" command -v security >/dev/null 2>&1 || skip "system /usr/bin/security present — cannot exercise no-op path"
  run --separate-stderr bash -c "cd '$PROJECT' && PATH='$restricted_path' bash '$LQ' viewer"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "LINEAR_API_KEY not set" ]]
  # No noise about security command-not-found
  ! [[ "$stderr" =~ "command not found" ]]
  ! [[ "$stderr" =~ "security:" ]]
}

# ===========================================================================
# AC-7: live-API gate — keychain interactive-approval semantics.
# Documented as the live-validation step (Plan Step 7); not exercised here.
# ===========================================================================

@test "AC-7: documented as live-validation gate (placeholder)" {
  skip "AC-7 verified live per plan Step 7 — keychain Always-Allow semantics not stub-able"
}

# ===========================================================================
# AC-8: error message names all 4 resolution tiers verbatim.
# ===========================================================================

@test "AC-8: exit-2 error message names env-var, project .env, ~/.env, and Keychain tier" {
  PROJECT=$(_make_project)
  # No tiers populated; security stub returns rc=44.
  _install_security_stub
  run --separate-stderr bash -c "cd '$PROJECT' && bash '$LQ' viewer"
  [ "$status" -eq 2 ]
  [[ "$stderr" =~ "LINEAR_API_KEY" ]]
  [[ "$stderr" =~ "project root" ]] || [[ "$stderr" =~ ".env at" ]]
  [[ "$stderr" =~ "~/.env" ]] || [[ "$stderr" =~ "home" ]]
  [[ "$stderr" =~ "linear_api_key" ]] || [[ "$stderr" =~ "Keychain" ]]
}

# ===========================================================================
# Regression: BTS-167 invariants still hold.
# ===========================================================================

@test "regression: malformed project .env still fails non-zero" {
  PROJECT=$(_make_project)
  cat > "$PROJECT/.env" <<'EOF'
LINEAR_API_KEY="unterminated
EOF
  run --separate-stderr bash -c "cd '$PROJECT' && bash '$LQ' viewer"
  [ "$status" -ne 0 ]
}
