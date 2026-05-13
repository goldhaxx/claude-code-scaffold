#!/usr/bin/env bats
# BTS-482 — canonical example-data SSOT structure tests.
#
# The SSOT (.ccanvil/fixtures/canonical-example-data.json) documents the
# reserved-namespace fixture conventions security-audit.sh's email scanner
# already auto-allowlists (lines matching @example\.(com|org|net) per
# RFC 2606). Test fixtures across ccanvil downstream nodes reference this
# file so security-audit treats their fake user data as known-fake.

bats_require_minimum_version 1.5.0

SSOT="$BATS_TEST_DIRNAME/../../.ccanvil/fixtures/canonical-example-data.json"

# ---------------------------------------------------------------------------
# AC-3: SSOT file exists + parses as valid JSON
# ---------------------------------------------------------------------------

@test "AC-3: SSOT file exists" {
  [ -f "$SSOT" ]
}

@test "AC-3: SSOT parses as valid JSON" {
  jq . "$SSOT" > /dev/null
}

@test "AC-3: SSOT declares positive integer version field" {
  v=$(jq -r '.version' "$SSOT")
  [[ "$v" =~ ^[0-9]+$ ]]
  [ "$v" -ge 1 ]
}

# ---------------------------------------------------------------------------
# AC-4: SSOT declares ≥3 canonical email addresses in the @example namespace
# ---------------------------------------------------------------------------

@test "AC-4: SSOT declares at least 3 email entries" {
  count=$(jq -r '.emails | length' "$SSOT")
  [ "$count" -ge 3 ]
}

@test "AC-4: every email address matches @example.(com|org|net) namespace" {
  # Output one address per line; assert all match the canonical regex.
  while IFS= read -r addr; do
    [[ "$addr" =~ @example\.(com|org|net)$ ]] \
      || { echo "Non-canonical: $addr"; return 1; }
  done < <(jq -r '.emails[].address' "$SSOT")
}

@test "AC-4: each email entry has address + context fields" {
  jq -e '.emails | all(.address and .context)' "$SSOT" > /dev/null
}

# ---------------------------------------------------------------------------
# AC-9: malformed-JSON error path — jq exits non-zero on garbage input
# ---------------------------------------------------------------------------

@test "AC-9: jq surfaces a clear error on malformed SSOT" {
  bogus="$BATS_TEST_TMPDIR/malformed.json"
  printf 'not-json-at-all' > "$bogus"
  run --separate-stderr jq . "$bogus"
  [ "$status" -ne 0 ]
  [[ -n "$stderr" ]]
}

# ---------------------------------------------------------------------------
# AC-5: configuration.md documents the SSOT and the security-audit connection
# ---------------------------------------------------------------------------

CFG_MD="$BATS_TEST_DIRNAME/../../.ccanvil/guide/configuration.md"

@test "AC-5: configuration.md has 'Canonical example-data SSOT' section heading" {
  grep -qF 'Canonical example-data SSOT' "$CFG_MD"
}

@test "AC-5: configuration.md cites the SSOT path" {
  grep -qF '.ccanvil/fixtures/canonical-example-data.json' "$CFG_MD"
}

@test "AC-5: configuration.md explains the security-audit regex connection" {
  grep -qF 'security-audit.sh' "$CFG_MD"
  grep -qE '@example\\?\.\(com\|org\|net\)' "$CFG_MD"
}

@test "AC-5: configuration.md anchors the pattern to BTS-482" {
  grep -qF 'BTS-482' "$CFG_MD"
}
