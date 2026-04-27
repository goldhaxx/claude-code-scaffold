#!/usr/bin/env bats
# BTS-230: archive-stasis routing-aware. Reads stasis content from a
# Linear Document via cmd_artifact_read when routing.stasis=linear.
# Output destination (docs/sessions/<epoch>-<feature_id>.md) unchanged.

bats_require_minimum_version 1.5.0

DOCS_CHECK="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT_DIR="$TMPDIR/project"
  mkdir -p "$PROJECT_DIR/.claude" "$PROJECT_DIR/docs" "$PROJECT_DIR/docs/sessions"
}

_setup_linear_routed() {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'EOF'
{
  "integrations": {
    "routing": {"stasis": "linear", "spec": "linear", "plan": "linear"},
    "linear": {"team": "Test", "project_id": "00000000-0000-0000-0000-000000000000"}
  }
}
EOF
}

_setup_local_routed() {
  cat > "$PROJECT_DIR/.claude/ccanvil.json" <<'EOF'
{"integrations":{"routing":{"stasis":"local"}}}
EOF
}

_canned_stasis_to() {
  local target="$1"
  cat > "$target" <<'EOF'
# Stasis

> Feature: session-2026-04-27-test
> Kind: session
> Last updated: 1777327000

## Accomplished
test content
EOF
}

# =========================================================================
# AC-3: local-routed regression — reads docs/stasis.md as before
# =========================================================================

@test "AC-3: local-routed reads docs/stasis.md (regression)" {
  _setup_local_routed
  _canned_stasis_to "$PROJECT_DIR/docs/stasis.md"
  run bash "$DOCS_CHECK" archive-stasis --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.archived == true' >/dev/null
  echo "$output" | jq -e '.path == "docs/sessions/1777327000-session-2026-04-27-test.md"' >/dev/null
  [ -f "$PROJECT_DIR/docs/sessions/1777327000-session-2026-04-27-test.md" ]
}

@test "AC-3: local-routed errors when docs/stasis.md missing (regression)" {
  _setup_local_routed
  run bash "$DOCS_CHECK" archive-stasis --project-dir "$PROJECT_DIR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "docs/stasis.md not found"
}

# =========================================================================
# AC-4: Linear-routed + no content errors clearly
# =========================================================================

@test "AC-4: Linear-routed + no content errors with diagnostic" {
  _setup_linear_routed
  cd "$PROJECT_DIR"  # avoid auto-loading project .env via _load_env_if_needed
  run env -u LINEAR_API_KEY bash "$DOCS_CHECK" archive-stasis --project-dir "$PROJECT_DIR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no stasis content found"
}

# =========================================================================
# Drift-guard: BTS-230 reference present in docs-check.sh
# =========================================================================

@test "drift: BTS-230 referenced inline in docs-check.sh" {
  grep -q "BTS-230" "$DOCS_CHECK"
}
