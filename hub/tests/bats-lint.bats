#!/usr/bin/env bats
# BTS-127 — bats-lint.sh flags leaky sequential jq -e patterns.
# Fixtures seeded inline; each test is an independent scenario.
#
# NOTE: bats preprocesses any literal `@test "..." {` in this file, including
# inside heredocs. Fixtures use the sentinel `TESTZ` which `seed_bats` rewrites
# to `@test` at runtime.

bats_require_minimum_version 1.5.0

LINT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-lint.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# Write a .bats fixture. Rewrites `TESTZ` to `@test` so the enclosing bats
# file's preprocessor can't see literal `@test` directives here.
seed_bats() {
  local dest="$1"
  shift
  local content
  content=$(printf '%s\n' "$@")
  printf '%s' "${content//TESTZ/@test}" > "$dest"
}

@test "BTS-127: lint flags leaky sequential jq -e (no set -e)" {
  set -e
  seed_bats "$WORK/leaky.bats" \
    'TESTZ "leaky" {' \
    "  run echo '{\"a\":1}'" \
    '  echo "$output" | jq -e ".a == 999"' \
    '  echo "$output" | jq -e ".a == 1"' \
    '}'
  run --separate-stderr bash "$LINT" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$stderr" =~ leaky.bats ]]
  [[ "$stderr" =~ "leaky jq -e" ]]
}

@test "BTS-127: lint passes when set -e is present at top of block" {
  set -e
  seed_bats "$WORK/strict.bats" \
    'TESTZ "strict" {' \
    '  set -e' \
    "  run echo '{\"a\":1}'" \
    '  echo "$output" | jq -e ".a == 1"' \
    '  echo "$output" | jq -e ".a == 1"' \
    '}'
  run bash "$LINT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "BTS-127: lint passes when jq -e assertions are combined via and" {
  set -e
  seed_bats "$WORK/combined.bats" \
    'TESTZ "combined" {' \
    "  run echo '{\"a\":1,\"b\":2}'" \
    '  echo "$output" | jq -e ".a == 1 and .b == 2"' \
    '}'
  run bash "$LINT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "BTS-127: lint passes on tests with only one jq -e" {
  set -e
  seed_bats "$WORK/single.bats" \
    'TESTZ "single" {' \
    "  run echo '{\"a\":1}'" \
    '  echo "$output" | jq -e ".a == 1"' \
    '}'
  run bash "$LINT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "BTS-127: lint passes on tests with zero jq -e" {
  set -e
  seed_bats "$WORK/nojq.bats" \
    'TESTZ "nojq" {' \
    '  run echo hi' \
    '  [ "$status" -eq 0 ]' \
    '  [[ "$output" = "hi" ]]' \
    '}'
  run bash "$LINT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "BTS-127: lint reports each leaky block when file has multiple" {
  set -e
  seed_bats "$WORK/multi.bats" \
    'TESTZ "first leaky" {' \
    "  echo '{\"a\":1}' | jq -e '.a == 999'" \
    "  echo '{\"a\":1}' | jq -e '.a == 1'" \
    '}' \
    '' \
    'TESTZ "second leaky" {' \
    "  echo '{\"x\":2}' | jq -e '.x == 999'" \
    "  echo '{\"x\":2}' | jq -e '.x == 2'" \
    '}' \
    '' \
    'TESTZ "third strict" {' \
    '  set -e' \
    "  echo '{\"y\":3}' | jq -e '.y == 3'" \
    "  echo '{\"y\":3}' | jq -e '.y == 3'" \
    '}'
  run --separate-stderr bash "$LINT" "$WORK"
  [ "$status" -eq 1 ]
  local lines
  lines=$(echo "$stderr" | grep -c 'multi.bats')
  [ "$lines" -ge 2 ]
}

@test "BTS-127: lint accepts a single file path, not only a directory" {
  set -e
  seed_bats "$WORK/one.bats" \
    'TESTZ "single" {' \
    '  set -e' \
    "  echo '{\"a\":1}' | jq -e '.a == 1'" \
    "  echo '{\"a\":1}' | jq -e '.a == 1'" \
    '}'
  run bash "$LINT" "$WORK/one.bats"
  [ "$status" -eq 0 ]
}

@test "BTS-127: lint exits 0 on empty directory" {
  run bash "$LINT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "BTS-127: lint ignores jq -e inside heredoc bodies (fixture-generator tests)" {
  set -e
  # Simulates a test that *writes a file containing jq -e* via heredoc.
  # The jq -e lines inside the heredoc are data, not assertions — must not
  # count toward the leak threshold.
  seed_bats "$WORK/fixture_gen.bats" \
    'TESTZ "writes fixture with jq -e inside" {' \
    '  cat > "$WORK/inner.bats" <<BATS' \
    '@test "inner" {' \
    "  echo '{\"a\":1}' | jq -e '.a == 1'" \
    "  echo '{\"a\":1}' | jq -e '.a == 1'" \
    '}' \
    'BATS' \
    '  run bash foo' \
    '}'
  run bash "$LINT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "BTS-127: lint ignores heredoc with quoted delimiter" {
  set -e
  seed_bats "$WORK/quoted_heredoc.bats" \
    "TESTZ \"quoted heredoc\" {" \
    "  cat > out <<'END'" \
    "echo '{}' | jq -e '.a'" \
    "echo '{}' | jq -e '.b'" \
    "echo '{}' | jq -e '.c'" \
    'END' \
    '}'
  run bash "$LINT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "BTS-127: lint does not count 'run jq -e' toward leak threshold" {
  set -e
  # run captures exit status into $status — jq -e invoked via run cannot leak.
  seed_bats "$WORK/run_jq.bats" \
    'TESTZ "run jq -e" {' \
    "  run jq -e '.a == 1' <<<'{\"a\":1}'" \
    '  [ "$status" -eq 0 ]' \
    "  run jq -e '.b == 2' <<<'{\"b\":2}'" \
    '  [ "$status" -eq 0 ]' \
    '}'
  run bash "$LINT" "$WORK"
  [ "$status" -eq 0 ]
}
