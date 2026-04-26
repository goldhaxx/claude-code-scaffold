#!/usr/bin/env bats
# Tests for scripts/permissions-audit.sh
#
# Each test creates an isolated directory with fixture settings files.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/permissions-audit.sh"

setup() {
  FIXTURE=$(mktemp -d)
  # Create a default empty log to avoid NOTE messages on stderr
  # (tests that specifically test missing/invalid log override this)
  echo '{"entries":{}}' > "$FIXTURE/permissions-log.json"
  DEFAULT_LOG="$FIXTURE/permissions-log.json"
}

teardown() {
  rm -rf "$FIXTURE"
}


# =========================================================================
# Step 1: Script skeleton + entry parsing (AC-1 partial)
# =========================================================================

@test "check outputs valid JSON with entries array" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(ls:*)",
      "Bash(diff:*)"
    ]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  echo "$output" | jq -e '.entries | length == 3'
}

@test "each entry has permission, source, and status fields" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.entries[0].permission == "Bash(git status:*)"'
  echo "$output" | jq -e '.entries[0].source'
  echo "$output" | jq -e '.entries[0].status'
}

@test "output includes danger, unreviewed, reviewed counts" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)", "Bash(ls:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e 'has("danger")'
  echo "$output" | jq -e 'has("unreviewed")'
  echo "$output" | jq -e 'has("reviewed")'
}

@test "parses both allow and deny entries" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"],
    "deny": ["Bash(rm -rf /)*"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.entries | length == 2'
}

@test "missing settings.json exits with error" {
  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
}


# =========================================================================
# Step 2: Dual-file parsing + deduplication (AC-1 complete, AC-10)
# =========================================================================

@test "parses entries from both settings files" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.entries | length == 2'
}

@test "duplicate entry in both files reports single entry with array source" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(bats:*)"]
  }
}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(bats:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.entries | length == 1'
  echo "$output" | jq -e '.entries[0].source == ["settings.json", "settings.local.json"]'
}

@test "unique entries report single source as array" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.entries[0].source == ["settings.json"]'
}

@test "missing settings.local.json is not an error" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(ls:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  echo "$output" | jq -e '.entries | length == 1'
}


# =========================================================================
# Step 3: Dangerous pattern detection (AC-3)
# =========================================================================

@test "broad wildcard flagged as DANGER" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)", "Bash(cat:*)", "Bash(find:*)", "Bash(bash:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.danger == 4'
  echo "$output" | jq -e '[.entries[] | select(.status == "DANGER")] | length == 4'
}

@test "compound operators flagged as DANGER" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(bash -n scripts/foo.sh && echo \"ok\")",
      "Bash(cmd1; cmd2)"
    ]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.danger == 2'
}

@test "env-prefix command flagged as DANGER" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.entries[0].status == "DANGER"'
}

@test "redirect operators flagged as DANGER" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo foo > file.txt)", "Bash(echo bar >> file.txt)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.danger == 2'
}

@test "find -exec and find -delete flagged as DANGER" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(find . -exec rm {} \\;)", "Bash(find . -delete)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.danger == 2'
}

# BTS-154: Bash control-flow keywords (for, while, if, do, done, fi, etc.)
# in their bare or :* shapes are bash grammar tokens — they cannot execute
# anything on their own. The classifier exempts them via a pre-check before
# the DANGER patterns fire.
@test "BTS-154 AC-6: contract-flipped — bare-keyword fixture is now 0 DANGER" {
  # Was: prior loop-primitives test asserted .danger == 3 for these shapes.
  # Now: all three exempt via the keyword pre-check.
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(for:*)", "Bash(do:*)", "Bash(done)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.danger == 0'
}

@test "BTS-154 AC-1: bare bash keywords (done, fi) classify as safe (not DANGER)" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(done)", "Bash(fi)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  # All entries pass the keyword pre-check → exit 0 (no DANGER, no UNREVIEWED).
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.danger == 0'
}

@test "BTS-154 AC-2: keyword:* shapes (for:*, while:*, if:*, etc.) classify as safe" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(for:*)", "Bash(while:*)", "Bash(if:*)", "Bash(do:*)",
      "Bash(then:*)", "Bash(else:*)", "Bash(elif:*)"
    ]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.danger == 0'
}

