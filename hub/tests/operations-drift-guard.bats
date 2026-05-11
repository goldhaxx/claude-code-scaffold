#!/usr/bin/env bats
# BTS-419 — substrate-staleness drift-guard.
#
# Asserts that linear_assert_project_id_emitted enforces the contract:
# "if project_id is configured, the resolved command for any project-scoped
# verb MUST contain --project-id". Hard-fail with ALLOW_STALE_SUBSTRATE=1
# bypass.

bats_require_minimum_version 1.5.0

OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.claude"
}

teardown() {
  rm -rf "$PROJECT"
}

# ===========================================================================
# Step 1 — helper exists, clean pass-through paths
# ===========================================================================

@test "BTS-419 Step 1a: linear_assert_project_id_emitted is defined" {
  source "$OPS"
  declare -F linear_assert_project_id_emitted >/dev/null
}

@test "BTS-419 Step 1b: helper passes through when project_id is empty" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  output=$(linear_assert_project_id_emitted "backlog.list" "" "$input")
  [ "$output" = "$input" ]
}

@test "BTS-419 Step 1c: helper passes through when command already has --project-id" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --project-id UUID --team T"}}'
  output=$(linear_assert_project_id_emitted "backlog.list" "UUID" "$input")
  [ "$output" = "$input" ]
}

# ===========================================================================
# Step 2 — fire path: project_id set + command lacks --project-id → ERROR
# ===========================================================================

@test "BTS-419 Step 2a: helper fires with non-zero exit when project_id set but --project-id missing" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  run linear_assert_project_id_emitted "backlog.list" "UUID-1" "$input"
  [ "$status" -ne 0 ]
}

@test "BTS-419 Step 2b: fire path stderr contains 'stale substrate'" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  run linear_assert_project_id_emitted "backlog.list" "UUID-1" "$input"
  [[ "$output" == *"stale substrate"* ]]
}

@test "BTS-419 Step 2c: fire path stderr names the remediation recipe" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  run linear_assert_project_id_emitted "backlog.list" "UUID-1" "$input"
  [[ "$output" == *"ccanvil-sync.sh pull"* ]]
}

# ===========================================================================
# Step 3 — AC-7 operator-grade message: project_id value, verb name, cd recipe
# ===========================================================================

@test "BTS-419 Step 3a: fire path stderr contains the literal project_id value" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  run linear_assert_project_id_emitted "backlog.list" "PROJ-UUID-XYZ" "$input"
  [[ "$output" == *"PROJ-UUID-XYZ"* ]]
}

@test "BTS-419 Step 3b: fire path stderr names the verb being resolved" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  run linear_assert_project_id_emitted "idea.review-icebox" "UUID-1" "$input"
  [[ "$output" == *"idea.review-icebox"* ]]
}

@test "BTS-419 Step 3c: fire path stderr includes a 'cd' recipe prefix" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  run linear_assert_project_id_emitted "backlog.list" "UUID-1" "$input"
  [[ "$output" == *"cd "* ]]
}

# ===========================================================================
# Step 4 — AC-5: no fire on non-project-scoped verbs (ticket.transition,
# work.resolve). These verbs operate on a single ticket identifier; the
# project filter is not part of their contract surface, so the guard must
# NOT fire even when project_id is configured.
# ===========================================================================

_with_linear_routing_and_project_id() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project_id":"PROJ-UUID-1","team":"Blocktech Solutions","idea_label":"idea","state_ids":{"done":"STATE-DONE","backlog":"STATE-BL","todo":"STATE-TD","in_progress":"STATE-IP"}}}}}
JSON
}

@test "BTS-419 Step 4a: ticket.transition does NOT trigger staleness guard when project_id is set" {
  _with_linear_routing_and_project_id
  run bash "$OPS" resolve ticket.transition BTS-100 done --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"stale substrate"* ]]
  # Sanity: the resolved command is the canonical save-issue shape, no project filter.
  echo "$output" | jq -e '.invocation.command | contains("save-issue") and contains("STATE-DONE")'
}

