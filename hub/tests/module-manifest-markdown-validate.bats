#!/usr/bin/env bats
# BTS-240 Step 3+4: cmd_validate markdown branch — AC-4, AC-5

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
  FIXTURES="$REPO_ROOT/hub/tests/fixtures/manifest"

  # Build a throwaway project layout so allowlist paths resolve cleanly.
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil/scripts" "$proj/hub/tests/fixtures/manifest"
  cp "$SCRIPT" "$proj/.ccanvil/scripts/module-manifest.sh"
  cp "$FIXTURES/markdown-minimal.md" "$proj/hub/tests/fixtures/manifest/markdown-minimal.md"
}

@test "validate markdown: file-level entry passes (AC-4 base)" {
  set -e
  echo "hub/tests/fixtures/manifest/markdown-minimal.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.covered == 1'
  echo "$output" | jq -e '.coverage.total == 1'
  echo "$output" | jq -e '.drift | length == 0'
}

@test "validate markdown: id falls back to basename .md (AC-4)" {
  set -e
  # No id: declared in body — id should be "markdown-minimal" (basename .md).
  echo "hub/tests/fixtures/manifest/markdown-minimal.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok"'
}

@test "validate markdown: missing failure-mode marker is SKIPPED (AC-5)" {
  set -e
  # markdown-minimal.md declares failure-mode but the body has no
  # `# @failure-mode: ...` markers (markdown body is prose, not code).
  # Without the marker-skip patch, this would fail with
  # missing-failure-mode-marker. With it, validate must exit 0.
  echo "hub/tests/fixtures/manifest/markdown-minimal.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate
  [ "$status" -eq 0 ]
  ! echo "$output$stderr" | grep -q "missing-failure-mode-marker"
}

@test "validate markdown: missing side-effect marker is SKIPPED (AC-5)" {
  set -e
  # Same logic for side-effect markers.
  echo "hub/tests/fixtures/manifest/markdown-minimal.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate
  [ "$status" -eq 0 ]
  ! echo "$output$stderr" | grep -q "missing-side-effect-marker"
}

@test "validate markdown: declared caller (path form) is found in target file" {
  set -e
  # Create a target markdown file that "calls" the primitive.
  mkdir -p "$proj/.claude/commands"
  cat > "$proj/.claude/commands/caller-fixture.md" <<'EOF'
# Caller fixture

Invokes with-caller somewhere in its body.
EOF
  cat > "$proj/hub/tests/fixtures/manifest/with-caller.md" <<'EOF'
---
manifest:
  purpose: Has a path-form caller
  input:
    - x
  output:
    - y
  caller:
    - .claude/commands/caller-fixture.md
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
  echo "hub/tests/fixtures/manifest/with-caller.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.coverage.covered == 1'
}

@test "validate markdown: declared caller pointing at missing file fails" {
  set -e
  cat > "$proj/hub/tests/fixtures/manifest/missing-caller.md" <<'EOF'
---
manifest:
  purpose: Has a path-form caller that does not exist
  input:
    - x
  output:
    - y
  caller:
    - .claude/commands/does-not-exist.md
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
  echo "hub/tests/fixtures/manifest/missing-caller.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate
  [ "$status" -eq 2 ]
  echo "$output$stderr" | grep -q "caller-not-found"
}

@test "validate markdown: depends-on present in body passes" {
  set -e
  cat > "$proj/hub/tests/fixtures/manifest/with-deps.md" <<'EOF'
---
manifest:
  purpose: Depends on something that's in the body
  input:
    - x
  output:
    - y
  depends-on:
    - special_helper_word
  side-effect:
    - z
  failure-mode:
    - "f | exit=1 | visible=none"
  contract:
    - c
  anchor:
    - BTS-240
---

# Body

This file mentions special_helper_word somewhere in its prose.
EOF
  echo "hub/tests/fixtures/manifest/with-deps.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate
  [ "$status" -eq 0 ]
}

@test "validate markdown: depends-on absent from body fails" {
  set -e
  cat > "$proj/hub/tests/fixtures/manifest/missing-deps.md" <<'EOF'
---
manifest:
  purpose: Depends on something not in the body
  input:
    - x
  output:
    - y
  depends-on:
    - totally_absent_token
  side-effect:
    - z
  failure-mode:
    - "f | exit=1 | visible=none"
  contract:
    - c
  anchor:
    - BTS-240
---

# Body

This file does not mention the dependency.
EOF
  echo "hub/tests/fixtures/manifest/missing-deps.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate
  [ "$status" -eq 2 ]
  echo "$output$stderr" | grep -q "depends-on-not-found"
}

@test "validate markdown: missing required key still fails for .md" {
  set -e
  # Missing 'purpose' should still fail — marker-skip does NOT bypass
  # required-key validation.
  no_purpose="$proj/hub/tests/fixtures/manifest/no-purpose.md"
  cat > "$no_purpose" <<'EOF'
---
manifest:
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
    - a
---

body
EOF
  echo "hub/tests/fixtures/manifest/no-purpose.md" > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  run bash "$SCRIPT" validate
  [ "$status" -eq 2 ]
  echo "$output$stderr" | grep -q "missing-required-key"
  echo "$output$stderr" | grep -q "value=purpose"
}