@test "BTS-154 AC-3: full keyword set (16 keywords × bare + :*) all classify as safe" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(for)", "Bash(while)", "Bash(until)", "Bash(if)",
      "Bash(then)", "Bash(else)", "Bash(elif)", "Bash(fi)",
      "Bash(do)", "Bash(done)", "Bash(case)", "Bash(esac)",
      "Bash(in)", "Bash(function)", "Bash(select)", "Bash(time)",
      "Bash(for:*)", "Bash(while:*)", "Bash(until:*)", "Bash(if:*)",
      "Bash(then:*)", "Bash(else:*)", "Bash(elif:*)", "Bash(fi:*)",
      "Bash(do:*)", "Bash(done:*)", "Bash(case:*)", "Bash(esac:*)",
      "Bash(in:*)", "Bash(function:*)", "Bash(select:*)", "Bash(time:*)"
    ]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.danger == 0'
}

@test "BTS-154 AC-4: substring shapes do NOT match the keyword exemption (word-anchor guard)" {
  set -e
  # `done-something` starts with `done` but isn't the keyword. The pre-check
  # is word-anchored (`^...$`), so the existing loose loop-primitive regex
  # (`^done`) still catches it as DANGER — pre-existing behavior preserved.
  # `fish` and `forever` don't trip any DANGER pattern; they classify as
  # UNREVIEWED (not auto-exempted by the keyword pre-check).
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(done-something)", "Bash(fish)", "Bash(forever)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  # done-something is still DANGER (loose ^done regex, pre-existing).
  # fish and forever land as UNREVIEWED (keyword pre-check correctly
  # rejects them via the $-anchor).
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.danger == 1'
  echo "$output" | jq -e '[.entries[] | select(.status == "UNREVIEWED")] | length == 2'
}

# =========================================================================
# BTS-159: decision-append substrate
# =========================================================================
# Single-call replacement for the Write+cat+rm dance in /permissions-review.
# Validates against the same pre-flight schema as `apply --decisions`, then
# atomically appends one JSON line to a caller-provided buffer file.

@test "BTS-159 AC-1: decision-append --decision delete writes one JSON line" {
  set -e
  local buf="$FIXTURE/buffer.jsonl"
  run bash "$SCRIPT" decision-append --buffer "$buf" --permission 'Bash(rm:*)' --decision delete
  [ "$status" -eq 0 ]
  [ -f "$buf" ]
  # Exactly one line, valid JSON, correct shape.
  local n
  n=$(wc -l < "$buf" | tr -d ' ')
  [ "$n" -eq 1 ]
  cat "$buf" | jq -e '.permission == "Bash(rm:*)" and .decision == "delete"'
}

@test "BTS-159 AC-1: decision-append appends to existing buffer (preserves prior content)" {
  set -e
  local buf="$FIXTURE/buffer.jsonl"
  printf '{"permission":"Bash(ls:*)","decision":"keep-local"}\n' > "$buf"
  run bash "$SCRIPT" decision-append --buffer "$buf" --permission 'Bash(rm:*)' --decision delete
  [ "$status" -eq 0 ]
  local n
  n=$(wc -l < "$buf" | tr -d ' ')
  [ "$n" -eq 2 ]
}

@test "BTS-159 AC-2: --decision promote / keep-local both emit the 2-field shape" {
  set -e
  local buf="$FIXTURE/buffer.jsonl"
  bash "$SCRIPT" decision-append --buffer "$buf" --permission 'Bash(p1)' --decision promote
  bash "$SCRIPT" decision-append --buffer "$buf" --permission 'Bash(p2)' --decision keep-local
  # Each line is valid JSON with exactly 2 keys.
  while IFS= read -r line; do
    echo "$line" | jq -e 'keys | length == 2'
  done < "$buf"
}

@test "BTS-159 AC-3: --decision accept-danger emits the 6-field shape" {
  set -e
  local buf="$FIXTURE/buffer.jsonl"
  run bash "$SCRIPT" decision-append --buffer "$buf" \
    --permission 'Bash(ALLOW_DESTRUCTIVE=1 rm:*)' \
    --decision accept-danger \
    --risk 'r' --rationale 'why' --efficiency 'e' --reviewer 'zach'
  [ "$status" -eq 0 ]
  cat "$buf" | jq -e '
    .permission == "Bash(ALLOW_DESTRUCTIVE=1 rm:*)" and
    .decision == "accept-danger" and
    .risk == "r" and .rationale == "why" and
    .efficiency_justification == "e" and .reviewer == "zach"
  '
}