@test "BTS-419 Step 4b: work.resolve does NOT trigger staleness guard when project_id is set" {
  _with_linear_routing_and_project_id
  run bash "$OPS" resolve work.resolve BTS-100 --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"stale substrate"* ]]
}

# ===========================================================================
# Step 5 — ALLOW_STALE_SUBSTRATE=1 bypass: operator-controlled emergency
# escape valve. Matches the ALLOW_DESTRUCTIVE / ALLOW_MAIN / ALLOW_OUTSIDE
# pattern. Bypass turns the hard-fail into a pass-through; a single-line
# WARN: advisory may go to stderr (informational, not blocking).
# ===========================================================================

@test "BTS-419 Step 5a: ALLOW_STALE_SUBSTRATE=1 turns the hard-fail into pass-through" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  ALLOW_STALE_SUBSTRATE=1 output=$(linear_assert_project_id_emitted "backlog.list" "UUID-1" "$input")
  [ "$output" = "$input" ]
}

@test "BTS-419 Step 5b: ALLOW_STALE_SUBSTRATE=1 exits 0 (not 1)" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  ALLOW_STALE_SUBSTRATE=1 run linear_assert_project_id_emitted "backlog.list" "UUID-1" "$input"
  [ "$status" -eq 0 ]
}

@test "BTS-419 Step 5c: ALLOW_STALE_SUBSTRATE=1 does not emit 'stale substrate' ERROR text" {
  source "$OPS"
  input='{"invocation":{"command":"bash linear-query.sh list-issues --team T"}}'
  ALLOW_STALE_SUBSTRATE=1 run linear_assert_project_id_emitted "backlog.list" "UUID-1" "$input"
  [[ "$output" != *"ERROR: stale substrate"* ]]
}

# ===========================================================================
# Step 7 — AC-1 verb-loop positive fixture. With project_id configured and
# project (name) empty, EACH of the six project-scoped verbs MUST emit
# --project-id in its resolved command. End-to-end via operations.sh resolve.
# ===========================================================================

_with_project_id_only() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"project_id":"PROJ-UUID-LOOP","team":"Blocktech Solutions","idea_label":"idea","state_ids":{"backlog":"S-BL","triage":"S-TR","icebox":"S-IB"}}}}}
JSON
}

@test "BTS-419 Step 7a: backlog.list emits --project-id (project_id-only config)" {
  _with_project_id_only
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--project-id ")'
}

@test "BTS-419 Step 7b: idea.add emits --project-id (project_id-only config)" {
  _with_project_id_only
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--project-id ")'
}

@test "BTS-419 Step 7c: idea.list emits --project-id (project_id-only config)" {
  _with_project_id_only
  run bash "$OPS" resolve idea.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--project-id ")'
}

@test "BTS-419 Step 7d: idea.count emits --project-id (project_id-only config)" {
  _with_project_id_only
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--project-id ")'
}

@test "BTS-419 Step 7e: idea.triage emits --project-id (project_id-only config)" {
  _with_project_id_only
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--project-id ")'
}

@test "BTS-419 Step 7f: idea.review-icebox emits --project-id (project_id-only config)" {
  _with_project_id_only
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.invocation.command | contains("--project-id ")'
}

# ===========================================================================
# Step 8 — AC-2 no-empty-flag emission. With NEITHER project_id NOR project
# set, the resolved command MUST NOT carry the empty-value forms
# `--project ''` or `--project-id ''`. Mirrors BTS-407 AC-5 across all 6 verbs.
# ===========================================================================

_with_neither_project() {
  cat > "$PROJECT/.claude/ccanvil.json" <<'JSON'
{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}
JSON
  cat > "$PROJECT/.claude/ccanvil.local.json" <<'JSON'
{"integrations":{"routing":{"idea":"linear"},"providers":{"linear":{"team":"Blocktech Solutions","idea_label":"idea","state_ids":{"backlog":"S-BL","triage":"S-TR","icebox":"S-IB"}}}}}
JSON
}

