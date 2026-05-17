#!/usr/bin/env bats
#
# BTS-507 — shared helper that bypasses bats-report.sh's BTS-281 module-manifest
# pre-warm. Tests in this file exercise the helper directly (not via a
# bats-report.sh sub-invocation); they're exempt from the drift-guard.
#
# bats-report-stub: exempt

load _helpers/bats-report-stub

@test "AC-1: stub_bats_report_prewarm writes canonical envelope + exports BTS_MANIFEST_VALIDATE_CACHE" {
  set -e
  stub_bats_report_prewarm

  [ -n "$BTS_MANIFEST_VALIDATE_CACHE" ]
  [ -s "$BTS_MANIFEST_VALIDATE_CACHE" ]

  jq -e '.coverage.covered == 0 and .coverage.total == 0 and (.drift | length) == 0 and .status == "ok"' \
    < "$BTS_MANIFEST_VALIDATE_CACHE"

  case "$BTS_MANIFEST_VALIDATE_CACHE" in
    "$BATS_FILE_TMPDIR"/*) ;;
    *) echo "expected path under \$BATS_FILE_TMPDIR ($BATS_FILE_TMPDIR), got: $BTS_MANIFEST_VALIDATE_CACHE" >&2; return 1 ;;
  esac
}

@test "AC-2: idempotent at file scope — two calls yield the same path, no error" {
  set -e
  stub_bats_report_prewarm
  local first="$BTS_MANIFEST_VALIDATE_CACHE"

  stub_bats_report_prewarm
  local second="$BTS_MANIFEST_VALIDATE_CACHE"

  [ "$first" = "$second" ]
  [ -s "$second" ]
}