@test "BTS-159 AC-4: missing --permission exits 2 with no buffer write" {
  local buf="$FIXTURE/buffer.jsonl"
  run --separate-stderr bash "$SCRIPT" decision-append --buffer "$buf" --decision delete
  [ "$status" -eq 2 ]
  [ ! -f "$buf" ]
  [[ "$stderr" == *"permission"* ]]
}

@test "BTS-159 AC-4: missing --decision exits 2" {
  local buf="$FIXTURE/buffer.jsonl"
  run --separate-stderr bash "$SCRIPT" decision-append --buffer "$buf" --permission 'Bash(x)'
  [ "$status" -eq 2 ]
  [ ! -f "$buf" ]
  [[ "$stderr" == *"decision"* ]]
}

@test "BTS-159 AC-4: accept-danger missing required fields exits 2" {
  local buf="$FIXTURE/buffer.jsonl"
  # All four required fields → omit one (rationale).
  run --separate-stderr bash "$SCRIPT" decision-append --buffer "$buf" \
    --permission 'Bash(x)' --decision accept-danger \
    --risk 'r' --efficiency 'e' --reviewer 'z'
  [ "$status" -eq 2 ]
  [ ! -f "$buf" ]
  [[ "$stderr" == *"rationale"* ]]
}

@test "BTS-159 AC-4: accept-danger field == 'TODO' exits 2" {
  local buf="$FIXTURE/buffer.jsonl"
  run --separate-stderr bash "$SCRIPT" decision-append --buffer "$buf" \
    --permission 'Bash(x)' --decision accept-danger \
    --risk 'r' --rationale 'TODO' --efficiency 'e' --reviewer 'z'
  [ "$status" -eq 2 ]
  [ ! -f "$buf" ]
}

@test "BTS-159 AC-5: unknown --decision exits 2 listing valid set" {
  local buf="$FIXTURE/buffer.jsonl"
  run --separate-stderr bash "$SCRIPT" decision-append --buffer "$buf" \
    --permission 'Bash(x)' --decision nonsense
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"delete"* ]]
  [[ "$stderr" == *"accept-danger"* ]]
}

@test "BTS-159 AC-7: buffer built via decision-append is consumed by apply --decisions" {
  set -e
  local buf="$FIXTURE/buffer.jsonl"
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(real-tool:*)"]}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(stale:*)"]}}
EOF
  bash "$SCRIPT" decision-append --buffer "$buf" \
    --permission 'Bash(stale:*)' --decision delete
  # apply must accept the buffer without validation errors. We don't
  # assert specific behavior here (covered by BTS-149 tests) — only that
  # the pre-flight passes (no decision-shape complaints).
  run bash "$SCRIPT" apply --decisions "$buf" --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
}

@test "BTS-159 AC-9: /permissions-review skill prose uses decision-append (not legacy hand-assembled JSON)" {
  local skill="$BATS_TEST_DIRNAME/../../.claude/commands/permissions-review.md"
  [ -f "$skill" ]
  # Must reference the new substrate (positive).
  grep -q 'decision-append' "$skill"
  # Negative regression guard: the legacy form was a raw JSON example
  # `{"permission":"...","decision":"delete|promote|keep-local"}` in a
  # code block, instructing Claude to hand-assemble the JSON. That
  # specific pattern (an object literal pairing the two field names) is
  # the regression surface — if it returns, decision-append got bypassed.
  ! grep -qE '"permission":\s*"[^"]*"\s*,\s*"decision":' "$skill"
}

@test "BTS-159 AC-4: missing --buffer exits 2 with no write" {
  # Parity coverage with --permission and --decision missing tests above.
  run --separate-stderr bash "$SCRIPT" decision-append --permission 'Bash(x)' --decision delete
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"buffer"* ]]
}

@test "BTS-159 AC-8: extra fields on non-accept-danger decisions are silently ignored" {
  set -e
  local buf="$FIXTURE/buffer.jsonl"
  bash "$SCRIPT" decision-append --buffer "$buf" \
    --permission 'Bash(x)' --decision delete \
    --risk 'should-not-appear' --rationale 'should-not-appear' \
    --efficiency 'should-not-appear' --reviewer 'should-not-appear'
  cat "$buf" | jq -e 'keys | length == 2'
  cat "$buf" | jq -e 'has("risk") | not'
}

