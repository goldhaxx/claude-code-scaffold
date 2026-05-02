#!/usr/bin/env bats
# BTS-267: cmd_seed_allowlist — proposes initial manifest allowlist for a downstream-node substrate.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
}

# AC-4: nonexistent --dir → exit 2 with stderr error.
@test "seed-allowlist: nonexistent --dir exits 2 with directory-not-found stderr" {
  run bash "$SCRIPT" seed-allowlist --dir /nonexistent/path/$$
  [ "$status" -eq 2 ]
  [[ "$output" =~ "directory not found" ]]
}

# AC-3: empty substrate (no .ccanvil/ and no .claude/) → exit 0, empty stdout.
@test "seed-allowlist: empty node directory exits 0 with no entries" {
  empty_node="$BATS_TEST_TMPDIR/empty-node"
  mkdir -p "$empty_node"
  run bash "$SCRIPT" seed-allowlist --dir "$empty_node"
  [ "$status" -eq 0 ]
  # No proposed entries — stdout may be empty or comment-only.
  [[ -z "$(echo "$output" | grep -vE '^\s*(#|$)')" ]]
}

# AC-1/AC-6: mega-script with cmd_* functions emits one path:fn entry per function.
@test "seed-allowlist: mega-script emits path:fn entries (one per cmd_*)" {
  set -e
  node="$BATS_TEST_TMPDIR/megascript-node"
  mkdir -p "$node/.ccanvil/scripts"
  cat > "$node/.ccanvil/scripts/foo.sh" <<'EOSH'
#!/usr/bin/env bash
cmd_alpha() { echo a; }
cmd_beta() { echo b; }
EOSH
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  # Filter out comments + blank lines for assertions.
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  echo "$entries" | grep -qF '.ccanvil/scripts/foo.sh:cmd_alpha'
  echo "$entries" | grep -qF '.ccanvil/scripts/foo.sh:cmd_beta'
  # Two entries total for the mega-script.
  [ "$(echo "$entries" | wc -l | tr -d ' ')" -eq 2 ]
}

# AC-1/AC-6: single-purpose script (no cmd_*) emits bare path entry.
@test "seed-allowlist: single-purpose script emits bare path (no :fn)" {
  set -e
  node="$BATS_TEST_TMPDIR/single-node"
  mkdir -p "$node/.ccanvil/scripts"
  cat > "$node/.ccanvil/scripts/bar.sh" <<'EOSH'
#!/usr/bin/env bash
echo "imperative single-purpose script"
EOSH
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  echo "$entries" | grep -qE '^\.ccanvil/scripts/bar\.sh$'
  [ "$(echo "$entries" | wc -l | tr -d ' ')" -eq 1 ]
}

# AC-6: mixed mega-script and single-purpose in same node — both forms emitted.
@test "seed-allowlist: mixed mega-script + single-purpose emits both forms" {
  set -e
  node="$BATS_TEST_TMPDIR/mixed-node"
  mkdir -p "$node/.ccanvil/scripts"
  cat > "$node/.ccanvil/scripts/mega.sh" <<'EOSH'
#!/usr/bin/env bash
cmd_one() { echo 1; }
EOSH
  cat > "$node/.ccanvil/scripts/single.sh" <<'EOSH'
#!/usr/bin/env bash
echo single
EOSH
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  echo "$entries" | grep -qF '.ccanvil/scripts/mega.sh:cmd_one'
  echo "$entries" | grep -qE '^\.ccanvil/scripts/single\.sh$'
}

# AC-1: skill SKILL.md emits path:<id> using frontmatter name field.
@test "seed-allowlist: skill SKILL.md emits path:<name>" {
  set -e
  node="$BATS_TEST_TMPDIR/skill-node"
  mkdir -p "$node/.claude/skills/foo"
  cat > "$node/.claude/skills/foo/SKILL.md" <<'EOMD'
---
name: foo
description: A test skill
---
body
EOMD
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  echo "$entries" | grep -qE '^\.claude/skills/foo/SKILL\.md:foo$'
}

# AC-1: rules/agents/commands emit bare path (basename matches id).
@test "seed-allowlist: rule/agent/command markdown emits bare path" {
  set -e
  node="$BATS_TEST_TMPDIR/md-node"
  mkdir -p "$node/.claude/rules" "$node/.claude/agents" "$node/.claude/commands"
  echo "# rule" > "$node/.claude/rules/example.md"
  echo "# agent" > "$node/.claude/agents/helper.md"
  echo "# command" > "$node/.claude/commands/dispatch.md"
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  echo "$entries" | grep -qE '^\.claude/rules/example\.md$'
  echo "$entries" | grep -qE '^\.claude/agents/helper\.md$'
  echo "$entries" | grep -qE '^\.claude/commands/dispatch\.md$'
}

# AC-1: hooks emit bare path (file-level).
@test "seed-allowlist: hooks emit bare path entries" {
  set -e
  node="$BATS_TEST_TMPDIR/hooks-node"
  mkdir -p "$node/.claude/hooks"
  echo "#!/usr/bin/env bash" > "$node/.claude/hooks/protect-foo.sh"
  echo "#!/usr/bin/env bash" > "$node/.claude/hooks/lint-bar.sh"
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  echo "$entries" | grep -qE '^\.claude/hooks/protect-foo\.sh$'
  echo "$entries" | grep -qE '^\.claude/hooks/lint-bar\.sh$'
}
