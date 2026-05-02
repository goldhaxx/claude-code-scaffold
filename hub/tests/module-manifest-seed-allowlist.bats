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