@test "BTS-154 AC-7: stale accept_danger log entry for now-safe keyword stays harmless" {
  set -e
  # Prior to BTS-154, Bash(done) was DANGER and operators added accept_danger
  # overrides via /permissions-review. Post-BTS-154, the keyword pre-check
  # short-circuits to safe BEFORE the override is consulted. The stale log
  # entry must not produce errors or change classification.
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(done)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(done)": {
      "risk": "Zero practical risk — bash control-flow keyword.",
      "rationale": "Pre-BTS-154 false-positive override.",
      "efficiency_justification": "Suppress noise.",
      "reviewer": "test",
      "accept_danger": true
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.danger == 0'
  # The override path was never reached — entry is REVIEWED via the
  # accept_danger fallback OR safe via the pre-check. Either way: 0 DANGER,
  # exit 0, no errors on stderr.
}

@test "BTS-154 AC-5: dangerous shapes adjacent to keywords still classify as DANGER" {
  set -e
  # Compound-operator and redirect must still fire even if the leading token
  # is a keyword. Keyword exemption is for the bare-token / :* shapes only.
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(for f; rm -rf /)",
      "Bash(do echo > /etc/passwd)"
    ]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.danger == 2'
}

@test "file mutation commands flagged as DANGER" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(sort -o file.txt)", "Bash(git branch -D main)", "Bash(git tag -d v1)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.danger == 3'
}

@test "arbitrary execution flagged as DANGER" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(xargs -I {} cat {})", "Bash(env PATH=/tmp cmd)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.danger == 2'
}

@test "safe entries not flagged as DANGER" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)", "Bash(ls:*)", "Bash(bats:*)", "Bash(bash -n scripts/foo.sh)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.danger == 0'
}

@test "DANGER entry includes matched pattern name" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE"
  echo "$output" | jq -e '.entries[0].matched_pattern'
}


# =========================================================================
# Step 4: Log-based status classification (AC-4, AC-6)
# =========================================================================

@test "fully reviewed entry in log → REVIEWED status" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(git status:*)": {
      "risk": "LOW",
      "rationale": "Read-only git command",
      "efficiency_justification": "Used constantly during development",
      "reviewer": "zach",
      "reviewed_epoch": 1774200000
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.entries[0].status == "REVIEWED"'
  echo "$output" | jq -e '.reviewed == 1'
  echo "$output" | jq -e '.unreviewed == 0'
}

@test "stub entry with TODO rationale → UNREVIEWED" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(git status:*)": {
      "risk": "",
      "rationale": "TODO",
      "efficiency_justification": "",
      "reviewer": "",
      "reviewed_epoch": 0
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.entries[0].status == "UNREVIEWED"'
}

@test "entry not in log → UNREVIEWED" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {}
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.entries[0].status == "UNREVIEWED"'
}

@test "DANGER overrides REVIEWED log status" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(echo:*)": {
      "risk": "HIGH",
      "rationale": "Needed for output",
      "efficiency_justification": "Used in scripts",
      "reviewer": "zach",
      "reviewed_epoch": 1774200000
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.entries[0].status == "DANGER"'
  echo "$output" | jq -e '.danger == 1'
}

# =========================================================================
# BTS-143: accept_danger override — DANGER pattern + filled log entry with
# accept_danger:true → REVIEWED with risk_accepted:true preserved.
# =========================================================================

@test "BTS-143 AC-1: DANGER + accept_danger:true + filled fields → REVIEWED with risk_accepted" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(echo:*)": {
      "risk": "HIGH",
      "rationale": "Output is intentional; hooks gate destructive cases",
      "efficiency_justification": "Used constantly during development",
      "reviewer": "zach",
      "reviewed_epoch": 1777085000,
      "accept_danger": true
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.entries[0].status == "REVIEWED"'
  echo "$output" | jq -e '.entries[0].risk_accepted == true'
  echo "$output" | jq -e '.entries[0].matched_pattern != null and .entries[0].matched_pattern != ""'
  echo "$output" | jq -e '.danger == 0 and .reviewed == 1 and .unreviewed == 0'
}

@test "BTS-143 AC-2: DANGER + accept_danger:true + STUB rationale → DANGER (no override on incomplete)" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(echo:*)": {
      "risk": "HIGH",
      "rationale": "TODO",
      "efficiency_justification": "Used in scripts",
      "reviewer": "zach",
      "accept_danger": true
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.entries[0].status == "DANGER"'
  echo "$output" | jq -e '.danger == 1'
}

