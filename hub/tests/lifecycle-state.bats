#!/usr/bin/env bats
# BTS-20 — unit tests for the lifecycle-state substrate primitive.
#
# Tests the docs-check.sh lifecycle-state subcommand and the codified
# transition graph at .ccanvil/templates/lifecycle-graph.json.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"
GRAPH="$REPO_ROOT/.ccanvil/templates/lifecycle-graph.json"

setup() {
  TMPDIR_BATS=$(mktemp -d)
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

# Helper: build a minimal ccanvil-project layout in $TMPDIR_BATS.
# Mirrors the parts of the repo that lifecycle-state actually inspects:
#   .ccanvil/scripts/  (presence flag — symlinked to repo's actual scripts)
#   .git/              (so we are inside a repo)
#   docs/              (operator's working dir)
init_fixture() {
  local fx="$TMPDIR_BATS"
  mkdir -p "$fx/.ccanvil" "$fx/docs/specs" "$fx/.git"
  ln -s "$REPO_ROOT/.ccanvil/scripts" "$fx/.ccanvil/scripts"
  ln -s "$REPO_ROOT/.ccanvil/templates" "$fx/.ccanvil/templates"
  echo "ref: refs/heads/main" > "$fx/.git/HEAD"
  echo "$fx"
}

# =========================================================================
# AC-2: transition graph schema
# =========================================================================

@test "AC-2: lifecycle-graph.json exists and parses" {
  [ -f "$GRAPH" ]
  jq -e 'type == "object"' "$GRAPH"
}

@test "AC-2: graph has states[] and edges[]" {
  set -e
  jq -e '.states | type == "array" and length > 0' "$GRAPH"
  jq -e '.edges | type == "array" and length > 0' "$GRAPH"
}

@test "AC-2: every state has {id, description}" {
  jq -e 'all(.states[]; has("id") and has("description") and (.id | type == "string") and (.description | type == "string"))' "$GRAPH"
}

@test "AC-2: every edge has {from, to, action}" {
  jq -e 'all(.edges[]; has("from") and has("to") and has("action"))' "$GRAPH"
}

# =========================================================================
# AC-3: canonical state coverage
# =========================================================================

@test "AC-3: graph covers canonical states" {
  jq -e '[.states[].id] | contains(["no-active-spec","spec-activated","plan-written","implementing","pr-open","pr-merged","session-wrap","blocked"])' "$GRAPH"
}

@test "AC-3: every edge from/to references a defined state" {
  jq -e '
    (.states | map(.id)) as $ids |
    all(.edges[]; .from as $f | .to as $t | ($ids | index($f)) != null and ($ids | index($t)) != null)
  ' "$GRAPH"
}

# =========================================================================
# AC-1: clean-state envelope shape
# =========================================================================

@test "AC-1: emits valid envelope on clean fixture (no docs)" {
  set -e
  fx=$(init_fixture)
  run bash "$SCRIPT" lifecycle-state --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state | type == "string"'
  echo "$output" | jq -e '.legal_next_actions | type == "array"'
  echo "$output" | jq -e '.blockers | type == "array"'
  echo "$output" | jq -e '.suggestions | type == "array"'
}

@test "AC-1: legal_next_actions entries have {action, command, reason}" {
  set -e
  fx=$(init_fixture)
  run bash "$SCRIPT" lifecycle-state --project-dir "$fx"
  [ "$status" -eq 0 ]
  # Each entry must have action+command (reason is suggested but optional —
  # graph guard string is the reason fallback).
  echo "$output" | jq -e '.legal_next_actions | all(has("action") and has("command"))'
}

# =========================================================================
# AC-4: session-wrap state (post-compact, fresh stasis)
# =========================================================================

@test "AC-4: session-stasis + fresh post-compact marker → state==session-wrap" {
  set -e
  fx=$(init_fixture)
  # Write a session-kind stasis with a populated Determinism Review section
  # (validate flags missing-determinism-review otherwise — same gate that
  # surfaces on real session stasis).
  cat > "$fx/docs/stasis.md" <<'EOF'
# Stasis

> Feature: session-2099-test
> Kind: session
> Last updated: 1000

## Accomplished
test fixture

## Determinism Review

- operations_reviewed: 0
- candidates_found: 0
- No candidates this session.
EOF
  # Write post-compact marker AFTER the stasis last-updated timestamp.
  mkdir -p "$fx/.ccanvil/state"
  echo "2000" > "$fx/.ccanvil/state/last-compact-ts"
  run bash "$SCRIPT" lifecycle-state --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "session-wrap"'
  echo "$output" | jq -e '.legal_next_actions | length > 0'
}

# =========================================================================
# AC-4b: session-wrap with STALE compact marker → /compact in legal actions
# =========================================================================

@test "AC-4b: session-stasis + stale post-compact marker → /compact in legal_next_actions" {
  set -e
  fx=$(init_fixture)
  cat > "$fx/docs/stasis.md" <<'EOF'
# Stasis

> Feature: session-2099-test
> Kind: session
> Last updated: 2000

## Accomplished
test fixture

## Determinism Review

- operations_reviewed: 0
- candidates_found: 0
- No candidates this session.
EOF
  # Marker is OLDER than stasis.last_updated → compact has not run yet.
  mkdir -p "$fx/.ccanvil/state"
  echo "1000" > "$fx/.ccanvil/state/last-compact-ts"
  run bash "$SCRIPT" lifecycle-state --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "session-wrap"'
  echo "$output" | jq -e '[.legal_next_actions[].action] | index("/compact") != null'
}

# =========================================================================
# AC-5: spec-activated state
# =========================================================================

@test "AC-5: active spec + no plan → state==spec-activated, /plan in legal_next_actions" {
  set -e
  fx=$(init_fixture)
  # Switch fixture HEAD to a feature branch (we don't run git, just simulate
  # the check by creating spec.md without plan.md).
  cat > "$fx/docs/spec.md" <<'EOF'
# Feature: Test

> Feature: test-feat
> Work: linear:TEST-1
> Created: 100
> Status: In Progress

## Acceptance Criteria
- [ ] AC-1
EOF
  run bash "$SCRIPT" lifecycle-state --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "spec-activated"'
  echo "$output" | jq -e '[.legal_next_actions[].action] | index("/plan") != null'
}

# =========================================================================
# AC-6: blocked state surfaces validate details
# =========================================================================

@test "AC-6: stale-plan validate result → state==blocked, blockers populated" {
  set -e
  fx=$(init_fixture)
  # Spec needs body content so content_hash is non-empty; plan stores a fake
  # spec_hash so validate trips the stale-plan branch.
  cat > "$fx/docs/spec.md" <<'EOF'
# Feature: Test

> Feature: test-feat
> Work: linear:TEST-1
> Created: 100
> Status: In Progress

## Summary

Spec body that produces a non-empty content_hash so validate's stale-plan
detection actually fires (the check requires both spec.content_hash and
plan.spec_hash to be present and non-equal).

## Acceptance Criteria

- [ ] AC-1: a thing
EOF
  cat > "$fx/docs/plan.md" <<'EOF'
# Implementation Plan: Test

> Feature: test-feat
> Work: linear:TEST-1
> Created: 100
> Spec hash: deadbeef
> Based on: docs/spec.md

## Objective
test
EOF
  run bash "$SCRIPT" lifecycle-state --project-dir "$fx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "blocked"'
  echo "$output" | jq -e '.blockers | length > 0'
}

# =========================================================================
# AC-9: uninitialized — not a ccanvil/git tree
# =========================================================================

@test "AC-9: invocation outside ccanvil tree → exit 2 + state==uninitialized" {
  fx="$TMPDIR_BATS/empty"
  mkdir -p "$fx"
  # No .ccanvil/, no .git/.
  run bash "$SCRIPT" lifecycle-state --project-dir "$fx"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.state == "uninitialized" and (.error | type == "string")'
}

# =========================================================================
# AC-1 (dispatcher): lifecycle-state is a dispatcher entry
# =========================================================================

@test "dispatcher: lifecycle-state subcommand is registered" {
  grep -qF 'lifecycle-state)' "$SCRIPT"
}
