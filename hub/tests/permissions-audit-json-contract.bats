#!/usr/bin/env bats
# BTS-134 — permissions-audit.sh JSON contract: --json flag + error envelope.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/permissions-audit.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  FIXTURE=$(mktemp -d)
  mkdir -p "$FIXTURE"
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "BTS-134 AC-1: --json flag accepted; output identical-shaped JSON to default" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(git status:*)"]}}
JSON

  run --separate-stderr bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/log.json" --json
  # Exit 1 (UNREVIEWED present, no log) is fine — we're checking output shape.
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.entries | type == "array"'
  echo "$output" | jq -e '.danger | type == "number"'
  echo "$output" | jq -e '.unreviewed | type == "number"'
  echo "$output" | jq -e '.reviewed | type == "number"'
}

@test "BTS-134 AC-2: missing settings.json — stdout has JSON error envelope, stderr has ERROR, exit 2" {
  run --separate-stderr bash "$SCRIPT" check --settings-dir "$FIXTURE/nope" --log "$FIXTURE/log.json"
  [ "$status" -eq 2 ]
  # stdout is valid JSON containing an "error" field
  echo "$output" | jq -e 'has("error")'
  echo "$output" | jq -e '.error | type == "string"'
  echo "$output" | jq -e '.exit == 2'
  # stderr still has the human-readable line
  [[ "$stderr" =~ "ERROR:" ]]
  [[ "$stderr" =~ "not found" ]]
}

@test "BTS-134 AC-3: corrupt log file — stdout has JSON error envelope, stderr has ERROR, exit 2" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(git status:*)"]}}
JSON
  echo "not json {{{" > "$FIXTURE/bad-log.json"

  run --separate-stderr bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/bad-log.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e 'has("error")'
  echo "$output" | jq -e '.error | type == "string"'
  echo "$output" | jq -e '.exit == 2'
  [[ "$stderr" =~ "ERROR:" ]]
  [[ "$stderr" =~ "not valid JSON" ]]
}

@test "BTS-134 AC-4: --text mode preserves existing error behavior (no JSON envelope on stdout)" {
  run --separate-stderr bash "$SCRIPT" check --settings-dir "$FIXTURE/nope" --log "$FIXTURE/log.json" --text
  [ "$status" -eq 2 ]
  # stdout is NOT JSON — text mode behaviors preserved.
  ! echo "$output" | jq -e '.' >/dev/null 2>&1
  [[ "$stderr" =~ "ERROR:" ]]
}

@test "BTS-134 AC-5: --json --text last-wins (text wins, no JSON envelope on error)" {
  run --separate-stderr bash "$SCRIPT" check --settings-dir "$FIXTURE/nope" --log "$FIXTURE/log.json" --json --text
  [ "$status" -eq 2 ]
  # --text was last → text-mode behavior, no JSON envelope on stdout
  ! echo "$output" | jq -e '.' >/dev/null 2>&1
}

@test "BTS-134 AC-5: --text --json last-wins (json wins, JSON envelope on error)" {
  run --separate-stderr bash "$SCRIPT" check --settings-dir "$FIXTURE/nope" --log "$FIXTURE/log.json" --text --json
  [ "$status" -eq 2 ]
  echo "$output" | jq -e 'has("error")'
}

@test "BTS-134 AC-6: exit codes preserved — 1 (UNREVIEWED), 2 (DANGER)" {
  set -e
  # UNREVIEWED-only — exit 1
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(git status:*)"]}}
JSON
  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/log.json"
  [ "$status" -eq 1 ]

  # DANGER — exit 2 (broad-wildcard pattern)
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)"]}}
JSON
  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/log.json"
  [ "$status" -eq 2 ]
}

@test "BTS-134 AC-7: success-path envelope unchanged — entries/danger/unreviewed/reviewed keys" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(git status:*)"]}}
JSON

  run --separate-stderr bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/log.json"
  # Whatever the exit code, the success-path envelope keys must be present
  # and the error key must NOT be present (success-path) when settings.json IS valid.
  echo "$output" | jq -e 'has("entries") and has("danger") and has("unreviewed") and has("reviewed")'
  echo "$output" | jq -e 'has("error") | not'
}