@test "BTS-143 AC-3: DANGER + accept_danger:false + filled fields → DANGER (must opt in)" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(echo:*)": {
      "risk": "HIGH",
      "rationale": "Filled but not accepting risk",
      "efficiency_justification": "Used in scripts",
      "reviewer": "zach",
      "accept_danger": false
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.entries[0].status == "DANGER"'
}

# =========================================================================
# BTS-144: promote-review subcommand for settings.local.json delta classification.
# =========================================================================

@test "BTS-144 AC-7: empty settings.local.json → empty output, exit 0" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(git:*)"]}}
EOF
  # No settings.local.json file at all.

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.candidates == [] and .counts.total == 0'
}

@test "BTS-144 AC-2: candidate set is local-minus-main (string equality)" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(other:*)"]}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(custom-tool:*)"]}}
EOF

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.counts.total == 1'
  echo "$output" | jq -e '.candidates[0].permission == "Bash(custom-tool:*)"'
}

@test "BTS-144 AC-3: redundant (covered by broader wildcard) → DELETE" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(git:*)"]}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(git status:*)"]}}
EOF

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.candidates[0].recommendation == "DELETE"'
  echo "$output" | jq -e '.candidates[0].reason | test("redundant.*Bash\\(git:\\*\\)")'
}

@test "BTS-144 AC-4: preset/ path → DELETE dead path" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": []}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(bash preset/old/script.sh)"]}}
EOF

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.candidates[0].recommendation == "DELETE"'
  echo "$output" | jq -e '.candidates[0].reason | test("dead path")'
}

@test "BTS-144 AC-5: env-prefix bypass with broadly-allowed underlying verb → DELETE one-shot" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(bash:*)"]}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(ALLOW_OUTSIDE_WORKSPACE=1 bash ./x.sh)"]}}
EOF

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.candidates[0].recommendation == "DELETE"'
  echo "$output" | jq -e '.candidates[0].reason | test("one-shot bypass")'
}

@test "BTS-144 AC-6: no rule matches → TRIAGE" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(other:*)"]}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(specific-cmd --flag)"]}}
EOF

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.candidates[0].recommendation == "TRIAGE"'
  echo "$output" | jq -e '.candidates[0].reason == "manual review required"'
}

@test "BTS-144 AC-1: JSON output shape includes candidates + counts.{delete,promote,triage,total}" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(git:*)"]}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(git status:*)", "Bash(specific-cmd)"]}}
EOF

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    (.candidates | type == "array") and
    (.counts.delete == 1) and
    (.counts.promote == 0) and
    (.counts.triage == 1) and
    (.counts.total == 2)
  '
}

@test "BTS-144 AC-9: counts.promote always 0 even with mixed candidates" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(bash:*)"]}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(ALLOW_OUTSIDE_WORKSPACE=1 bash ./x.sh)", "Bash(custom-tool:*)", "Bash(bash preset/old.sh)"]}}
EOF

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.counts.promote == 0'
}

@test "BTS-144 AC-8: text mode shows DELETE and TRIAGE group headers" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(git:*)"]}}
EOF
  cat > "$FIXTURE/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(git status:*)", "Bash(custom-tool:*)"]}}
EOF

  run bash "$SCRIPT" promote-review --settings-dir "$FIXTURE" --text
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "DELETE"
  echo "$output" | grep -q "TRIAGE"
}

@test "BTS-143 AC-7: text-mode shows [risk-accepted] annotation on override entry" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(echo:*)": {
      "risk": "HIGH",
      "rationale": "Output is intentional",
      "efficiency_justification": "Used constantly",
      "reviewer": "zach",
      "accept_danger": true
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json" --text
  [ "$status" -eq 0 ]
  echo "$output" | grep -F "risk-accepted"
}

@test "mixed statuses counted correctly" {
  set -e
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(ls:*)",
      "Bash(echo:*)"
    ]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(git status:*)": {
      "risk": "LOW",
      "rationale": "Read-only",
      "efficiency_justification": "Constant use",
      "reviewer": "zach",
      "reviewed_epoch": 1774200000
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.reviewed == 1'
  echo "$output" | jq -e '.unreviewed == 1'
  echo "$output" | jq -e '.danger == 1'
}


