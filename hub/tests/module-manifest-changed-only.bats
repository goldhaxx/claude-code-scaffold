#!/usr/bin/env bats
# BTS-383 AC-4/AC-5: validate --changed-only [--since <ref>] scopes drift
# detection to the git-diff ∩ allowlist subset.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
  FIXTURES="$REPO_ROOT/hub/tests/fixtures/manifest"
}

# Helper: build a project with two manifest-blocked files committed to a
# fresh git history. Returns proj root via $proj.
_make_proj() {
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.ccanvil/scripts" "$proj/.ccanvil"
  cp "$FIXTURES/two-blocks.sh" "$proj/.ccanvil/scripts/file-a.sh"
  cp "$FIXTURES/two-blocks.sh" "$proj/.ccanvil/scripts/file-b.sh"
  printf '%s\n%s\n' \
    ".ccanvil/scripts/file-a.sh:func_one" \
    ".ccanvil/scripts/file-b.sh:func_one" \
    > "$proj/.ccanvil/manifest-allowlist.txt"
  cd "$proj"
  git init -q
  git -c commit.gpgsign=false -c user.name=t -c user.email=t@t add -A
  git -c commit.gpgsign=false -c user.name=t -c user.email=t@t commit -q -m baseline
}

@test "AC-4: --changed-only --since HEAD emits scanned_files = git-diff ∩ allowlist" {
  set -e
  _make_proj
  # Modify only file-a.sh
  printf '\n# trailing comment\n' >> .ccanvil/scripts/file-a.sh
  run bash "$SCRIPT" validate --changed-only --since HEAD --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scanned_files | type == "array"'
  echo "$output" | jq -e '.scanned_files | length == 1'
  echo "$output" | jq -e '.scanned_files[0] | endswith("file-a.sh")'
  # coverage reflects scanned subset
  echo "$output" | jq -e '.coverage.covered == 1'
  echo "$output" | jq -e '.coverage.total == 1'
}

@test "AC-5: --changed-only with empty diff emits zero-coverage envelope (not error)" {
  set -e
  _make_proj
  # No changes after baseline.
  run bash "$SCRIPT" validate --changed-only --since HEAD --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scanned_files == []'
  echo "$output" | jq -e '.coverage.covered == 0'
  echo "$output" | jq -e '.coverage.total == 0'
  echo "$output" | jq -e '.status == "ok"'
}

@test "AC-5: --changed-only filters non-allowlisted changed files" {
  set -e
  _make_proj
  # Modify file-a.sh AND a non-allowlisted file.
  printf '\n# trailing\n' >> .ccanvil/scripts/file-a.sh
  echo 'note' > note.md
  git -c commit.gpgsign=false -c user.name=t -c user.email=t@t add note.md
  run bash "$SCRIPT" validate --changed-only --since HEAD --json
  [ "$status" -eq 0 ]
  # Only allowlisted-and-changed file scanned.
  echo "$output" | jq -e '.scanned_files | length == 1'
  echo "$output" | jq -e '.scanned_files[0] | endswith("file-a.sh")'
}

@test "AC-4: --changed-only completes in <5s on 1-file fixture diff" {
  set -e
  _make_proj
  printf '\n# trailing\n' >> .ccanvil/scripts/file-a.sh
  start_ms=$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000')
  run bash "$SCRIPT" validate --changed-only --since HEAD --json
  end_ms=$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000')
  elapsed_ms=$((end_ms - start_ms))
  echo "perf: ${elapsed_ms}ms (bound 5000)" >&2
  [ "$status" -eq 0 ]
  [ "$elapsed_ms" -lt 5000 ]
}

@test "AC-4: --changed-only without --since defaults to HEAD~1" {
  set -e
  _make_proj
  # Add a second commit that modifies file-a only.
  printf '\n# second-commit change\n' >> .ccanvil/scripts/file-a.sh
  git -c commit.gpgsign=false -c user.name=t -c user.email=t@t add -A
  git -c commit.gpgsign=false -c user.name=t -c user.email=t@t commit -q -m second
  run bash "$SCRIPT" validate --changed-only --json
  [ "$status" -eq 0 ]
  # default --since HEAD~1 → diff between baseline and HEAD picks up file-a only.
  echo "$output" | jq -e '.scanned_files | length == 1'
  echo "$output" | jq -e '.scanned_files[0] | endswith("file-a.sh")'
}
