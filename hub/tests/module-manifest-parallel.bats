#!/usr/bin/env bats
#
# BTS-510 AC-2 — parallel-stress harness for cmd_index.
# 12 concurrent writers + 100 interleaved reads must produce zero JSON
# parse failures. Verifies the structural property (per-invocation
# mktemp intermediate) holds under concurrent execution.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/module-manifest.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .ccanvil/scripts .ccanvil/state

  # Two source files with non-trivial manifest blocks so cmd_index has
  # real work to do per invocation (extract + merge takes a few ms each,
  # widening the race window relative to the no-op case).
  cat > .ccanvil/scripts/seed-a.sh <<'EOF'
# @manifest
# purpose: seed A for parallel-stress
# input: none
# output: stdout (none)
# output: exit-codes 0 ok
# anchor: BTS-510-test
seed_a() { :; }
EOF
  cat > .ccanvil/scripts/seed-b.sh <<'EOF'
# @manifest
# purpose: seed B for parallel-stress
# input: none
# output: stdout (none)
# output: exit-codes 0 ok
# anchor: BTS-510-test
seed_b() { :; }
EOF
}

@test "AC-2: 12 concurrent cmd_index writers + interleaved reads → zero parse OR content-truncation failures" {
  local out=".ccanvil/state/manifests.json"
  local writer_iters=100
  local reader_iters=500
  local writers=12
  # Minimum expected key count: each seed contributes 1 key. Anything
  # less means the writer hit the empty-accumulator `{}` branch — the
  # actual BTS-510 symptom (partial $out.tmp clobber → truncation
  # falling through to an apparent empty-source result).
  local expected_min_keys=2

  local pids=()
  local i
  for ((i=0; i<writers; i++)); do
    (
      for ((j=0; j<writer_iters; j++)); do
        bash "$SCRIPT" index >/dev/null 2>&1
      done
    ) &
    pids+=($!)
  done

  local parse_fail=0
  local content_fail=0
  local readable_count=0
  for ((r=0; r<reader_iters; r++)); do
    if [[ -f "$out" ]]; then
      readable_count=$((readable_count + 1))
      local content
      content=$(cat "$out" 2>/dev/null || true)
      if ! echo "$content" | jq -e . >/dev/null 2>&1; then
        parse_fail=$((parse_fail + 1))
      else
        local n_keys
        n_keys=$(echo "$content" | jq 'keys | length' 2>/dev/null || echo 0)
        if (( n_keys < expected_min_keys )); then
          content_fail=$((content_fail + 1))
        fi
      fi
    fi
  done

  local p
  for p in "${pids[@]}"; do
    wait "$p" || true
  done

  jq -e . < "$out" >/dev/null 2>&1 \
    || { echo "post-quiescence final read failed to parse" >&2; cat "$out" >&2; return 1; }
  local final_keys
  final_keys=$(jq 'keys | length' < "$out")
  [ "$final_keys" -ge "$expected_min_keys" ] \
    || { echo "post-quiescence final read has $final_keys keys (<$expected_min_keys)" >&2; cat "$out" >&2; return 1; }

  if (( parse_fail > 0 || content_fail > 0 )); then
    echo "FAIL: $parse_fail parse + $content_fail content-truncation failures across $readable_count reads" >&2
    return 1
  fi

  echo "OK: 0 parse / 0 truncation failures across $readable_count reads ($writers × $writer_iters writers)"
}