# =========================================================================
# Step 5: Exit codes (AC-2) — already covered by steps 3+4 tests
# =========================================================================
# Exit 0 tested in "fully reviewed entry in log → REVIEWED status"
# Exit 1 tested in "entry not in log → UNREVIEWED"
# Exit 2 tested in "broad wildcard flagged as DANGER"


# =========================================================================
# Step 6: Error handling (AC-8, AC-9)
# =========================================================================

@test "missing log file → UNREVIEWED with stderr note" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/nonexistent.json"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "NOTE: .*not found.*run permissions-audit.sh init"
  # The JSON output should still be valid
  echo "$output" | grep -v "^NOTE:" | jq -e '.unreviewed == 1'
}

@test "invalid JSON log → exit 2 with error on stderr" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF
  echo "not json {{{" > "$FIXTURE/bad-log.json"

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/bad-log.json"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "ERROR: .*not valid JSON"
}


# =========================================================================
# Step 7: Text output mode (AC-5)
# =========================================================================

@test "check --text outputs DANGER entries first" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)", "Bash(echo:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --text
  echo "$output" | grep -q "DANGER"
  # DANGER section header appears before UNREVIEWED section header
  local danger_line unreviewed_line
  danger_line=$(echo "$output" | grep -n "^--- DANGER" | head -1 | cut -d: -f1)
  unreviewed_line=$(echo "$output" | grep -n "^--- UNREVIEWED" | head -1 | cut -d: -f1)
  [ "$danger_line" -lt "$unreviewed_line" ]
}

@test "check --text shows matched pattern for DANGER entries" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(echo:*)"]
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --text
  echo "$output" | grep -q "broad-wildcard"
}

@test "check --text suppresses REVIEWED without --verbose" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(git status:*)": {
      "risk": "LOW",
      "rationale": "Read-only",
      "efficiency_justification": "Constant use",
      "reviewer": "zach",
      "reviewed_epoch": 1774200000
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --text
  # Should NOT show the reviewed entry details
  ! echo "$output" | grep -q "Bash(git status:\*)"
}

@test "check --text --verbose shows REVIEWED entries" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(git status:*)": {
      "risk": "LOW",
      "rationale": "Read-only",
      "efficiency_justification": "Constant use",
      "reviewer": "zach",
      "reviewed_epoch": 1774200000
    }
  }
}
EOF

  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --text --verbose
  echo "$output" | grep -q "REVIEWED"
  echo "$output" | grep -q "Bash(git status:\*)"
  # AC-5: verbose shows risk and rationale
  echo "$output" | grep -q "LOW"
  echo "$output" | grep -q "Read-only"
}


# =========================================================================
# Step 8: Init command (AC-7)
# =========================================================================

@test "init creates log with stubs for all entries" {
  rm -f "$FIXTURE/permissions-log.json"
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)", "Bash(ls:*)"]
  }
}
EOF

  run bash "$SCRIPT" init --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  [ -f "$FIXTURE/permissions-log.json" ]
  jq -e '.entries["Bash(git status:*)"].rationale == "TODO"' "$FIXTURE/permissions-log.json"
  jq -e '.entries["Bash(ls:*)"].risk == ""' "$FIXTURE/permissions-log.json"
}

@test "init preserves existing reviewed entries" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)", "Bash(ls:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(git status:*)": {
      "risk": "LOW",
      "rationale": "Read-only",
      "efficiency_justification": "Constant use",
      "reviewer": "zach",
      "reviewed_epoch": 1774200000
    }
  }
}
EOF

  run bash "$SCRIPT" init --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  # Existing reviewed entry preserved
  jq -e '.entries["Bash(git status:*)"].rationale == "Read-only"' "$FIXTURE/permissions-log.json"
  # New entry gets stub
  jq -e '.entries["Bash(ls:*)"].rationale == "TODO"' "$FIXTURE/permissions-log.json"
}

@test "init is idempotent — running twice preserves reviewed data" {
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  }
}
EOF
  cat > "$FIXTURE/permissions-log.json" <<'EOF'
{
  "entries": {
    "Bash(git status:*)": {
      "risk": "LOW",
      "rationale": "Read-only",
      "efficiency_justification": "Constant use",
      "reviewer": "zach",
      "reviewed_epoch": 1774200000
    }
  }
}
EOF

  bash "$SCRIPT" init --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  bash "$SCRIPT" init --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"

  jq -e '.entries["Bash(git status:*)"].rationale == "Read-only"' "$FIXTURE/permissions-log.json"
  jq -e '.entries["Bash(git status:*)"].reviewer == "zach"' "$FIXTURE/permissions-log.json"
}

