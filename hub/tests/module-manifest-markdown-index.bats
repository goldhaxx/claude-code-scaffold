#!/usr/bin/env bats
# BTS-240 Step 5: cmd_index walks markdown source dirs — AC-6

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"

  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil/scripts"
  mkdir -p "$proj/.claude/skills/foo" "$proj/.claude/rules" "$proj/.claude/agents" "$proj/.claude/commands"
  cp "$SCRIPT" "$proj/.ccanvil/scripts/module-manifest.sh"
}

_write_md_manifest() {
  local target="$1"
  cat > "$target" <<'EOF'
---
manifest:
  purpose: Markdown index test fixture
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

@test "index: walks .claude/skills/<n>/SKILL.md" {
  set -e
  _write_md_manifest "$proj/.claude/skills/foo/SKILL.md"
  cd "$proj"
  run bash "$SCRIPT" index
  [ "$status" -eq 0 ]
  jq -e '.[".claude/skills/foo/SKILL.md:SKILL"]' .ccanvil/state/manifests.json
}

@test "index: walks .claude/rules/*.md" {
  set -e
  _write_md_manifest "$proj/.claude/rules/bar.md"
  cd "$proj"
  run bash "$SCRIPT" index
  [ "$status" -eq 0 ]
  jq -e '.[".claude/rules/bar.md:bar"]' .ccanvil/state/manifests.json
}

@test "index: walks .claude/agents/*.md" {
  set -e
  _write_md_manifest "$proj/.claude/agents/baz.md"
  cd "$proj"
  run bash "$SCRIPT" index
  [ "$status" -eq 0 ]
  jq -e '.[".claude/agents/baz.md:baz"]' .ccanvil/state/manifests.json
}

@test "index: walks .claude/commands/*.md" {
  set -e
  _write_md_manifest "$proj/.claude/commands/qux.md"
  cd "$proj"
  run bash "$SCRIPT" index
  [ "$status" -eq 0 ]
  jq -e '.[".claude/commands/qux.md:qux"]' .ccanvil/state/manifests.json
}

@test "index: query finds markdown manifest by depends-on (AC-6)" {
  set -e
  cat > "$proj/.claude/commands/qux.md" <<'EOF'
---
manifest:
  purpose: Has a unique depends-on for query test
  input:
    - x
  output:
    - y
  depends-on:
    - linear-query.sh
  side-effect:
    - z
  failure-mode:
    - "f | exit=1 | visible=none"
  contract:
    - c
  anchor:
    - BTS-240
---

calls linear-query.sh
EOF
  cd "$proj"
  run bash "$SCRIPT" query 'depends-on:linear-query.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length >= 1'
  echo "$output" | jq -e '.[0].id == "qux"'
}
