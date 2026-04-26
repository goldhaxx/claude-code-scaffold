#!/usr/bin/env bats
# BTS-179 — idea-pending-replay substrate primitive.
#
# Replaces the per-skill shell loop in /idea sync with a deterministic
# bash command that iterates .ccanvil/ideas-pending.log and dispatches each
# entry by op via the http substrate (resolve idea.add or ticket.transition,
# eval the resolved command). Eliminates the echo-then-jq round-trip class
# of bug surfaced 2026-04-26.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"
OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude" "$PROJECT/.ccanvil/scripts"
}

teardown() {
  rm -rf "$PROJECT"
}

# Set up a Linear-routed project config so operations.sh resolves idea.add
# and ticket.transition to http with backlog/triage state ids configured.
_with_linear_routing() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project":"ccanvil","team":"Blocktech","idea_label":"idea","state_ids":{"triage":"TRIAGE-UUID","backlog":"BACKLOG-UUID","icebox":"ICEBOX-UUID","canceled":"CANCELED-UUID","duplicate":"DUPLICATE-UUID"}}}}}
JSON
}

# Drop a stub linear-query.sh that records argv + stdin to $PROJECT/stub-log
# and emits a fake successful response. Each call appends one record.
_with_linear_stub() {
  local exit_code="${1:-0}"
  cat > "$PROJECT/.ccanvil/scripts/linear-query.sh" <<EOF
#!/usr/bin/env bash
# Stub for tests: record argv + stdin to stub-log, emit fake response.
{
  echo "----CALL----"
  echo "ARGV: \$*"
  echo "STDIN-START"
  cat
  echo "STDIN-END"
} >> "$PROJECT/stub-log"
echo '{"id":"BTS-STUB","title":"stubbed"}'
exit $exit_code
EOF
  chmod +x "$PROJECT/.ccanvil/scripts/linear-query.sh"
}

# =========================================================================
# AC-1: empty log fast path
# =========================================================================

@test "AC-1: idea-pending-replay with no log emits empty summary, exits 0" {
  set -e
  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 0'
  echo "$output" | jq -e '.failed == 0'
  echo "$output" | jq -e '.pending == 0'
  echo "$output" | jq -e '.entries == []'
}

@test "AC-1: idea-pending-replay with empty log file emits empty summary, exits 0" {
  set -e
  : > "$PROJECT/.ccanvil/ideas-pending.log"
  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 0'
  echo "$output" | jq -e '.entries == []'
}

# =========================================================================
# AC-2: add op replay
# =========================================================================

@test "AC-2: replay of an 'add' entry dispatches via idea.add http substrate" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op add \
    --title "Test idea" --body "first paragraph"

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 1'
  echo "$output" | jq -e '.failed == 0'
  echo "$output" | jq -e '.pending == 0'
  echo "$output" | jq -e '.entries | length == 1'
  echo "$output" | jq -e '.entries[0].op == "add"'
  echo "$output" | jq -e '.entries[0].result == "synced"'

  # Pending log was ack'd.
  [ ! -s "$PROJECT/.ccanvil/ideas-pending.log" ]

  # Stub captured the call: save-issue with --input-json - and stdin JSON.
  grep -q "save-issue" "$PROJECT/stub-log"
  grep -q "input-json" "$PROJECT/stub-log"
  # stdin was the {title, description} JSON.
  grep -q '"Test idea"' "$PROJECT/stub-log"
  grep -q "first paragraph" "$PROJECT/stub-log"
}

@test "AC-2: 'add' entry with parent_id appends --parent-id to dispatch" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op add \
    --title "Child" --body "body" --parent BTS-179

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 1'

  grep -q -- "--parent-id" "$PROJECT/stub-log"
  grep -q "BTS-179" "$PROJECT/stub-log"
}

# =========================================================================
# AC-3 + AC-4: ticket.transition ops (promote, defer, dismiss, merge,
# ticket.transition)
# =========================================================================

@test "AC-3: replay of 'promote' entry uses ticket.transition + --priority" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op promote \
    --id BTS-100 --priority 2

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 1'
  echo "$output" | jq -e '.entries[0].op == "promote"'

  grep -q "save-issue" "$PROJECT/stub-log"
  grep -q "BTS-100" "$PROJECT/stub-log"
  grep -q "BACKLOG-UUID" "$PROJECT/stub-log"
  grep -qE -- "--priority +2( |$)" "$PROJECT/stub-log"
}

@test "AC-4: replay of 'defer' uses ticket.transition + icebox state-id" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op defer --id BTS-200

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 1'

  grep -q "BTS-200" "$PROJECT/stub-log"
  grep -q "ICEBOX-UUID" "$PROJECT/stub-log"
}

@test "AC-4: replay of 'dismiss' uses ticket.transition + canceled state-id" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op dismiss --id BTS-300

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 1'

  grep -q "BTS-300" "$PROJECT/stub-log"
  grep -q "CANCELED-UUID" "$PROJECT/stub-log"
}

@test "AC-4: replay of 'merge' uses ticket.transition + --duplicate-of" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op merge \
    --id BTS-400 --duplicate-of BTS-401

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 1'

  grep -q "BTS-400" "$PROJECT/stub-log"
  grep -q "DUPLICATE-UUID" "$PROJECT/stub-log"
  grep -qE -- "--duplicate-of +BTS-401( |$)" "$PROJECT/stub-log"
}

@test "AC-4: replay of generic 'ticket.transition' op uses provided role" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" \
    --op ticket.transition --id BTS-500 --role backlog

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 1'
  echo "$output" | jq -e '.entries[0].op == "ticket.transition"'

  grep -q "BTS-500" "$PROJECT/stub-log"
  grep -q "BACKLOG-UUID" "$PROJECT/stub-log"
}

