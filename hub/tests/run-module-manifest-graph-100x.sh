#!/usr/bin/env bash
#
# BTS-510 AC-3 — empirical regression-guard for the cmd_index parallel race.
# Runs `bats --jobs 12 hub/tests/module-manifest-graph.bats` 100 times and
# counts failures of the "tiny allowlist with command→agent edge" test.
# Exits 0 iff zero failures.
#
# Wall time: ~10-15 min on a 12-core M-series.
# Usage:
#   bash hub/tests/run-module-manifest-graph-100x.sh        # default 100 iters
#   ITERS=50 bash hub/tests/run-module-manifest-graph-100x.sh  # downscale
#
# Anchored on BTS-510 spec AC-3.

set -uo pipefail

ITERS="${ITERS:-100}"
TEST_FILE="hub/tests/module-manifest-graph.bats"
TARGET_TEST="tiny allowlist with command"

if [[ ! -f "$TEST_FILE" ]]; then
  echo "FATAL: $TEST_FILE not found (run from project root)" >&2
  exit 2
fi

if ! command -v bats >/dev/null 2>&1; then
  echo "FATAL: bats not on PATH" >&2
  exit 2
fi

echo "BTS-510 AC-3 verification: running $TEST_FILE $ITERS times (--jobs 12)"
echo "Target test: '$TARGET_TEST...'"
echo

fail_count=0
fail_iters=()
log_dir=$(mktemp -d -t bts510-XXXXXX)
trap "rm -rf '$log_dir'" EXIT

start=$(date +%s)
for ((i=1; i<=ITERS; i++)); do
  log="$log_dir/iter-$i.log"
  if bats --jobs 12 "$TEST_FILE" > "$log" 2>&1; then
    printf '.'
  else
    # Check whether the failure was the BTS-510 target test specifically.
    if grep -qF "$TARGET_TEST" "$log" 2>/dev/null && grep -E "^not ok .*$TARGET_TEST" "$log" >/dev/null; then
      printf 'X'
      fail_count=$((fail_count + 1))
      fail_iters+=("$i")
    else
      printf '?'
      # Unrelated failure — surface in summary.
      fail_count=$((fail_count + 1))
      fail_iters+=("$i (unrelated)")
    fi
  fi
  # Newline every 50 marks for readability.
  if (( i % 50 == 0 )); then
    printf ' %d\n' "$i"
  fi
done
echo

end=$(date +%s)
wall=$((end - start))

echo "--- summary ---"
echo "iters:     $ITERS"
echo "failures:  $fail_count"
echo "wall:      ${wall}s"
if (( fail_count > 0 )); then
  echo "fail iters: ${fail_iters[*]}"
  echo
  echo "First failing log:"
  first_fail="${fail_iters[0]%% *}"
  cat "$log_dir/iter-$first_fail.log" >&2
  exit 1
fi

echo "PASS: 0 failures of '$TARGET_TEST' across $ITERS runs."