@test "BTS-419 Step 8a: backlog.list emits no empty --project / --project-id flag" {
  _with_neither_project
  run bash "$OPS" resolve backlog.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  cmd=$(echo "$output" | jq -r '.invocation.command')
  [[ "$cmd" != *"--project ''"* ]]
  [[ "$cmd" != *"--project-id ''"* ]]
}

@test "BTS-419 Step 8b: idea.add emits no empty --project / --project-id flag" {
  _with_neither_project
  run bash "$OPS" resolve idea.add --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  cmd=$(echo "$output" | jq -r '.invocation.command')
  [[ "$cmd" != *"--project ''"* ]]
  [[ "$cmd" != *"--project-id ''"* ]]
}

@test "BTS-419 Step 8c: idea.list emits no empty --project / --project-id flag" {
  _with_neither_project
  run bash "$OPS" resolve idea.list --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  cmd=$(echo "$output" | jq -r '.invocation.command')
  [[ "$cmd" != *"--project ''"* ]]
  [[ "$cmd" != *"--project-id ''"* ]]
}

@test "BTS-419 Step 8d: idea.count emits no empty --project / --project-id flag" {
  _with_neither_project
  run bash "$OPS" resolve idea.count --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  cmd=$(echo "$output" | jq -r '.invocation.command')
  [[ "$cmd" != *"--project ''"* ]]
  [[ "$cmd" != *"--project-id ''"* ]]
}

@test "BTS-419 Step 8e: idea.triage emits no empty --project / --project-id flag" {
  _with_neither_project
  run bash "$OPS" resolve idea.triage --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  cmd=$(echo "$output" | jq -r '.invocation.command')
  [[ "$cmd" != *"--project ''"* ]]
  [[ "$cmd" != *"--project-id ''"* ]]
}

@test "BTS-419 Step 8f: idea.review-icebox emits no empty --project / --project-id flag" {
  _with_neither_project
  run bash "$OPS" resolve idea.review-icebox --project-dir "$PROJECT"
  [ "$status" -eq 0 ]
  cmd=$(echo "$output" | jq -r '.invocation.command')
  [[ "$cmd" != *"--project ''"* ]]
  [[ "$cmd" != *"--project-id ''"* ]]
}

# ===========================================================================
# BTS-418 — resolver-wrapper-flag-contract drift-guard
#
# Static-analysis fixture: for each http-mechanism resolver verb in
# linear_mcp_adapter, every emitted --<flag> MUST be accepted by the target
# linear-query.sh subcommand's case-arm parser. Catches BTS-407-shape
# regressions at merge time.
# ===========================================================================

LQ="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/linear-query.sh"

_emitted_flags() {
  # Extracts long-flag names (`--<name>`) from a resolver-output envelope's
  # invocation.command. Resolver convention is space-separated `--flag value`
  # only — `--flag=value` form is out of scope (no current resolver emits
  # it; see spec Out of Scope). Stdin sentinels like `-` (e.g.
  # `--input-json -`) are correctly non-matched by the regex.
  local envelope="$1"
  local cmd
  cmd=$(echo "$envelope" | jq -r '.invocation.command // ""')
  grep -oE -- '--[a-z][a-z0-9-]*' <<<"$cmd" | sort -u
}

_wrapper_accepted_flags() {
  # Extracts long-flag case-arms from a wrapper subcommand's argv parser.
  # Relies on `linear-query.sh` convention: each `cmd_<name>() {` body
  # opens at column 0 and closes with a column-0 `}`. If a future cmd_
  # function adds a nested helper definition or here-doc that closes at
  # column 0, the awk range would truncate. Audit before adding such a
  # construct; `declare -f` after sourcing the script is the structurally
  # robust alternative if this becomes a real risk.
  local subcmd="$1"
  local fn_name="cmd_$(echo "$subcmd" | tr -- '-' '_')"
  local opener="${fn_name}() {"
  awk -v opener="$opener" '
    $0 == opener { p = 1 }
    p == 1 { print }
    p == 1 && $0 == "}" { p = 0 }
  ' "$LQ" \
    | grep -oE '\-\-[a-z][a-z0-9-]*\)' \
    | tr -d ')' \
    | sort -u
}

