#!/usr/bin/env bats
# BTS-240 Step 1+2: cmd_extract markdown branch — AC-1, AC-2, AC-3, AC-8

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
  FIXTURES="$REPO_ROOT/hub/tests/fixtures/manifest"
}

@test "extract markdown: emits one JSON object per manifest block" {
  set -e
  run bash "$SCRIPT" extract "$FIXTURES/markdown-happy.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array" and length == 1'
}

@test "extract markdown: id falls back to basename when not declared in body" {
  set -e
  run bash "$SCRIPT" extract "$FIXTURES/markdown-happy.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].id == "markdown-happy"'
}

@test "extract markdown: scalar fields stay scalars (purpose)" {
  set -e
  run bash "$SCRIPT" extract "$FIXTURES/markdown-happy.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].purpose | type == "string"'
  echo "$output" | jq -e '.[0].purpose == "Happy-path markdown manifest fixture"'
}

@test "extract markdown: scalar routes-by preserved" {
  set -e
  run bash "$SCRIPT" extract "$FIXTURES/markdown-happy.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0]."routes-by" == "/markdown-happy"'
}

@test "extract markdown: input is array with both scalar entries" {
  set -e
  run bash "$SCRIPT" extract "$FIXTURES/markdown-happy.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].input | type == "array" and length == 2'
  echo "$output" | jq -e '.[0].input[0] == "stdin"'
  echo "$output" | jq -e '.[0].input[1] == "cli-flags"'
}

@test "extract markdown: failure-mode preserved as pipe-delimited strings (AC-8)" {
  set -e
  run bash "$SCRIPT" extract "$FIXTURES/markdown-happy.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0]."failure-mode" | type == "array" and length == 2'
  echo "$output" | jq -e '.[0]."failure-mode"[0] == "missing-input | exit=1 | visible=stderr-message"'
  echo "$output" | jq -e '.[0]."failure-mode"[1] == "parse-error | exit=2 | visible=stderr-message | mitigation=retry-with-fallback"'
}

@test "extract markdown: anchor + contract are arrays (single-element)" {
  set -e
  run bash "$SCRIPT" extract "$FIXTURES/markdown-happy.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].anchor | type == "array" and length == 1'
  echo "$output" | jq -e '.[0].contract | type == "array" and length == 1'
  echo "$output" | jq -e '.[0].anchor[0] == "BTS-240 (origin)"'
}

@test "extract markdown: emits [] for file with no frontmatter (AC-2)" {
  set -e
  no_fm="$BATS_TEST_TMPDIR/no-frontmatter.md"
  printf '# Heading\n\nNo frontmatter here.\n' > "$no_fm"
  run bash "$SCRIPT" extract "$no_fm"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array" and length == 0'
}

@test "extract markdown: emits [] for frontmatter without manifest key (AC-2)" {
  set -e
  no_mf="$BATS_TEST_TMPDIR/no-manifest.md"
  cat > "$no_mf" <<'EOF'
---
name: foo
description: "no manifest key here"
---

# Body
EOF
  run bash "$SCRIPT" extract "$no_mf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array" and length == 0'
}

@test "extract markdown: malformed yaml emits MALFORMED + exit 2 (AC-3)" {
  malformed="$BATS_TEST_TMPDIR/malformed.md"
  # Frontmatter opens with --- but never closes.
  cat > "$malformed" <<'EOF'
---
name: broken
manifest:
  purpose: never-closes
EOF
  run bash "$SCRIPT" extract "$malformed"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qE '^MALFORMED:'
}

@test "extract markdown: explicit id: in manifest body overrides basename" {
  set -e
  custom_id="$BATS_TEST_TMPDIR/custom.md"
  cat > "$custom_id" <<'EOF'
---
manifest:
  id: my_custom_id
  purpose: id override fixture
  input:
    - x
  output:
    - y
  side-effect:
    - z
  failure-mode:
    - "f | exit=0 | visible=none"
  contract:
    - c
  anchor:
    - a
---

body
EOF
  run bash "$SCRIPT" extract "$custom_id"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].id == "my_custom_id"'
}
