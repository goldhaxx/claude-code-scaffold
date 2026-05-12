#!/usr/bin/env bats
#
# BTS-324: routing-key rename heal substrate.
#
# Detects legacy `integrations.routing.ticket = "linear"` keys in downstream
# nodes (stochastic-init divergence) and renames to canonical
# routing.{idea,spec,plan,stasis,backlog}. Drains .ccanvil/ideas-pending.log
# after rename so stuck Linear transitions land. Sibling under BTS-316.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
  PROJECT_DIR="$TMPDIR_BATS/proj"
  mkdir -p "$PROJECT_DIR/.claude" "$PROJECT_DIR/.ccanvil"
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

seed_legacy() {
  # Seed config with the BTS-324 anchor case: routing.ticket = "linear",
  # no canonical routing keys, full providers.linear block.
  cat > "$PROJECT_DIR/.claude/ccanvil.local.json" <<'EOF'
{
  "node_uuid": "deadbeef-aaaa-bbbb-cccc-111122223333",
  "integrations": {
    "routing": {"ticket": "linear"},
    "providers": {"linear": {"team": "Foo", "project": "Bar"}}
  }
}
EOF
}

seed_canonical() {
  cat > "$PROJECT_DIR/.claude/ccanvil.local.json" <<'EOF'
{
  "integrations": {
    "routing": {"idea": "linear"},
    "providers": {"linear": {"team": "Foo", "project": "Bar"}}
  }
}
EOF
}

# =========================================================================
# Step 1 — skeleton: --help (unknown flag) emits usage and exits 2
# =========================================================================

@test "BTS-324 skeleton: --help emits usage and exits 2" {
  run bash "$SCRIPT" provider-heal-routing-rename --help --project-dir "$PROJECT_DIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"Usage:"* ]] || [[ "$output" == *"Usage:"* ]]
  [[ "$stderr" == *"provider-heal-routing-rename"* ]] || [[ "$output" == *"provider-heal-routing-rename"* ]]
}

# =========================================================================
# AC-1 — --check read-only envelope, idempotent, no filesystem writes
# =========================================================================

@test "BTS-324 AC-1: --check emits legacy-detected envelope with full shape" {
  seed_legacy
  run bash "$SCRIPT" provider-heal-routing-rename --check --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "legacy-detected"' >/dev/null
  echo "$output" | jq -e '.legacy_key_present == true' >/dev/null
  echo "$output" | jq -e '.legacy_value == "linear"' >/dev/null
  echo "$output" | jq -e '.canonical_keys_present == []' >/dev/null
  echo "$output" | jq -e '.proposed_target == ["idea"]' >/dev/null
}

@test "BTS-324 AC-1: --check is byte-identical across two consecutive runs (idempotent)" {
  seed_legacy
  first=$(bash "$SCRIPT" provider-heal-routing-rename --check --project-dir "$PROJECT_DIR")
  second=$(bash "$SCRIPT" provider-heal-routing-rename --check --project-dir "$PROJECT_DIR")
  [ "$first" = "$second" ]
}

@test "BTS-324 AC-1: --check does not write to filesystem (mtime unchanged)" {
  seed_legacy
  cfg="$PROJECT_DIR/.claude/ccanvil.local.json"
  before=$(stat -f %m "$cfg" 2>/dev/null || stat -c %Y "$cfg")
  sleep 1
  bash "$SCRIPT" provider-heal-routing-rename --check --project-dir "$PROJECT_DIR" >/dev/null
  after=$(stat -f %m "$cfg" 2>/dev/null || stat -c %Y "$cfg")
  [ "$before" = "$after" ]
}

@test "BTS-324 AC-1: --check against already-canonical config emits status:already-canonical, not legacy-detected" {
  seed_canonical
  run bash "$SCRIPT" provider-heal-routing-rename --check --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "already-canonical"' >/dev/null
  echo "$output" | jq -e '.legacy_key_present == false' >/dev/null
  # And the negative: must NOT report legacy-detected.
  ! echo "$output" | jq -e '.status == "legacy-detected"' >/dev/null
}

# =========================================================================
# AC-7 — error/edge: missing config file, no integrations.routing
# =========================================================================

