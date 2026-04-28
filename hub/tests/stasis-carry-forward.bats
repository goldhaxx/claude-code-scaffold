#!/usr/bin/env bats
# BTS-232: /recall surfaces carry-forward determinism candidates from prior stasis.
# - cmd_stasis_carry_forward parses the prior stasis's `## Determinism Review`
#   section, extracts each candidate's slug, queries the current Linear idea
#   listing, and reports candidates with no matching `Determinism: <slug>` idea.
# - The /recall skill prose surfaces a `**Carry-forward determinism candidates:**`
#   section when count_carry_forward > 0.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"
RECALL_SKILL="$REPO_ROOT/.claude/skills/recall/SKILL.md"

setup() {
  TMPDIR_BATS=$(mktemp -d)
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

write_fixture() {
  local path="$TMPDIR_BATS/$1"
  shift
  cat > "$path"
  echo "$path"
}

# =========================================================================
# AC-1: all candidates matched → empty carry-forward
# =========================================================================

@test "AC-1: all candidates matched in idea listing → carry-forward empty" {
  set -e
  stasis_content=$(cat <<'EOF'
# Stasis

> Feature: session-test

## Accomplished

Things.

## Determinism Review

* operations_reviewed: 10
* candidates_found: 2
* **foo-bar**: did stuff. Should be deterministic. Impact: medium.
* **baz-qux**: more stuff. Should be deterministic. Impact: low.

## Cross-Session Patterns

Stuff.
EOF
)

  fixture=$(jq -n '[
    {id:"BTS-9001", title:"Determinism: foo-bar", status:"Backlog"},
    {id:"BTS-9002", title:"Determinism: baz-qux extras", status:"Backlog"}
  ]' | write_fixture issues.json)

  run bash "$SCRIPT" stasis-carry-forward --stasis-content - --input-json "$fixture" <<<"$stasis_content"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count_total == 2'
  echo "$output" | jq -e '.count_carry_forward == 0'
  echo "$output" | jq -e '[.candidates[] | select(.has_idea == true)] | length == 2'
}

# =========================================================================
# AC-2a: bolded-shape slug → matched
# =========================================================================

@test "AC-2a: bolded-shape **slug**: ... is extracted and matched" {
  set -e
  stasis_content=$(cat <<'EOF'
## Determinism Review

* operations_reviewed: 1
* candidates_found: 1
* **session-info-jq-fork**: forks jq four times. Should batch into one call. Impact: low.
EOF
)

  fixture=$(jq -n '[
    {id:"BTS-207", title:"Determinism: session-info-jq-fork", status:"Backlog"}
  ]' | write_fixture issues.json)

  run bash "$SCRIPT" stasis-carry-forward --stasis-content - --input-json "$fixture" <<<"$stasis_content"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count_total == 1'
  echo "$output" | jq -e '.count_carry_forward == 0'
  echo "$output" | jq -e '.candidates[0].slug == "session-info-jq-fork"'
  echo "$output" | jq -e '.candidates[0].idea_id == "BTS-207"'
}

# =========================================================================
# AC-2b: backtick-shape `tok1` → `tok2` ... is extracted and matched
# =========================================================================

@test "AC-2b: backtick-shape single-token slug matches idea via substring" {
  set -e
  stasis_content=$(cat <<'EOF'
## Determinism Review

* operations_reviewed: 1
* candidates_found: 1
* `simple-token`: did stuff. Should be deterministic. Impact: low.
EOF
)

  # Idea title contains the slug as a substring
  fixture=$(jq -n '[
    {id:"BTS-9011", title:"Determinism: simple-token with extras", status:"Backlog"}
  ]' | write_fixture issues.json)

  run bash "$SCRIPT" stasis-carry-forward --stasis-content - --input-json "$fixture" <<<"$stasis_content"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count_total == 1'
  echo "$output" | jq -e '.candidates[0].slug == "simple-token"'
  echo "$output" | jq -e '.candidates[0].has_idea == true'
  echo "$output" | jq -e '.candidates[0].idea_id == "BTS-9011"'
}

# =========================================================================
# AC-2c: backtick-shape multi-token bullet whose slug doesn't match
# any idea title — surfaces as carry-forward (the BTS-235 / session-7 case)
# =========================================================================

@test "AC-2c: backtick multi-token slug with no literal match → carry-forward" {
  set -e
  stasis_content=$(cat <<'EOF'
## Determinism Review

* operations_reviewed: 1
* candidates_found: 1
* `pr-cleanup` → `gh pr edit` → `gh pr ready` → `gh pr merge`: 4-step finalization sequence. Should be one verb. Impact: medium.
EOF
)

  # Operator captured under a DIFFERENT slug — this is the exact session-7
  # mismatch that BTS-232 is meant to surface.
  fixture=$(jq -n '[
    {id:"BTS-235", title:"Determinism: ship-finalize-wrapper-for-pr-cleanup-edit-ready-merge", status:"Backlog"}
  ]' | write_fixture issues.json)

  run bash "$SCRIPT" stasis-carry-forward --stasis-content - --input-json "$fixture" <<<"$stasis_content"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count_total == 1'
  echo "$output" | jq -e '.count_carry_forward == 1'
  echo "$output" | jq -e '.candidates[0].has_idea == false'
}

# =========================================================================
# AC-1/AC-3: mixed — some matched, some not → carry-forward set correctly
# =========================================================================

@test "AC-3: mixed candidates — only unmatched surface as carry-forward" {
  set -e
  stasis_content=$(cat <<'EOF'
## Determinism Review

* operations_reviewed: 5
* candidates_found: 3
* **alpha-thing**: matched. Impact: low.
* **beta-thing**: not matched. Impact: low.
* **gamma-thing**: not matched. Impact: low.
EOF
)

  fixture=$(jq -n '[
    {id:"BTS-8001", title:"Determinism: alpha-thing", status:"Backlog"}
  ]' | write_fixture issues.json)

  run bash "$SCRIPT" stasis-carry-forward --stasis-content - --input-json "$fixture" <<<"$stasis_content"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count_total == 3'
  echo "$output" | jq -e '.count_carry_forward == 2'
  # The two unmatched candidates surface
  echo "$output" | jq -e '[.candidates[] | select(.has_idea == false) | .slug] | sort == ["beta-thing","gamma-thing"]'
}

# =========================================================================
# AC-4: empty-state literal → no candidates, no error
# =========================================================================

@test "AC-4: 'No candidates this session.' literal → empty result" {
  set -e
  stasis_content=$(cat <<'EOF'
## Determinism Review

* operations_reviewed: 5
* candidates_found: 0
* No candidates this session.
EOF
)

  fixture=$(jq -n '[]' | write_fixture issues.json)

  run bash "$SCRIPT" stasis-carry-forward --stasis-content - --input-json "$fixture" <<<"$stasis_content"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count_total == 0'
  echo "$output" | jq -e '.count_carry_forward == 0'
  echo "$output" | jq -e '.candidates | length == 0'
}

# =========================================================================
# AC-5: no prior stasis → empty result with note, no error
# =========================================================================

@test "AC-5: empty stdin (simulating no prior stasis) → empty result" {
  set -e
  fixture=$(jq -n '[]' | write_fixture issues.json)

  # Empty stdin via /dev/null. The substrate falls through to artifact-read,
  # which on a non-stasis-bearing project_dir returns empty → note emitted.
  run bash "$SCRIPT" stasis-carry-forward --project-dir "$TMPDIR_BATS" --input-json "$fixture"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count_total == 0'
  echo "$output" | jq -e '.count_carry_forward == 0'
  echo "$output" | jq -e '.note != null'
}

# =========================================================================
# AC-2 metadata-skip: bolded `**operations_reviewed:**` and `**candidates_found:**`
# are post-extract filtered (BTS-232 live-dogfood fix)
# =========================================================================

@test "AC-2 bolded metadata bullets are filtered out post-extraction" {
  set -e
  stasis_content=$(cat <<'EOF'
## Determinism Review

* **operations_reviewed:** ~50 narrative
* **candidates_found:** 2
* **alpha-thing**: real candidate. Impact: low.
* **beta-thing**: another candidate. Impact: low.
EOF
)

  fixture=$(jq -n '[]' | write_fixture issues.json)
  run bash "$SCRIPT" stasis-carry-forward --stasis-content - --input-json "$fixture" <<<"$stasis_content"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count_total == 2'
  echo "$output" | jq -e '[.candidates[].slug] | sort == ["alpha-thing","beta-thing"]'
}

# =========================================================================
# AC-3 (skill prose): /recall references BTS-232 + has carry-forward block
# =========================================================================

@test "AC-3 lock: recall SKILL.md references BTS-232" {
  grep -q "BTS-232" "$RECALL_SKILL"
}

@test "AC-3 lock: recall SKILL.md calls stasis-carry-forward" {
  grep -q "stasis-carry-forward" "$RECALL_SKILL"
}

@test "AC-3 lock: recall SKILL.md mentions Carry-forward determinism candidates heading" {
  grep -qF "Carry-forward determinism candidates" "$RECALL_SKILL"
}

# =========================================================================
# Drift-guard: BTS-232 reference inline in docs-check.sh
# =========================================================================

@test "drift: BTS-232 referenced inline in docs-check.sh" {
  grep -q "BTS-232" "$SCRIPT"
}
