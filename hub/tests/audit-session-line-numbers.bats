#!/usr/bin/env bats
# BTS-133 — audit-session should emit real file:line from git diff hunks (not 0).

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
}

_init_repo() {
  local repo
  repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  printf '%s\n' "echo seed" > "$repo/seed.txt"
  git -C "$repo" add seed.txt
  git -C "$repo" commit -q -m "seed"
  echo "$repo"
}

@test "BTS-133 AC-1: single cp at line 1 of new file emits line: 1" {
  set -e
  local repo
  repo=$(_init_repo)

  # New file with cp on the very first line
  printf '%s\n' 'cp src/a dst/a' > "$repo/move.sh"
  git -C "$repo" add move.sh
  git -C "$repo" commit -q -m "add move.sh"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.patterns_found | length >= 1'
  echo "$output" | jq -e '.patterns_found[0].file == "move.sh"'
  echo "$output" | jq -e '.patterns_found[0].line == 1'
  rm -rf "$repo"
}

@test "BTS-133 AC-2: hunk @@ +50 — three consecutive cp lines emit 50, 51, 52" {
  set -e
  local repo
  repo=$(_init_repo)

  # Build a 49-line preamble of inert content, then 3 consecutive cp lines.
  {
    for i in $(seq 1 49); do printf 'echo line %s\n' "$i"; done
    printf '%s\n' 'cp x1 y1'
    printf '%s\n' 'cp x2 y2'
    printf '%s\n' 'cp x3 y3'
  } > "$repo/multi.sh"
  git -C "$repo" add multi.sh
  git -C "$repo" commit -q -m "add multi.sh with 3 cps"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  # Expect exactly 3 cp findings on this file at lines 50, 51, 52.
  local lines
  lines=$(echo "$output" | jq -r '[.patterns_found[] | select(.file == "multi.sh" and .pattern == "cp") | .line] | sort | join(",")')
  [ "$lines" = "50,51,52" ]
  rm -rf "$repo"
}

@test "BTS-133 AC-3: two separate hunks in one file — each finding uses its own hunk's line" {
  set -e
  local repo
  repo=$(_init_repo)

  # Initial file: 100 lines of inert content
  {
    for i in $(seq 1 100); do printf 'echo line %s\n' "$i"; done
  } > "$repo/two-hunks.sh"
  git -C "$repo" add two-hunks.sh
  git -C "$repo" commit -q -m "add two-hunks.sh seed"

  # Mutate: insert a cp near line 10 and another near line 80, far enough apart
  # that --unified=0 produces two separate hunks.
  {
    for i in $(seq 1 9); do printf 'echo line %s\n' "$i"; done
    printf '%s\n' 'cp early-x early-y'
    for i in $(seq 10 79); do printf 'echo line %s\n' "$i"; done
    printf '%s\n' 'cp late-x late-y'
    for i in $(seq 80 100); do printf 'echo line %s\n' "$i"; done
  } > "$repo/two-hunks.sh"
  git -C "$repo" add two-hunks.sh
  git -C "$repo" commit -q -m "insert 2 cps in distinct hunks"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  # Expect both findings; line numbers should be distinct and >0.
  local lines
  lines=$(echo "$output" | jq -r '[.patterns_found[] | select(.file == "two-hunks.sh" and .pattern == "cp") | .line] | sort | tostring')
  # First hunk inserts at line 10, second hunk inserts at line 81 (after 9 + 1 + 70 unchanged + 1 = 81 in new file).
  [ "$lines" = "[10,81]" ]
  rm -rf "$repo"
}

@test "BTS-133 AC-4: two files in same diff — line counters do not bleed across files" {
  set -e
  local repo
  repo=$(_init_repo)

  # File A: cp at line 1 of A.
  printf '%s\n' 'cp a-src a-dst' > "$repo/A.sh"
  # File B: 30 lines of inert content, then cp at line 31 of B.
  {
    for i in $(seq 1 30); do printf 'echo b %s\n' "$i"; done
    printf '%s\n' 'cp b-src b-dst'
  } > "$repo/B.sh"

  git -C "$repo" add A.sh B.sh
  git -C "$repo" commit -q -m "add A.sh and B.sh"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '[.patterns_found[] | select(.file == "A.sh" and .pattern == "cp") | .line] == [1]'
  echo "$output" | jq -e '[.patterns_found[] | select(.file == "B.sh" and .pattern == "cp") | .line] == [31]'
  rm -rf "$repo"
}

@test "BTS-133 AC-5: commit-message findings still emit line: 0 (backward compat)" {
  set -e
  local repo
  repo=$(_init_repo)

  printf '%s\n' 'echo nothing-special' > "$repo/x.txt"
  git -C "$repo" add x.txt
  git -C "$repo" commit -q -m "manually ran the migration to add x.txt"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]

  # commit-message finding should always have line: 0 (commit hash is not a source line)
  echo "$output" | jq -e '[.patterns_found[] | select(.pattern == "commit-message") | .line] | all(. == 0)'
  rm -rf "$repo"
}

@test "BTS-133 AC-6: empty diff produces zero findings (no false positives from line tracking)" {
  set -e
  local repo
  repo=$(_init_repo)

  # No changes after the seed commit; --since HEAD~0..HEAD is empty.
  run bash "$SCRIPT" audit-session --since HEAD "$repo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.patterns_found | length == 0'
  rm -rf "$repo"
}

@test "BTS-133 AC-7: existing assertion — every finding has a numeric line field" {
  set -e
  local repo
  repo=$(_init_repo)

  printf '%s\n' 'cp x y' > "$repo/move.sh"
  git -C "$repo" add move.sh
  git -C "$repo" commit -q -m "add move.sh"

  run bash "$SCRIPT" audit-session --since HEAD~1 "$repo"
  [ "$status" -eq 0 ]
  # Every finding's `.line` is a number (not null, not string).
  echo "$output" | jq -e '[.patterns_found[] | (.line | type)] | all(. == "number")'
  rm -rf "$repo"
}
