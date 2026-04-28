#!/usr/bin/env bats
# BTS-239 Step 10: drift-guard with mutation tests — AC-8.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/.ccanvil/scripts" "$PROJ/.ccanvil/state"
  # Stage a single greenfield fixture as the only source.
  cp "$REPO_ROOT/hub/tests/fixtures/manifest/valid-deep.sh" "$PROJ/.ccanvil/scripts/valid-deep.sh"
  echo ".ccanvil/scripts/valid-deep.sh:valid_deep_func" > "$PROJ/.ccanvil/manifest-allowlist.txt"
}

@test "drift-guard clean state: validate exits 0" {
  set -e
  cd "$PROJ"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.covered == 1'
  echo "$output" | jq -e '.status == "ok"'
}

@test "drift-guard mutation: corrupt caller field → exit 2 with DRIFT stderr" {
  cd "$PROJ"
  # Initial: clean.
  bash "$SCRIPT" validate --json >/dev/null
  # Mutation: replace `caller: referenced_caller` with a non-existent caller.
  sed -i.bak 's/^# caller: referenced_caller$/# caller: ghost_caller_xyz/' .ccanvil/scripts/valid-deep.sh
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "DRIFT" ]]
  [[ "$output" =~ "caller-not-found" ]]
  [[ "$output" =~ "ghost_caller_xyz" ]]
  # Revert.
  mv .ccanvil/scripts/valid-deep.sh.bak .ccanvil/scripts/valid-deep.sh
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
}

@test "drift-guard mutation: remove failure-mode marker → exit 2 with missing-failure-mode-marker" {
  cd "$PROJ"
  bash "$SCRIPT" validate --json >/dev/null
  # Remove the @failure-mode marker line from the body.
  sed -i.bak '/^[[:space:]]*#[[:space:]]*@failure-mode:[[:space:]]*foo/d' .ccanvil/scripts/valid-deep.sh
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing-failure-mode-marker" ]]
  mv .ccanvil/scripts/valid-deep.sh.bak .ccanvil/scripts/valid-deep.sh
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
}

@test "drift-guard mutation: remove side-effect marker → exit 2 with missing-side-effect-marker" {
  cd "$PROJ"
  bash "$SCRIPT" validate --json >/dev/null
  sed -i.bak '/^[[:space:]]*#[[:space:]]*@side-effect:[[:space:]]*writes-tmp/d' .ccanvil/scripts/valid-deep.sh
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing-side-effect-marker" ]]
  mv .ccanvil/scripts/valid-deep.sh.bak .ccanvil/scripts/valid-deep.sh
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
}

@test "drift-guard mutation: remove required key (purpose) → exit 2 with missing-required-key" {
  cd "$PROJ"
  bash "$SCRIPT" validate --json >/dev/null
  sed -i.bak '/^# purpose:/d' .ccanvil/scripts/valid-deep.sh
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing-required-key" ]]
  [[ "$output" =~ "purpose" ]]
  mv .ccanvil/scripts/valid-deep.sh.bak .ccanvil/scripts/valid-deep.sh
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
}

_md_proj_setup() {
  MD_PROJ="$BATS_TEST_TMPDIR/md_proj"
  mkdir -p "$MD_PROJ/.ccanvil/scripts" \
           "$MD_PROJ/.claude/skills/seedskill" \
           "$MD_PROJ/.claude/rules" \
           "$MD_PROJ/.claude/agents" \
           "$MD_PROJ/.claude/commands"
  cp "$REPO_ROOT/.ccanvil/scripts/module-manifest.sh" "$MD_PROJ/.ccanvil/scripts/"
}

_write_full_md_manifest() {
  local target="$1"
  cat > "$target" <<'EOF'
---
manifest:
  purpose: drift-guard mutation fixture
  input:
    - x
  output:
    - y
  side-effect:
    - z
  failure-mode:
    - "f | exit=1 | visible=none"
  contract:
    - c
  anchor:
    - BTS-240
---

body
EOF
}

@test "drift-guard markdown skill: drop purpose → missing-required-key" {
  _md_proj_setup
  _write_full_md_manifest "$MD_PROJ/.claude/skills/seedskill/SKILL.md"
  echo ".claude/skills/seedskill/SKILL.md:SKILL" > "$MD_PROJ/.ccanvil/manifest-allowlist.txt"
  cd "$MD_PROJ"
  run bash "$SCRIPT" validate
  [ "$status" -eq 0 ]
  # Mutation: drop the purpose line.
  sed -i.bak '/^  purpose:/d' .claude/skills/seedskill/SKILL.md
  run bash "$SCRIPT" validate
  [ "$status" -eq 2 ]
  echo "$output$stderr" | grep -q "missing-required-key"
  echo "$output$stderr" | grep -q "value=purpose"
}

@test "drift-guard markdown rule: caller pointing at nonexistent file → caller-not-found" {
  _md_proj_setup
  _write_full_md_manifest "$MD_PROJ/.claude/rules/seedrule.md"
  echo ".claude/rules/seedrule.md" > "$MD_PROJ/.ccanvil/manifest-allowlist.txt"
  cd "$MD_PROJ"
  run bash "$SCRIPT" validate
  [ "$status" -eq 0 ]
  # Mutation: inject a caller pointing at a nonexistent .md.
  sed -i.bak 's|^manifest:$|manifest:\
  caller:\
    - .claude/commands/ghost.md|' .claude/rules/seedrule.md
  run bash "$SCRIPT" validate
  [ "$status" -eq 2 ]
  echo "$output$stderr" | grep -q "caller-not-found"
}

@test "drift-guard markdown agent: depends-on absent from body → depends-on-not-found" {
  _md_proj_setup
  _write_full_md_manifest "$MD_PROJ/.claude/agents/seedagent.md"
  echo ".claude/agents/seedagent.md" > "$MD_PROJ/.ccanvil/manifest-allowlist.txt"
  cd "$MD_PROJ"
  run bash "$SCRIPT" validate
  [ "$status" -eq 0 ]
  # Mutation: inject a depends-on token not present in the body.
  sed -i.bak 's|^manifest:$|manifest:\
  depends-on:\
    - phantom_dependency_token|' .claude/agents/seedagent.md
  run bash "$SCRIPT" validate
  [ "$status" -eq 2 ]
  echo "$output$stderr" | grep -q "depends-on-not-found"
}

@test "drift-guard markdown command: id mismatch → manifest-not-found" {
  _md_proj_setup
  _write_full_md_manifest "$MD_PROJ/.claude/commands/seedcmd.md"
  # Allowlist asks for id "wrong-id" but manifest body has no id (defaults
  # to basename "seedcmd"). Lookup will fail.
  echo ".claude/commands/seedcmd.md:wrong-id" > "$MD_PROJ/.ccanvil/manifest-allowlist.txt"
  cd "$MD_PROJ"
  run bash "$SCRIPT" validate
  [ "$status" -eq 2 ]
  echo "$output$stderr" | grep -q "manifest-not-found"
}

@test "drift-guard production allowlist clean (regression guard against this branch)" {
  set -e
  cd "$REPO_ROOT"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.covered == .coverage.total'
}
