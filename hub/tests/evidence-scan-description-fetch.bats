#!/usr/bin/env bats
# BTS-203: per-candidate get-issue fetch in evidence-scan-session.
# When body is empty (idea.list listings don't include description),
# the substrate fetches via linear-query.sh get-issue. Tests use
# LINEAR_QUERY_OVERRIDE to stub the fetch.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SCRIPT="$REPO_ROOT/.ccanvil/scripts/docs-check.sh"

setup() {
  TMPDIR_BATS=$(mktemp -d)
}

teardown() {
  [[ -n "${TMPDIR_BATS:-}" ]] && rm -rf "$TMPDIR_BATS"
}

write_fixture() {
  local path="$TMPDIR_BATS/$1"
  shift
  cat > "$path"
  echo "$path"
}

# Build a stubbed linear-query.sh that returns canned descriptions per ID.
write_stub_with_anchors() {
  local stub="$TMPDIR_BATS/lq-stub.sh"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
if [[ "$1" == "get-issue" ]]; then
  case "$2" in
    BTS-9101)
      jq -n '{description: "Command: foo\nOutput: bar\nExit: 0\nReproduce: foo"}'
      exit 0
      ;;
    *)
      exit 3
      ;;
  esac
fi
exit 1
STUBEOF
  chmod +x "$stub"
  echo "$stub"
}

write_stub_always_fails() {
  local stub="$TMPDIR_BATS/lq-stub-fail.sh"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
exit 3
STUBEOF
  chmod +x "$stub"
  echo "$stub"
}

# =========================================================================
# AC-1: bug-shape + fetched anchors → no gap
# =========================================================================

@test "AC-1: bug-shape title with empty body, fetch returns full anchors → no gap" {
  fixture=$(jq -n '[{
    id: "BTS-9101",
    title: "guard-destructive false positive on flag combos",
    description: null,
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  stub=$(write_stub_with_anchors)
  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scanned == 1'
  echo "$output" | jq -e '.evidence_gaps | length == 0'
}

# =========================================================================
# AC-2: bug-shape + body present without anchors → gap (existing behavior)
# =========================================================================

@test "AC-2: bug-shape title with non-empty body missing anchors → gap" {
  fixture=$(jq -n '[{
    id: "BTS-9102",
    title: "the workflow fails sometimes",
    description: "vague body, no anchors here",
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.evidence_gaps | length == 1'
  echo "$output" | jq -e '.evidence_gaps[0].reason == "missing-evidence-anchors"'
}

# =========================================================================
# AC-3: DIAGNOSE: titles still exempt — no fetch attempted
# =========================================================================

@test "AC-3: DIAGNOSE: title is exempt (no fetch, no anchor check)" {
  fixture=$(jq -n '[{
    id: "BTS-9103",
    title: "DIAGNOSE: intermittent flakiness",
    description: null,
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  stub=$(write_stub_always_fails)
  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.evidence_gaps | length == 0'
}

# =========================================================================
# AC-4: input-json with description provided → no fetch needed
# =========================================================================

@test "AC-4: input-json description present → existing path, no fetch needed" {
  body='Command: bash run.sh
Output: error
Exit: 2
Reproduce: bash run.sh'
  fixture=$(jq -n --arg b "$body" '[{
    id: "BTS-9104",
    title: "the foo command fails on macOS",
    description: $b,
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  # Even with a failing stub, this test passes because body is non-empty.
  stub=$(write_stub_always_fails)
  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.evidence_gaps | length == 0'
}

# =========================================================================
# AC-5: fetch fails → fail-closed, reports missing-evidence-anchors
# =========================================================================

@test "AC-5: fetch fails (network/auth error) → reports missing-evidence-anchors" {
  fixture=$(jq -n '[{
    id: "BTS-9105",
    title: "the build fails reproducibly",
    description: null,
    createdAt: "2099-01-01T00:00:00.000Z"
  }]' | write_fixture issues.json)
  stub=$(write_stub_always_fails)
  LINEAR_QUERY_OVERRIDE="$stub" run bash "$SCRIPT" evidence-scan-session --input-json "$fixture" --no-time-filter
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.evidence_gaps | length == 1'
  echo "$output" | jq -e '.evidence_gaps[0].id == "BTS-9105"'
  echo "$output" | jq -e '.evidence_gaps[0].reason == "missing-evidence-anchors"'
}

# =========================================================================
# Drift-guard: BTS-203 reference present in docs-check.sh
# =========================================================================

@test "drift: BTS-203 referenced inline in docs-check.sh" {
  grep -q "BTS-203" "$SCRIPT"
}
