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

# AC-9: filter hub-managed files via .ccanvil/ccanvil.lock (BTS-267 dogfood-surfaced).
@test "seed-allowlist: hub-managed files (in ccanvil.lock) are filtered out" {
  set -e
  node="$BATS_TEST_TMPDIR/lockfile-node"
  mkdir -p "$node/.ccanvil/scripts" "$node/.ccanvil"
  cat > "$node/.ccanvil/scripts/hub-managed.sh" <<'EOSH'
#!/usr/bin/env bash
cmd_alpha() { echo a; }
EOSH
  cat > "$node/.ccanvil/scripts/node-owned.sh" <<'EOSH'
#!/usr/bin/env bash
cmd_beta() { echo b; }
EOSH
  cat > "$node/.ccanvil/ccanvil.lock" <<'EOJSON'
{
  "hub_source": "test",
  "files": {
    ".ccanvil/scripts/hub-managed.sh": {"hash": "abc"}
  }
}
EOJSON
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  # hub-managed.sh:cmd_alpha is in the lockfile — must NOT appear.
  [ "$(echo "$entries" | grep -cF '.ccanvil/scripts/hub-managed.sh')" -eq 0 ]
  # node-owned.sh:cmd_beta is NOT in the lockfile — must appear.
  echo "$entries" | grep -qF '.ccanvil/scripts/node-owned.sh:cmd_beta'
}

# AC-9: lockfile absence falls back to no filtering (preserves AC-1 behavior).
@test "seed-allowlist: missing ccanvil.lock falls back to unfiltered seed" {
  set -e
  node="$BATS_TEST_TMPDIR/no-lockfile-node"
  mkdir -p "$node/.ccanvil/scripts"
  cat > "$node/.ccanvil/scripts/foo.sh" <<'EOSH'
#!/usr/bin/env bash
cmd_x() { echo x; }
EOSH
  # No ccanvil.lock — should still propose foo.sh:cmd_x.
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  echo "$entries" | grep -qF '.ccanvil/scripts/foo.sh:cmd_x'
}

# AC-2: dedup against existing allowlist — emit only NEW candidates.
@test "seed-allowlist: dedup against existing .ccanvil/manifest-allowlist.txt" {
  set -e
  node="$BATS_TEST_TMPDIR/dedup-node"
  mkdir -p "$node/.ccanvil/scripts" "$node/.ccanvil"
  cat > "$node/.ccanvil/scripts/foo.sh" <<'EOSH'
#!/usr/bin/env bash
cmd_alpha() { echo a; }
cmd_beta() { echo b; }
EOSH
  cat > "$node/.ccanvil/manifest-allowlist.txt" <<'EOAL'
# Existing allowlist
.ccanvil/scripts/foo.sh:cmd_alpha
EOAL
  run bash "$SCRIPT" seed-allowlist --dir "$node"
  [ "$status" -eq 0 ]
  entries=$(echo "$output" | grep -vE '^\s*(#|$)')
  # cmd_alpha already in allowlist — should be filtered out (count must be 0).
  [ "$(echo "$entries" | grep -cF '.ccanvil/scripts/foo.sh:cmd_alpha')" -eq 0 ]
  # cmd_beta is new — should be emitted.
  echo "$entries" | grep -qF '.ccanvil/scripts/foo.sh:cmd_beta'
}