_target_wrapper_subcmd() {
  local envelope="$1"
  local cmd
  cmd=$(echo "$envelope" | jq -r '.invocation.command // ""')
  awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /linear-query\.sh$/) { print $(i+1); exit }
      }
    }
  ' <<<"$cmd"
}

_check_flag_contract_envelope() {
  local verb="$1" envelope="$2"
  local target emitted accepted drift
  target=$(_target_wrapper_subcmd "$envelope")
  if [[ -z "$target" ]]; then
    return 0  # not a linear-query.sh invocation; nothing to check
  fi
  emitted=$(_emitted_flags "$envelope")
  accepted=$(_wrapper_accepted_flags "$target")
  drift=$(comm -23 <(echo "$emitted") <(echo "$accepted"))
  if [[ -z "$drift" ]]; then
    return 0
  fi
  while IFS= read -r flag; do
    [[ -z "$flag" ]] && continue
    echo "DRIFT: $verb emits $flag not accepted by linear-query.sh $target"
  done <<<"$drift"
  return 1
}

_check_flag_contract() {
  local verb="$1"; shift
  local envelope
  envelope=$(bash "$OPS" resolve "$verb" "$@" --project-dir "$PROJECT")
  _check_flag_contract_envelope "$verb" "$envelope"
}

# ---------------------------------------------------------------------------
# Step 1 — AC-1: resolver-side flag extraction
# ---------------------------------------------------------------------------

@test "BTS-418 Step 1a: _emitted_flags returns empty for command with no flags" {
  envelope='{"invocation":{"command":"bash .ccanvil/scripts/linear-query.sh list-issues"}}'
  result=$(_emitted_flags "$envelope")
  [ -z "$result" ]
}

@test "BTS-418 Step 1b: _emitted_flags extracts a single --flag" {
  envelope='{"invocation":{"command":"bash .ccanvil/scripts/linear-query.sh list-issues --team T"}}'
  result=$(_emitted_flags "$envelope")
  [ "$result" = "--team" ]
}

@test "BTS-418 Step 1c: _emitted_flags extracts the full sorted set from live backlog.list" {
  _with_linear_routing_and_project_id
  envelope=$(bash "$OPS" resolve backlog.list --project-dir "$PROJECT")
  result=$(_emitted_flags "$envelope")
  expected=$'--limit\n--project-id\n--state\n--team'
  [ "$result" = "$expected" ]
}

# ---------------------------------------------------------------------------
# Step 2 — AC-2: wrapper-side flag extraction
# ---------------------------------------------------------------------------

@test "BTS-418 Step 2a: linear-query.sh exists at expected path" {
  [ -f "$LQ" ]
}

@test "BTS-418 Step 2b: _wrapper_accepted_flags list-issues returns the cmd_list_issues case-arm set" {
  result=$(_wrapper_accepted_flags list-issues)
  expected=$'--label\n--limit\n--project\n--project-id\n--state\n--team'
  [ "$result" = "$expected" ]
}

@test "BTS-418 Step 2c: _wrapper_accepted_flags save-issue is non-empty and includes --id and --state" {
  result=$(_wrapper_accepted_flags save-issue)
  [[ "$result" == *"--id"* ]]
  [[ "$result" == *"--state"* ]]
}

# ---------------------------------------------------------------------------
# Step 3 — AC-5: target-wrapper-subcommand derivation
# ---------------------------------------------------------------------------

@test "BTS-418 Step 3a: _target_wrapper_subcmd returns 'list-issues' for backlog.list envelope" {
  envelope='{"invocation":{"command":"bash .ccanvil/scripts/linear-query.sh list-issues --team T"}}'
  result=$(_target_wrapper_subcmd "$envelope")
  [ "$result" = "list-issues" ]
}

@test "BTS-418 Step 3b: _target_wrapper_subcmd returns 'save-issue' for ticket.transition envelope" {
  envelope='{"invocation":{"command":"bash .ccanvil/scripts/linear-query.sh save-issue --id BTS-1 --state X"}}'
  result=$(_target_wrapper_subcmd "$envelope")
  [ "$result" = "save-issue" ]
}