@test "init with no existing log creates new file" {
  rm -f "$FIXTURE/permissions-log.json"
  cat > "$FIXTURE/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(ls:*)"]
  }
}
EOF

  run bash "$SCRIPT" init --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  jq -e '.entries | length == 1' "$FIXTURE/permissions-log.json"
}

# =========================================================================
# BTS-149: apply --decisions <jsonl> — interactive triage substrate
# Step 3: scaffolding (AC-1, AC-2, AC-4 partial — empty/invalid input,
# decision validation, envelope shape, no-mutation no-backup)
# =========================================================================

@test "BTS-149 AC-1: apply with empty decisions file returns zero envelope" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  : > "$FIXTURE/decisions.jsonl"
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == 0'
  echo "$output" | jq -e '.skipped == 0'
  echo "$output" | jq -e '.errors == []'
}

@test "BTS-149 AC-1: apply emits skipped count for keep-local decisions" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(ls:*)","decision":"keep-local"}
{"permission":"Bash(ls:*)","decision":"keep-local"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == 0'
  echo "$output" | jq -e '.skipped == 2'
}

@test "BTS-149 AC-2: apply rejects malformed JSONL with exit 2" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(ls:*)","decision":"keep-local"}
not-valid-json-here
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
}

@test "BTS-149 AC-2: apply rejects unknown decision verb with exit 2" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(ls:*)","decision":"banana"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
}

@test "BTS-149 AC-2: apply rejects decision missing 'permission' field with exit 2" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"decision":"delete"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
}

@test "BTS-149 AC-4: apply with no mutating decisions creates no .bak files" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(ls:*)","decision":"keep-local"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  [ ! -f "$FIXTURE/settings.json.bak" ]
  [ ! -f "$FIXTURE/settings.local.json.bak" ]
}

@test "BTS-149: apply requires --decisions argument" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  run bash "$SCRIPT" apply --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -ne 0 ]
}

# Step 4: AC-3 (delete decision)

@test "BTS-149 AC-3: delete removes entry from settings.local.json allow list" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)","Bash(stale:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(stale:*)","decision":"delete"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == 1'
  echo "$output" | jq -e '.skipped == 0'
  jq -e '.permissions.allow == ["Bash(rm:*)"]' "$FIXTURE/settings.local.json"
  jq -e '.permissions.allow == ["Bash(ls:*)"]' "$FIXTURE/settings.json"
}

@test "BTS-149 AC-3: delete of permission absent from local is a skip not an apply" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(absent:*)","decision":"delete"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == 0'
  echo "$output" | jq -e '.skipped == 1'
  jq -e '.permissions.allow == ["Bash(rm:*)"]' "$FIXTURE/settings.local.json"
}

@test "BTS-149 AC-4: delete creates and removes .bak file on success" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(stale:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(stale:*)","decision":"delete"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  [ ! -f "$FIXTURE/settings.json.bak" ]
  [ ! -f "$FIXTURE/settings.local.json.bak" ]
}

@test "BTS-149 AC-4: refuses to apply when stale .bak files already exist" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(stale:*)"]}}
JSON
  echo '{"permissions":{"allow":[]}}' > "$FIXTURE/settings.local.json.bak"
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(stale:*)","decision":"delete"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -ne 0 ]
  # original local file untouched (still has the entry)
  jq -e '.permissions.allow == ["Bash(stale:*)"]' "$FIXTURE/settings.local.json"
}

@test "BTS-149 AC-3: delete with missing settings.local.json is a skip" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(stale:*)","decision":"delete"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == 0'
  echo "$output" | jq -e '.skipped == 1'
}

# Step 5: AC-3 (promote)

@test "BTS-149 AC-3: promote moves entry from local to main allow list" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)","Bash(promoteme:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(promoteme:*)","decision":"promote"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == 1'
  echo "$output" | jq -e '.skipped == 0'
  jq -e '.permissions.allow == ["Bash(ls:*)","Bash(promoteme:*)"]' "$FIXTURE/settings.json"
  jq -e '.permissions.allow == ["Bash(rm:*)"]' "$FIXTURE/settings.local.json"
}