# =========================================================================
# AC-5: ack-on-success / preserve-on-failure
# =========================================================================

@test "AC-5: failed entry is preserved; succeeded entry is ack'd" {
  set -e
  _with_linear_routing
  # Stub that fails on the first call, succeeds on subsequent calls.
  cat > "$PROJECT/.ccanvil/scripts/linear-query.sh" <<EOF
#!/usr/bin/env bash
COUNT_FILE="$PROJECT/stub-call-count"
n=\$(cat "\$COUNT_FILE" 2>/dev/null || echo 0)
n=\$((n + 1))
echo \$n > "\$COUNT_FILE"
{
  echo "----CALL \$n----"
  echo "ARGV: \$*"
  cat
} >> "$PROJECT/stub-log"
if [[ "\$n" -eq 1 ]]; then
  echo "stub: simulated failure" >&2
  exit 3
fi
echo '{"id":"BTS-STUB","title":"stubbed"}'
exit 0
EOF
  chmod +x "$PROJECT/.ccanvil/scripts/linear-query.sh"

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op add \
    --title "Will fail" --body "body1"
  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op add \
    --title "Will succeed" --body "body2"

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  # AC-6: exit non-zero when any entry fails.
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.synced == 1'
  echo "$output" | jq -e '.failed == 1'
  echo "$output" | jq -e '.pending == 1'
  echo "$output" | jq -e '.entries | length == 2'
  # First entry failed; error captured.
  echo "$output" | jq -e '.entries[0].result == "failed"'
  echo "$output" | jq -e '.entries[0].error | length > 0'
  # Second entry succeeded.
  echo "$output" | jq -e '.entries[1].result == "synced"'

  # Pending log retains the failed entry only.
  [ "$(jq -s 'length' "$PROJECT/.ccanvil/ideas-pending.log")" = "1" ]
  jq -e '.args.title == "Will fail"' "$PROJECT/.ccanvil/ideas-pending.log"
}

# =========================================================================
# AC-6: exit code 0 when all succeed; non-zero when any fail
# =========================================================================

@test "AC-6: exit 0 when every entry syncs" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op defer --id BTS-A
  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op defer --id BTS-B

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 2'
  echo "$output" | jq -e '.failed == 0'
}

# =========================================================================
# AC-7: \n-escape regression — body with JSON-escaped newlines round-trips
# without corruption. This is the bug that motivated BTS-179: the prior
# skill-prose flow's `echo "$PENDING" | jq` round-trip turned escaped \n
# into literal newlines mid-pipeline, breaking the JSON.
# =========================================================================

@test "AC-7: body with JSON-escaped \\n round-trips through replay (real newlines reach dispatch, no parse errors)" {
  set -e
  _with_linear_routing
  _with_linear_stub 0

  # Body with multiple paragraphs separated by blank lines. When written via
  # idea-pending-append, the literal newlines become JSON-escaped \n. Replay
  # must re-emit them as REAL newlines on the dispatched stdin.
  local body=$'## What\n\nfirst paragraph\n\nsecond paragraph'
  bash "$SCRIPT" idea-pending-append --project-dir "$PROJECT" --op add \
    --title "newline regression" --body "$body"

  # Confirm pending log stored escaped form (single line, contains \n literal).
  [ "$(wc -l < "$PROJECT/.ccanvil/ideas-pending.log" | tr -d ' ')" = "1" ]
  grep -q '\\n' "$PROJECT/.ccanvil/ideas-pending.log"

  run bash "$SCRIPT" idea-pending-replay --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.synced == 1'
  echo "$output" | jq -e '.failed == 0'
  # Confirm no jq parse errors on stderr or stdout.
  ! echo "$output" | grep -q "parse error"
  ! echo "$output" | grep -q "control characters"

  # Stub-log records the stdin that reached dispatch. The {description}
  # field should contain real newlines — meaning each paragraph is on its
  # own physical line in the recorded stdin.
  grep -q "first paragraph" "$PROJECT/stub-log"
  grep -q "second paragraph" "$PROJECT/stub-log"
  # The stdin was a JSON envelope; description value was JSON-escaped \n.
  # Confirm jq can parse it back and the description field has real
  # newlines (i.e. >1 physical line when extracted).
  local stdin_json
  stdin_json=$(awk '/STDIN-START/{p=1;next} /STDIN-END/{p=0} p' "$PROJECT/stub-log")
  local desc_lines
  desc_lines=$(printf '%s' "$stdin_json" | jq -r '.description' | wc -l | tr -d ' ')
  # 4 newlines: ## What, blank, first paragraph, blank, second paragraph
  # → 4 trailing newlines from wc -l (counts \n delimiters).
  [ "$desc_lines" -ge 3 ]
}

# =========================================================================
# AC-8: resolver wiring — operations.sh resolve idea.sync points to
# idea-pending-replay (not idea-sync — which stays as enumerate-only).
# =========================================================================

@test "AC-8: operations.sh resolve idea.sync routes to idea-pending-replay (local provider)" {
  set -e
  # Local-only project: no Linear routing.
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"local":{"mechanism":"bash"}}}}
JSON
  run bash "$OPS" resolve idea.sync --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("idea-pending-replay")'
  ! echo "$output" | jq -e '.invocation.command | endswith("idea-sync")'
}

@test "AC-8: operations.sh resolve idea.sync routes to idea-pending-replay (linear provider)" {
  set -e
  _with_linear_routing
  run bash "$OPS" resolve idea.sync --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("idea-pending-replay")'
}