@test "BTS-418 Step 3c: _target_wrapper_subcmd returns empty for non-wrapper command" {
  envelope='{"invocation":{"command":"echo hello"}}'
  result=$(_target_wrapper_subcmd "$envelope")
  [ -z "$result" ]
}

# ---------------------------------------------------------------------------
# Step 4 — AC-3 seed: contract-check clean state on backlog.list
# ---------------------------------------------------------------------------

@test "BTS-418 Step 4a: _check_flag_contract on backlog.list under full config exits 0 with empty stdout" {
  _with_linear_routing_and_project_id
  run _check_flag_contract backlog.list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Step 5 — AC-3: per-verb positive sweep, idea-class (6 verbs)
# ---------------------------------------------------------------------------

@test "BTS-418 Step 5a: backlog.list — emitted flags ⊆ list-issues accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract backlog.list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 5b: idea.add — emitted flags ⊆ save-issue accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract idea.add
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 5c: idea.list — emitted flags ⊆ list-issues accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract idea.list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 5d: idea.count — emitted flags ⊆ list-issues accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract idea.count
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 5e: idea.triage — emitted flags ⊆ list-issues accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract idea.triage
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 5f: idea.review-icebox — emitted flags ⊆ list-issues accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract idea.review-icebox
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Step 6 — AC-3: per-verb positive sweep, transition + reads/writes (8 verbs)
# ---------------------------------------------------------------------------

@test "BTS-418 Step 6a: ticket.transition BTS-418 todo — emitted flags ⊆ save-issue accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract ticket.transition BTS-418 todo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 6b: ticket.get BTS-418 — get-issue invocation, no flags emitted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract ticket.get BTS-418
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 6c: spec.read BTS-418 — emitted flags ⊆ get-document accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract spec.read BTS-418
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 6d: spec.write BTS-418 — emitted flags ⊆ save-document accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract spec.write BTS-418
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 6e: plan.read BTS-418 — emitted flags ⊆ get-document accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract plan.read BTS-418
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 6f: plan.write BTS-418 — emitted flags ⊆ save-document accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract plan.write BTS-418
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 6g: stasis.read feature BTS-418 — emitted flags ⊆ get-document accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract stasis.read feature BTS-418
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BTS-418 Step 6h: stasis.write feature BTS-418 — emitted flags ⊆ save-document accepted" {
  _with_linear_routing_and_project_id
  run _check_flag_contract stasis.write feature BTS-418
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Step 7 — AC-4 + AC-7: synthetic drift detection + operator-grade message
# ---------------------------------------------------------------------------

@test "BTS-418 Step 7a: synthetic --bogus-flag-xyz triggers DRIFT exit non-zero" {
  envelope='{"invocation":{"command":"bash .ccanvil/scripts/linear-query.sh list-issues --team T --bogus-flag-xyz V"}}'
  run _check_flag_contract_envelope backlog.list "$envelope"
  [ "$status" -ne 0 ]
}

@test "BTS-418 Step 7b: synthetic drift stdout matches DRIFT: <verb> emits <flag> not accepted by linear-query.sh <subcmd>" {
  envelope='{"invocation":{"command":"bash .ccanvil/scripts/linear-query.sh list-issues --team T --bogus-flag-xyz V"}}'
  run _check_flag_contract_envelope backlog.list "$envelope"
  [[ "$output" == *"DRIFT: backlog.list emits --bogus-flag-xyz not accepted by linear-query.sh list-issues"* ]]
}

# ---------------------------------------------------------------------------
# Step 8 — AC-6: empty-config strict subset still passes
# ---------------------------------------------------------------------------

@test "BTS-418 Step 8a: idea.list under _with_neither_project (no --project-id emitted) still passes contract-check" {
  _with_neither_project
  run _check_flag_contract idea.list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