@test "BTS-149 AC-3: promote is idempotent when already in main allow list" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)","Bash(promoteme:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(promoteme:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(promoteme:*)","decision":"promote"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  # Documented semantic: promote increments `applied` whenever local was
  # mutated, even when main was already up-to-date (idempotent on main).
  echo "$output" | jq -e '.applied == 1'
  echo "$output" | jq -e '.skipped == 0'
  # main list should not contain duplicate
  count=$(jq -r '[.permissions.allow[] | select(. == "Bash(promoteme:*)")] | length' "$FIXTURE/settings.json")
  [ "$count" -eq 1 ]
  # local file should still have the promote remove the entry
  jq -e '.permissions.allow == []' "$FIXTURE/settings.local.json"
}

@test "BTS-149 AC-3: promote with permission absent from local still appends to main" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":[]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(newperm:*)","decision":"promote"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == 1'
  jq -e '.permissions.allow == ["Bash(ls:*)","Bash(newperm:*)"]' "$FIXTURE/settings.json"
}

@test "BTS-149 AC-4: promote creates .bak for both files and cleans up on success" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  cat > "$FIXTURE/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(promoteme:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(promoteme:*)","decision":"promote"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  [ ! -f "$FIXTURE/settings.json.bak" ]
  [ ! -f "$FIXTURE/settings.local.json.bak" ]
}

# Step 6: AC-3 + AC-5 (accept-danger decision)

@test "BTS-149 AC-3: accept-danger writes log entry with accept_danger:true" {
  set -e
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(rm:*)","decision":"accept-danger","risk":"data loss","rationale":"used for cleanup scripts","efficiency_justification":"saves 5 prompts/day","reviewer":"zach"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.applied == 1'
  jq -e '.entries["Bash(rm:*)"].accept_danger == true' "$FIXTURE/permissions-log.json"
  jq -e '.entries["Bash(rm:*)"].risk == "data loss"' "$FIXTURE/permissions-log.json"
  jq -e '.entries["Bash(rm:*)"].rationale == "used for cleanup scripts"' "$FIXTURE/permissions-log.json"
  jq -e '.entries["Bash(rm:*)"].efficiency_justification == "saves 5 prompts/day"' "$FIXTURE/permissions-log.json"
  jq -e '.entries["Bash(rm:*)"].reviewer == "zach"' "$FIXTURE/permissions-log.json"
}

@test "BTS-149 AC-5: accept-danger missing risk field exits 2 with no mutation" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(rm:*)","decision":"accept-danger","rationale":"x","efficiency_justification":"y","reviewer":"z"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
  # log untouched (no entry added)
  jq -e '.entries == {}' "$FIXTURE/permissions-log.json"
}

@test "BTS-149 AC-5: accept-danger with TODO sentinel field exits 2" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(rm:*)","decision":"accept-danger","risk":"TODO","rationale":"x","efficiency_justification":"y","reviewer":"z"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
  jq -e '.entries == {}' "$FIXTURE/permissions-log.json"
}

@test "BTS-149 AC-5: accept-danger with empty-string field exits 2" {
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(rm:*)","decision":"accept-danger","risk":"","rationale":"x","efficiency_justification":"y","reviewer":"z"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 2 ]
  jq -e '.entries == {}' "$FIXTURE/permissions-log.json"
}

@test "BTS-149 AC-3: accept-danger then check classifies as REVIEWED risk-accepted" {
  set -e
  # Use a permission that would normally classify as DANGER (matches "rm" pattern)
  cat > "$FIXTURE/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(rm:*)"]}}
JSON
  cat > "$FIXTURE/decisions.jsonl" <<'JSONL'
{"permission":"Bash(rm:*)","decision":"accept-danger","risk":"deletes files","rationale":"cleanup","efficiency_justification":"daily use","reviewer":"zach"}
JSONL
  run bash "$SCRIPT" apply --decisions "$FIXTURE/decisions.jsonl" \
    --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  [ "$status" -eq 0 ]

  # Now check should classify as REVIEWED with risk_accepted:true
  run bash "$SCRIPT" check --settings-dir "$FIXTURE" --log "$FIXTURE/permissions-log.json"
  echo "$output" | jq -e '.danger == 0'
  echo "$output" | jq -e '.reviewed == 1'
  echo "$output" | jq -e '.entries[0].status == "REVIEWED"'
  echo "$output" | jq -e '.entries[0].risk_accepted == true'
}