@test "BTS-324 AC-7: missing .claude/ccanvil.local.json → exit 1 with stderr" {
  # Do NOT seed; config file absent.
  run bash "$SCRIPT" provider-heal-routing-rename --check --project-dir "$PROJECT_DIR"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"ERROR: no .claude/ccanvil.local.json"* ]] || [[ "$output" == *"ERROR: no .claude/ccanvil.local.json"* ]]
}

@test "BTS-324 AC-7: config exists but no integrations.routing → no-op exit 0" {
  echo '{}' > "$PROJECT_DIR/.claude/ccanvil.local.json"
  run bash "$SCRIPT" provider-heal-routing-rename --check --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "no-op"' >/dev/null
  echo "$output" | jq -e '.reason == "no-routing-config"' >/dev/null
}

# =========================================================================
# AC-5 — --apply no-op when legacy ticket key absent
# =========================================================================

@test "BTS-324 AC-5: --apply with no legacy key → no-op, config bytes unchanged" {
  seed_canonical
  cfg="$PROJECT_DIR/.claude/ccanvil.local.json"
  cp "$cfg" "$TMPDIR_BATS/before.json"
  run bash "$SCRIPT" provider-heal-routing-rename --apply --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "no-op"' >/dev/null
  echo "$output" | jq -e '.reason == "no-legacy-key-found"' >/dev/null
  cmp "$cfg" "$TMPDIR_BATS/before.json"
}

# =========================================================================
# AC-2 — --apply default rename (ticket → idea)
# =========================================================================

@test "BTS-324 AC-2: --apply renames routing.ticket → routing.idea by default" {
  seed_legacy
  cfg="$PROJECT_DIR/.claude/ccanvil.local.json"
  run bash "$SCRIPT" provider-heal-routing-rename --apply --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "renamed"' >/dev/null
  echo "$output" | jq -e '.from == "ticket"' >/dev/null
  echo "$output" | jq -e '.to == ["idea"]' >/dev/null
  echo "$output" | jq -e '.drained' >/dev/null

  # Config side: routing.idea = linear, routing.ticket absent.
  jq -e '.integrations.routing.idea == "linear"' "$cfg" >/dev/null
  jq -e '.integrations.routing | has("ticket") | not' "$cfg" >/dev/null
  # Providers block preserved.
  jq -e '.integrations.providers.linear.team == "Foo"' "$cfg" >/dev/null
  # File is still valid JSON.
  jq -e '.' "$cfg" >/dev/null
}

# =========================================================================
# AC-3 — --routes <list> SSOT shape + invalid-kind validation
# =========================================================================

@test "BTS-324 AC-3: --apply --routes spec,plan,stasis,idea fans out to all four" {
  seed_legacy
  cfg="$PROJECT_DIR/.claude/ccanvil.local.json"
  run bash "$SCRIPT" provider-heal-routing-rename --apply \
    --routes spec,plan,stasis,idea --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.to == ["spec","plan","stasis","idea"]' >/dev/null
  for kind in spec plan stasis idea; do
    jq -e --arg k "$kind" '.integrations.routing[$k] == "linear"' "$cfg" >/dev/null
  done
  jq -e '.integrations.routing | has("ticket") | not' "$cfg" >/dev/null
}

@test "BTS-324 AC-3: invalid --routes kind → exit 2 with structured stderr" {
  seed_legacy
  run bash "$SCRIPT" provider-heal-routing-rename --apply \
    --routes spec,bogus --project-dir "$PROJECT_DIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"unknown route kind 'bogus'"* ]] || [[ "$output" == *"unknown route kind 'bogus'"* ]]
  [[ "$stderr" == *"spec, plan, stasis, idea, backlog"* ]] || [[ "$output" == *"spec, plan, stasis, idea, backlog"* ]]
}

@test "BTS-324 AC-3: --check --routes spec,plan reports proposed_target" {
  seed_legacy
  run bash "$SCRIPT" provider-heal-routing-rename --check \
    --routes spec,plan --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.proposed_target == ["spec","plan"]' >/dev/null
}

# =========================================================================
# AC-6 — target-set-scoped conflict refusal (critic-mode finding addressed)
# =========================================================================

