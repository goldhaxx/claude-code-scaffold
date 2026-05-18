#!/usr/bin/env bats
#
# BTS-510 — cmd_index structural shape.
# AC-1 (per-invocation mktemp, no fixed $out.tmp), AC-6 (contract anchor),
# AC-7 (mkdir -p preserved). Block extracted via awk from `cmd_index() {`
# to the next column-0 `}`.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/module-manifest.sh"

_cmd_index_body() {
  awk '/^cmd_index\(\) \{/,/^\}$/' "$SCRIPT"
}

_cmd_index_manifest() {
  # Manifest block sits immediately above the function: from the nearest
  # `# @manifest` ABOVE the function declaration through the line just
  # before `cmd_index() {`.
  awk '
    /^# @manifest/ { start=NR; m_start=NR; m_block="" }
    { if (m_start) m_block = m_block $0 "\n" }
    /^cmd_index\(\) \{/ { print m_block; exit }
  ' "$SCRIPT"
}

@test "AC-1: cmd_index does NOT contain fixed $out.tmp pattern" {
  body=$(_cmd_index_body)
  if echo "$body" | grep -qF '"$out.tmp"'; then
    echo "fixed-filename pattern still present:" >&2
    echo "$body" | grep -nF '"$out.tmp"' >&2
    return 1
  fi
}

@test "AC-1: cmd_index calls mktemp with \$out.XXXXXX template" {
  body=$(_cmd_index_body)
  echo "$body" | grep -qE 'mktemp[[:space:]]+"\$out\.XXXXXX"' \
    || { echo "missing mktemp \"\$out.XXXXXX\" call:" >&2; echo "$body" >&2; return 1; }
}

@test "AC-7: cmd_index preserves mkdir -p for the out directory" {
  body=$(_cmd_index_body)
  echo "$body" | grep -qF 'mkdir -p "$(dirname "$out")"' \
    || { echo "AC-7 mkdir -p missing:" >&2; echo "$body" >&2; return 1; }
}