seed_legacy_with_canonical_idea() {
  cat > "$PROJECT_DIR/.claude/ccanvil.local.json" <<'EOF'
{
  "integrations": {
    "routing": {"ticket": "linear", "idea": "local"},
    "providers": {"linear": {"team": "Foo", "project": "Bar"}}
  }
}
EOF
}

@test "BTS-324 AC-6: --apply default target [idea] conflicts with existing routing.idea → exit 1, config unchanged" {
  seed_legacy_with_canonical_idea
  cfg="$PROJECT_DIR/.claude/ccanvil.local.json"
  cp "$cfg" "$TMPDIR_BATS/before.json"
  run bash "$SCRIPT" provider-heal-routing-rename --apply --project-dir "$PROJECT_DIR"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "conflict"' >/dev/null
  echo "$output" | jq -e '.existing_canonical == ["idea"]' >/dev/null
  echo "$output" | jq -e '.legacy_value == "linear"' >/dev/null
  echo "$output" | jq -e '.target_routes == ["idea"]' >/dev/null
  cmp "$cfg" "$TMPDIR_BATS/before.json"
}

@test "BTS-324 AC-6: --apply --routes spec,plan against routing.idea preexisting → succeeds (outside target set)" {
  seed_legacy_with_canonical_idea
  cfg="$PROJECT_DIR/.claude/ccanvil.local.json"
  run bash "$SCRIPT" provider-heal-routing-rename --apply \
    --routes spec,plan --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "renamed"' >/dev/null
  jq -e '.integrations.routing.spec == "linear"' "$cfg" >/dev/null
  jq -e '.integrations.routing.plan == "linear"' "$cfg" >/dev/null
  # Pre-existing routing.idea preserved untouched.
  jq -e '.integrations.routing.idea == "local"' "$cfg" >/dev/null
  # ticket removed.
  jq -e '.integrations.routing | has("ticket") | not' "$cfg" >/dev/null
}

@test "BTS-324 AC-6: --check with colliding seed → exit 0 (read-only) but envelope status is conflict" {
  seed_legacy_with_canonical_idea
  run bash "$SCRIPT" provider-heal-routing-rename --check --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "conflict"' >/dev/null
  echo "$output" | jq -e '.existing_canonical == ["idea"]' >/dev/null
}

# =========================================================================
# AC-4 — drain step via cmd_idea_pending_replay
# =========================================================================

@test "BTS-324 AC-4: --apply with no pending log → drained all-zeros, rename succeeds" {
  seed_legacy
  cfg="$PROJECT_DIR/.claude/ccanvil.local.json"
  run bash "$SCRIPT" provider-heal-routing-rename --apply --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drained.synced == 0' >/dev/null
  echo "$output" | jq -e '.drained.failed == 0' >/dev/null
  echo "$output" | jq -e '.drained.pending == 0' >/dev/null
  jq -e '.integrations.routing.idea == "linear"' "$cfg" >/dev/null
}

@test "BTS-324 AC-4: --apply with empty pending log → drained all-zeros, rename succeeds" {
  seed_legacy
  : > "$PROJECT_DIR/.ccanvil/ideas-pending.log"
  run bash "$SCRIPT" provider-heal-routing-rename --apply --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drained.synced == 0' >/dev/null
  echo "$output" | jq -e '.drained.failed == 0' >/dev/null
}

@test "BTS-324 AC-4: --apply with pending log + no auth → rename still durable, drained.failed > 0" {
  seed_legacy
  # Append a dispatchable entry that will fail without LINEAR_API_KEY (no auth).
  bash "$SCRIPT" idea-pending-append \
    --op ticket.transition --id BTS-9999 --role done --project-dir "$PROJECT_DIR" >/dev/null
  cfg="$PROJECT_DIR/.claude/ccanvil.local.json"
  # Force unset auth so replay cannot succeed.
  run env -u LINEAR_API_KEY bash "$SCRIPT" provider-heal-routing-rename --apply --project-dir "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  # Rename happened regardless of replay outcome.
  jq -e '.integrations.routing.idea == "linear"' "$cfg" >/dev/null
  jq -e '.integrations.routing | has("ticket") | not' "$cfg" >/dev/null
  # drained.failed > 0 because the replay couldn't dispatch.
  echo "$output" | jq -e '.drained.failed > 0' >/dev/null
}
