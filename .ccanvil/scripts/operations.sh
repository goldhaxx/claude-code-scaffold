#!/usr/bin/env bash
# operations.sh — Mechanism-agnostic routing layer for preset operations.
#
# Reads .claude/ccanvil.json and dispatches each operation to a
# pluggable provider via any supported mechanism (bash, mcp, cli, api, etc.).
# Zero-config projects resolve everything to local bash adapters.
#
# Exit codes:
#   0 — success
#   1 — operation error (unknown op, missing provider, invalid config)
#   2 — usage error
#
# Usage:
#   operations.sh resolve <operation> [args...] [--project-dir DIR]

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

PROJECT_DIR="."

# ---------------------------------------------------------------------------
# Operations registry — all 17 defined operations
# ---------------------------------------------------------------------------

# BTS-183: removed dead-code MCP-only verbs idea.{promote,defer,dismiss,merge},
# backlog.get, ticket.find-by-title — zero live callers in skills or scripts.
# State transitions go through ticket.transition (http); backlog.list covers
# read paths; ad-hoc title lookups belong in interactive MCP, not substrate.
is_valid_operation() {
  case "$1" in
    backlog.list|backlog.create|backlog.prioritize) return 0 ;;
    spec.read|spec.write|spec.list|spec.activate|spec.complete) return 0 ;;
    plan.read|plan.write) return 0 ;;
    stasis.read|stasis.write) return 0 ;;
    status.get|status.update) return 0 ;;
    pr.create|pr.list) return 0 ;;
    review.run) return 0 ;;
    idea.add|idea.list|idea.count|idea.triage|idea.sync) return 0 ;;
    idea.review-icebox) return 0 ;;
    work.resolve) return 0 ;;
    ticket.transition|ticket.get) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat >&2 <<'EOF'
Usage: operations.sh {resolve|exec|merge-config} <operation> [args...] [--project-dir DIR]

Operations:
  backlog.{list,create,prioritize,get}
  spec.{read,write,list,activate,complete}
  plan.{read,write}
  stasis.{read,write}
  status.{get,update}
  pr.{create,list}
  review.run
  idea.{add,list,count,triage,sync,promote,defer,dismiss,merge,review-icebox}
  work.resolve <ref>
  ticket.transition <id> <role>
EOF
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

CMD=""
OPERATION=""
OP_ARGS=""
OP_ARG2=""

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    resolve|exec|merge-config)
      CMD="$1"; shift
      # Next positional arg is the operation name
      if [[ $# -gt 0 && "$1" != --* ]]; then
        OPERATION="$1"; shift
      fi
      # Next positional arg (if any) is the operation argument (e.g., issue ID)
      if [[ $# -gt 0 && "$1" != --* ]]; then
        OP_ARGS="$1"; shift
      fi
      # Optional third positional — used by two-arg operations like
      # ticket.transition (<id> <role>). Single-arg ops leave OP_ARG2="".
      if [[ $# -gt 0 && "$1" != --* ]]; then
        OP_ARG2="$1"; shift
      fi
      ;;
    --project-dir)
      PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -z "$CMD" ]] && usage
[[ "$CMD" == "resolve" && -z "$OPERATION" ]] && usage

# ---------------------------------------------------------------------------
# Config reading
# ---------------------------------------------------------------------------

CONFIG_FILE=""

# _operator_config_path — Return the operator-config file path.
# Reads $HOME directly; emits empty when HOME is unset (treated as "no
# operator tier" by callers). BTS-316.
#
# Test-injection: CCANVIL_OPERATOR_CONFIG_OVERRIDE wins when set (mirrors
# LINEAR_QUERY_OVERRIDE pattern). Lets bats fixtures point at a temp file
# without mutating $HOME, so other config-reading tests see a clean
# operator-tier (empty / non-existent) without per-test HOME juggling.
_operator_config_path() {
  if [[ -n "${CCANVIL_OPERATOR_CONFIG_OVERRIDE:-}" ]]; then
    echo "$CCANVIL_OPERATOR_CONFIG_OVERRIDE"
  elif [[ -n "${HOME:-}" ]]; then
    echo "$HOME/.ccanvil/operator.json"
  else
    echo ""
  fi
}

# merge_config — 3-tier merge of operator + ccanvil.json (hub) +
# ccanvil.local.json (node).
#
# Tiers (lowest precedence first):
#   1. Operator: $HOME/.ccanvil/operator.json — operator-wide defaults (BTS-316)
#   2. Hub: <dir>/.claude/ccanvil.json — distributed via ccanvil-sync
#   3. Node: <dir>/.claude/ccanvil.local.json — local overrides
#
# Outputs the effective config JSON to stdout via RFC 7396 deep merge
# (jq's * operator). Later tiers override earlier ones; node wins on conflict.
#
# Missing tiers are skipped silently (no error). When all three are absent,
# emits {} and exits 0.
#
# Exit 0: success.
# Exit 1: any existing tier file contains invalid JSON; stderr names the file.
merge_config() {
  local dir="$1"
  local operator_file
  operator_file=$(_operator_config_path)
  local hub_file="$dir/.claude/ccanvil.json"
  local local_file="$dir/.claude/ccanvil.local.json"

  # Validate each tier file that exists. Order matters: error message
  # names the offending file, not a downstream symptom.
  if [[ -n "$operator_file" && -f "$operator_file" ]]; then
    if ! jq empty "$operator_file" 2>/dev/null; then
      echo "ERROR: $operator_file is not valid JSON" >&2
      return 1
    fi
  fi
  if [[ -f "$hub_file" ]]; then
    if ! jq empty "$hub_file" 2>/dev/null; then
      echo "ERROR: .claude/ccanvil.json is not valid JSON" >&2
      return 1
    fi
  fi
  if [[ -f "$local_file" ]]; then
    if ! jq empty "$local_file" 2>/dev/null; then
      echo "ERROR: .claude/ccanvil.local.json is not valid JSON" >&2
      return 1
    fi
  fi

  # Collect existing tier files in precedence order (operator → hub → node).
  local tiers=()
  if [[ -n "$operator_file" && -f "$operator_file" ]]; then
    tiers+=("$operator_file")
  fi
  if [[ -f "$hub_file" ]]; then
    tiers+=("$hub_file")
  fi
  if [[ -f "$local_file" ]]; then
    tiers+=("$local_file")
  fi

  # No tiers → empty config (preserves existing 2-tier "neither file" behavior).
  if (( ${#tiers[@]} == 0 )); then
    echo '{}'
    return 0
  fi

  # Single tier → emit its content directly (cheaper, identical to multi-tier
  # reduce when N=1).
  if (( ${#tiers[@]} == 1 )); then
    jq '.' "${tiers[0]}"
    return 0
  fi

  # Multi-tier deep merge. `reduce` walks tier files in order; later tiers
  # override earlier ones. Equivalent to .[0] * .[1] * .[2] for 3 tiers and
  # extends naturally if more tiers are added later.
  jq -s 'reduce .[] as $x ({}; . * $x)' "${tiers[@]}"
}

read_config() {
  local hub_file="$PROJECT_DIR/.claude/ccanvil.json"
  local local_file="$PROJECT_DIR/.claude/ccanvil.local.json"

  # No config files → all local (not an error)
  if [[ ! -f "$hub_file" && ! -f "$local_file" ]]; then
    CONFIG_FILE=""
    return 0
  fi

  # Merge configs into a temp file so downstream jq queries work unchanged
  local merged
  merged=$(merge_config "$PROJECT_DIR") || exit 1

  CONFIG_FILE=$(mktemp)
  trap 'rm -f "$CONFIG_FILE"' EXIT
  echo "$merged" > "$CONFIG_FILE"
}

# Extract the routing group from an operation name (e.g., "backlog.list" → "backlog")
operation_group() {
  echo "${1%%.*}"
}

# ---------------------------------------------------------------------------
# Local adapter definitions
# ---------------------------------------------------------------------------

local_adapter() {
  local op="$1"
  local cmd="" output_contract=""

  # work.resolve emits a direct identity shape (not the wrapped invocation
  # shape used by other ops) — it IS the result, not a plan to fetch one.
  if [[ "$op" == "work.resolve" ]]; then
    local wid="$OP_ARGS"
    local had_prefix=false
    if [[ "$wid" == local:* ]]; then
      wid="${wid#local:}"
      had_prefix=true
    fi
    if [[ -z "$wid" ]]; then
      echo "ERROR: work.resolve requires a work id argument" >&2
      exit 1
    fi
    # Whitespace rejects — a work id is an opaque identifier, not a description.
    if [[ "$wid" =~ [[:space:]] ]]; then
      echo "ERROR: work id '$wid' contains whitespace (looks like a description, not a reference)" >&2
      exit 1
    fi
    # Strict format check for BARE local IDs. Explicit `local:` prefix trusts caller.
    # Local bare IDs must look like an idea UID: letters+digits, at least one digit.
    if ! $had_prefix; then
      if [[ ! "$wid" =~ ^[a-z][a-z0-9-]*$ ]] || [[ ! "$wid" =~ [0-9] ]]; then
        echo "ERROR: '$wid' is not a recognizable work reference on a local-provider node (expected e.g. idea-29). Use 'local:<id>' to bypass this check." >&2
        exit 1
      fi
    fi
    local slug
    slug=$(slug_from_work_id "$wid")
    if [[ -z "$slug" ]]; then
      echo "ERROR: work id '$wid' derives to an empty slug" >&2
      exit 1
    fi
    jq -n --arg id "$wid" --arg slug "$slug" \
      '{"provider":"local","id":$id,"slug":$slug,"url":""}'
    return 0
  fi

  case "$op" in
    # --- backlog ---
    backlog.list)
      cmd=".ccanvil/scripts/docs-check.sh list-specs"
      output_contract='["feature_id","status","created"]'
      ;;
    backlog.create)
      cmd=".ccanvil/scripts/docs-check.sh create-spec"
      output_contract='["feature_id","status"]'
      ;;
    backlog.prioritize)
      cmd=".ccanvil/scripts/docs-check.sh list-specs"
      output_contract='["feature_id","status","priority"]'
      ;;
    # --- spec ---
    spec.read)
      cmd="cat docs/spec.md"
      output_contract='["feature_id","status","body"]'
      ;;
    spec.write)
      cmd="cp .ccanvil/templates/spec.md docs/spec.md"
      output_contract='["feature_id"]'
      ;;
    spec.list)
      cmd=".ccanvil/scripts/docs-check.sh list-specs"
      output_contract='["feature_id","status","created"]'
      ;;
    spec.activate)
      cmd=".ccanvil/scripts/docs-check.sh activate"
      output_contract='["feature_id","branch"]'
      ;;
    spec.complete)
      cmd=".ccanvil/scripts/docs-check.sh complete"
      output_contract='["feature_id","status"]'
      ;;
    # --- plan ---
    plan.read)
      cmd="cat docs/plan.md"
      output_contract='["feature_id","spec_hash","body"]'
      ;;
    plan.write)
      cmd="cp .ccanvil/templates/plan.md docs/plan.md"
      output_contract='["feature_id"]'
      ;;
    # --- stasis ---
    stasis.read)
      cmd="cat docs/stasis.md"
      output_contract='["feature_id","plan_hash","body"]'
      ;;
    stasis.write)
      cmd="cp .ccanvil/templates/stasis.md docs/stasis.md"
      output_contract='["feature_id"]'
      ;;
    # --- status ---
    status.get)
      cmd=".ccanvil/scripts/docs-check.sh status"
      output_contract='["spec","plan","stasis"]'
      ;;
    status.update)
      cmd=".ccanvil/scripts/docs-check.sh validate"
      output_contract='["result","details"]'
      ;;
    # --- pr ---
    pr.create)
      cmd="gh pr create --draft"
      output_contract='["url","number"]'
      ;;
    pr.list)
      cmd="gh pr list --json number,title,state"
      output_contract='["number","title","state"]'
      ;;
    # --- review ---
    review.run)
      cmd="echo '{\"status\":\"not_implemented\",\"concerns\":[]}'"
      output_contract='["status","concerns"]'
      ;;
    # --- idea ---
    # Title + body are passed as trailing positional args by the skill
    # when invoking idea.add (out-of-band from operations.sh args).
    idea.add)
      cmd=".ccanvil/scripts/docs-check.sh idea-add"
      output_contract='["uid","title"]'
      ;;
    idea.list)
      cmd=".ccanvil/scripts/docs-check.sh idea-list"
      output_contract='["uid","created","title","status"]'
      ;;
    idea.count)
      # BTS-164: local-routed idea.count points at idea-count-local — a
      # rename of the original cmd_idea_count internal in Step 5. Until that
      # step lands, the command is invocable but resolves to an undefined
      # subcommand; tests cover the resolver shape, not execution.
      cmd=".ccanvil/scripts/docs-check.sh idea-count-local ${PROJECT_DIR}"
      output_contract='["total","triage","backlog","icebox","canceled","duplicate"]'
      ;;
    idea.triage)
      # Uses new-vocab "triage" filter; cmd_idea_list translation table
      # folds legacy status="new" entries in transparently.
      cmd=".ccanvil/scripts/docs-check.sh idea-list --status triage"
      output_contract='["uid","created","title","status"]'
      ;;
    idea.sync)
      # BTS-179: resolver returns idea-pending-replay (the dispatch
      # primitive). idea-sync remains the enumerate-only primitive for
      # backwards compat. Skill prose collapses to single resolve+eval.
      cmd=".ccanvil/scripts/docs-check.sh idea-pending-replay"
      output_contract='["synced","failed","pending","entries"]'
      ;;
    idea.review-icebox)
      cmd=".ccanvil/scripts/docs-check.sh idea-review-icebox"
      output_contract='["uid","created","title","status"]'
      ;;
    # BTS-183: idea.{promote,defer,dismiss,merge}, ticket.find-by-title
    # removed — zero live callers. Idea state mutations route through
    # ticket.transition on Linear-routed nodes; local-routed nodes use
    # `idea-update <uid> <target>` directly via the skill.
    ticket.transition)
      # ticket.transition is a Linear-specific primitive (state-ID based).
      # On local-provider nodes there is no equivalent surface — fail loud
      # rather than silently succeeding with an empty command.
      echo "ERROR: provider 'local' does not support ticket.transition — configure a Linear provider in .claude/ccanvil.json to enable" >&2
      exit 1
      ;;
  esac

  jq -n --arg cmd "$cmd" --argjson output "$output_contract" \
    '{"provider":"local","mechanism":"bash","invocation":{"command":$cmd},"contract":{"output":$output}}'
}

# ---------------------------------------------------------------------------
# MCP adapter definitions (Linear)
# ---------------------------------------------------------------------------

# linear_state_id — read a state UUID by role from the Linear provider config.
# Roles: triage | backlog | icebox | canceled | duplicate.
# Prints the empty string when the role is not configured so callers can
# treat absence as "not yet populated; fall back to name-based dispatch".
linear_state_id() {
  local provider_config="$1" role="$2"
  echo "$provider_config" | jq -r --arg r "$role" '.state_ids[$r] // ""'
}

# slug_from_work_id — derive a filesystem-safe, branch-safe slug from a work id.
# Lowercases alpha; replaces any character outside [a-z0-9-] with a single `-`;
# collapses runs of `-`; trims leading/trailing `-`. Deterministic, provider-
# agnostic. Examples:
#   BTS-130           → bts-130
#   idea-29           → idea-29
#   owner/repo#123    → owner-repo-123
slug_from_work_id() {
  local id="$1"
  echo "$id" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9-]\{1,\}/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

linear_mcp_adapter() {
  local op="$1" provider_config="$2" op_args="$3"
  local tool="" output_contract="" field_map=""
  local project team idea_label idea_status icebox_status workspace
  project=$(echo "$provider_config" | jq -r '.project // ""')
  team=$(echo "$provider_config" | jq -r '.team // ""')
  idea_label=$(echo "$provider_config" | jq -r '.idea_label // "idea"')
  idea_status=$(echo "$provider_config" | jq -r '.idea_status // "Idea"')
  icebox_status=$(echo "$provider_config" | jq -r '.icebox_status // "Icebox"')
  workspace=$(echo "$provider_config" | jq -r '.workspace // ""')

  # work.resolve emits a direct identity shape (see local_adapter for rationale).
  if [[ "$op" == "work.resolve" ]]; then
    local wid="$op_args"
    local had_prefix=false
    if [[ "$wid" == linear:* ]]; then
      wid="${wid#linear:}"
      had_prefix=true
    fi
    if [[ -z "$wid" ]]; then
      echo "ERROR: work.resolve requires a work id argument" >&2
      exit 1
    fi
    if [[ "$wid" =~ [[:space:]] ]]; then
      echo "ERROR: work id '$wid' contains whitespace (looks like a description, not a reference)" >&2
      exit 1
    fi
    # Strict format check for BARE Linear IDs: must match TEAM-N (e.g., BTS-130).
    # Explicit `linear:` prefix trusts caller intent and bypasses the check.
    if ! $had_prefix; then
      if [[ ! "$wid" =~ ^[A-Z]+-[0-9]+$ ]]; then
        echo "ERROR: '$wid' is not a valid Linear ticket key (expected e.g. BTS-130). Use 'linear:<id>' to bypass this check." >&2
        exit 1
      fi
    fi
    local slug url=""
    slug=$(slug_from_work_id "$wid")
    if [[ -z "$slug" ]]; then
      echo "ERROR: work id '$wid' derives to an empty slug" >&2
      exit 1
    fi
    [[ -n "$workspace" ]] && url="https://linear.app/${workspace}/issue/${wid}"
    jq -n --arg id "$wid" --arg slug "$slug" --arg url "$url" \
      '{"provider":"linear","id":$id,"slug":$slug,"url":$url}'
    return 0
  fi

  case "$op" in
    backlog.list)
      # BTS-175: http migration. Filter by --state <backlog_state_id> only —
      # NO label filter, so the resolver returns the canonical "everything in
      # Backlog state" view. Anti-pattern: do NOT proxy backlog reasoning
      # through idea.list (which filters by label=idea and silently hides
      # scaffold-labeled tickets).
      local backlog_state_id
      backlog_state_id=$(linear_state_id "$provider_config" "backlog")
      if [[ -z "$backlog_state_id" ]]; then
        echo "ERROR: backlog.list: state_ids.backlog not configured for Linear provider" >&2
        exit 1
      fi
      output_contract='["id","title","status","priority","createdAt"]'
      jq -n --arg project "$project" --arg team "$team" --arg state_id "$backlog_state_id" \
        --argjson output "$output_contract" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh list-issues" +
                      " --project " + ($project | @sh) +
                      " --team " + ($team | @sh) +
                      " --state " + ($state_id | @sh) +
                      " --limit 250"),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output }
        }'
      ;;
    # BTS-183: backlog.get removed — dead code. Use backlog.list.
    # --- idea operations ---
    # BTS-166: migrated from MCP to http. The wrapper (linear-query.sh) emits
    # GraphQL directly; resolvers describe the structural shape (team/project/
    # label/state) and the skill or script consumer evals the command. For
    # idea.add the consumer pipes a stdin-JSON object carrying title +
    # description (linear-query.sh save-issue --input-json -); for idea.list
    # / idea.triage / idea.review-icebox the consumer eval's directly.
    idea.add)
      output_contract='["id","title","status"]'
      local triage_state_id
      triage_state_id=$(linear_state_id "$provider_config" "triage")
      jq -n --arg project "$project" --arg team "$team" --arg label "$idea_label" \
        --arg state_id "$triage_state_id" \
        --argjson output "$output_contract" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh save-issue" +
                      " --team " + ($team | @sh) +
                      " --project " + ($project | @sh) +
                      " --labels " + ($label | @sh) +
                      (if $state_id != "" then " --state " + ($state_id | @sh) else "" end)),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output }
        }'
      ;;
    idea.list)
      output_contract='["id","title","status","createdAt"]'
      jq -n --arg project "$project" --arg team "$team" --arg label "$idea_label" \
        --argjson output "$output_contract" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh list-issues" +
                      " --project " + ($project | @sh) +
                      " --team " + ($team | @sh) +
                      " --label " + ($label | @sh) +
                      " --limit 250"),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output }
        }'
      ;;
    idea.count)
      # BTS-164: emit mechanism=http with a linear-query.sh invocation. The
      # consumer (cmd_idea_count) shells out to the wrapper, parses the
      # resulting list, and aggregates counts by status. linear-query.sh
      # owns auth (BTS-167: auto-sources .env when LINEAR_API_KEY is unset)
      # + transport. `auth_env` is informational on the resolver JSON;
      # consumers no longer pre-flight against it (the substrate handles
      # the contract end-to-end).
      output_contract='["id","status","statusType"]'
      jq -n --arg project "$project" --arg team "$team" --arg label "$idea_label" \
        --argjson output "$output_contract" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh list-issues" +
                      " --project " + ($project | @sh) +
                      " --team " + ($team | @sh) +
                      " --label " + ($label | @sh) +
                      " --limit 250"),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output }
        }'
      ;;
    idea.triage)
      # BTS-166: state-id when configured (disambiguation-proof), else "triage"
      # which linear-query.sh list-issues filters by state.type.eq.
      output_contract='["id","title","status","createdAt"]'
      local triage_state_id triage_state_arg
      triage_state_id=$(linear_state_id "$provider_config" "triage")
      if [[ -n "$triage_state_id" ]]; then
        triage_state_arg="$triage_state_id"
      else
        triage_state_arg="triage"
      fi
      jq -n --arg project "$project" --arg team "$team" --arg label "$idea_label" \
        --arg state "$triage_state_arg" \
        --argjson output "$output_contract" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh list-issues" +
                      " --project " + ($project | @sh) +
                      " --team " + ($team | @sh) +
                      " --label " + ($label | @sh) +
                      " --state " + ($state | @sh) +
                      " --limit 250"),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output }
        }'
      ;;
    idea.sync)
      # Sync is orchestration (drain the pending log, retry via MCP per entry).
      # Resolve to the local adapter even when Linear is configured — the local
      # command (`docs-check.sh idea-sync`) is responsible for the replay loop.
      local_adapter "$op"
      ;;
    # --- triage-outcome mutations ---
    # Each verb emits save_issue with a target state (+ duplicateOf for
    # merge). The skill fills in `id` (the source item being transitioned)
    # and priority (promote only) at dispatch time.
    # Each mutation resolver emits params.state only when state_ids is
    # configured; omitting it falls through to the skill's name-based
    # fallback (or surfaces the config gap as a visible error at dispatch).
    # Passing `state: ""` to Linear is silently no-op / API error — always
    # gate with the conditional merge pattern.
    # BTS-183: idea.{promote,defer,dismiss,merge} removed — dead-code MCP
    # branches. Idea state mutations on Linear-routed nodes route through
    # `ticket.transition <id> <role>` (http) per the /idea triage skill.
    idea.review-icebox)
      # BTS-166: state-id when configured, else literal "icebox" filter.
      output_contract='["id","title","status","createdAt"]'
      local icebox_state_id icebox_state_arg
      icebox_state_id=$(linear_state_id "$provider_config" "icebox")
      if [[ -n "$icebox_state_id" ]]; then
        icebox_state_arg="$icebox_state_id"
      else
        icebox_state_arg="icebox"
      fi
      jq -n --arg project "$project" --arg team "$team" --arg label "$idea_label" \
        --arg state "$icebox_state_arg" \
        --argjson output "$output_contract" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh list-issues" +
                      " --project " + ($project | @sh) +
                      " --team " + ($team | @sh) +
                      " --label " + ($label | @sh) +
                      " --state " + ($state | @sh) +
                      " --limit 250"),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output }
        }'
      ;;
    ticket.transition)
      # Provider-neutral ticket state transition. OP_ARGS = ticket id,
      # OP_ARG2 = role (triage|backlog|icebox|canceled|duplicate|done).
      # BTS-164: emits mechanism=http with a complete linear-query.sh
      # save-issue invocation. Caller eval's the command; no manual MCP
      # dispatch needed. For triage outcomes that need extra args
      # (--priority, --duplicate-of), the caller appends to the command
      # before eval.
      output_contract='["id","status"]'
      # Distinct error messages for missing id vs missing role so the
      # user knows which argument to supply. Id check first (positionally).
      if [[ -z "$op_args" ]]; then
        echo "ERROR: ticket.transition requires a ticket id as the first argument (e.g. ticket.transition BTS-128 done)" >&2
        exit 1
      fi
      if [[ -z "$OP_ARG2" ]]; then
        echo "ERROR: ticket.transition requires a role as the second argument. Valid roles: triage, backlog, icebox, canceled, duplicate, done, todo, in_progress" >&2
        exit 1
      fi
      # Validate role against the fixed vocabulary BEFORE config lookup —
      # fail loud here so an unknown role never silently degrades to an
      # empty state that the API would reject with an opaque 400.
      case "$OP_ARG2" in
        triage|backlog|icebox|canceled|duplicate|done|todo|in_progress) ;;
        *)
          echo "ERROR: unknown role '$OP_ARG2' for ticket.transition. Valid roles: triage, backlog, icebox, canceled, duplicate, done, todo, in_progress" >&2
          exit 1
          ;;
      esac
      local t_state_id
      t_state_id=$(linear_state_id "$provider_config" "$OP_ARG2")
      if [[ -z "$t_state_id" ]]; then
        echo "ERROR: role '$OP_ARG2' is not configured in integrations.providers.linear.state_ids — add it to .claude/ccanvil.json or .claude/ccanvil.local.json" >&2
        exit 1
      fi
      jq -n --arg id "$op_args" --arg state_id "$t_state_id" \
        --argjson output "$output_contract" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh save-issue --id " + ($id | @sh) + " --state " + ($state_id | @sh)),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output }
        }'
      ;;
    ticket.get)
      # BTS-164: fetch a single Linear issue by identifier. Used by future
      # consumers that need full issue context (status, description, labels)
      # without going through MCP. No current consumer; lands as a
      # building block.
      output_contract='["id","title","status","priority","description"]'
      if [[ -z "$op_args" ]]; then
        echo "ERROR: ticket.get requires a ticket id as the first argument (e.g. ticket.get BTS-128)" >&2
        exit 1
      fi
      jq -n --arg id "$op_args" --argjson output "$output_contract" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh get-issue " + ($id | @sh)),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output }
        }'
      ;;
    # BTS-183: ticket.find-by-title removed — dead-code MCP branch. Title
    # lookups belong in interactive operator queries via claude.ai connectors,
    # not the substrate path.
    # ---------------------------------------------------------------------
    # SSOT-Linear: route spec/plan/stasis lifecycle artifacts to Linear
    # Documents (BTS-204). Each verb resolves to a linear-query.sh
    # get-document or save-document invocation. Doc IDs are deterministic
    # uuid5-style derivations from {namespace, kind, ticket}.
    # ---------------------------------------------------------------------
    spec.read|plan.read)
      local kind="${op%%.*}"
      if [[ -z "$op_args" ]]; then
        echo "ERROR: $op (linear-routed) requires a ticket id argument (e.g. operations.sh resolve $op BTS-204)" >&2
        exit 1
      fi
      local doc_id
      doc_id=$(bash "$(dirname "${BASH_SOURCE[0]}")/linear-query.sh" resolve-document-id --kind "$kind" --ticket "$op_args")
      output_contract='["id","title","content","updatedAt"]'
      jq -n --arg cmd_id "$doc_id" --argjson output "$output_contract" \
        --arg kind "$kind" --arg ticket "$op_args" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: ("bash .ccanvil/scripts/linear-query.sh get-document " + ($cmd_id | @sh)),
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output, kind: $kind, ticket: $ticket, doc_id: $cmd_id, parent_kind: "issue" }
        }'
      ;;
    spec.write|plan.write)
      local kind="${op%%.*}"
      if [[ -z "$op_args" ]]; then
        echo "ERROR: $op (linear-routed) requires a ticket id argument (e.g. operations.sh resolve $op BTS-204)" >&2
        exit 1
      fi
      local doc_id
      doc_id=$(bash "$(dirname "${BASH_SOURCE[0]}")/linear-query.sh" resolve-document-id --kind "$kind" --ticket "$op_args")
      output_contract='["id","title","content","updatedAt"]'
      # The resolved command takes its full payload via --input-json - on stdin.
      # Caller pipes {title, content, issueId} (or includes id for update mode).
      jq -n --arg cmd_id "$doc_id" --argjson output "$output_contract" \
        --arg kind "$kind" --arg ticket "$op_args" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: "bash .ccanvil/scripts/linear-query.sh save-document --input-json -",
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output, kind: $kind, ticket: $ticket, doc_id: $cmd_id, parent_kind: "issue" }
        }'
      ;;
    stasis.read|stasis.write)
      # stasis takes a kind discriminator: "feature" or "session".
      # OP_ARGS = kind, OP_ARG2 = BTS-N (required for feature, omitted for session).
      local stasis_kind="${op_args:-feature}"
      case "$stasis_kind" in
        feature|session) ;;
        *)
          echo "ERROR: $op kind '$stasis_kind' is invalid. Pass 'feature' or 'session' as the first arg." >&2
          exit 1
          ;;
      esac
      local resolve_kind ticket parent_kind project_id
      project_id=$(echo "$provider_config" | jq -r '.project_id // ""')
      if [[ "$stasis_kind" == "feature" ]]; then
        if [[ -z "$OP_ARG2" ]]; then
          echo "ERROR: $op feature kind requires a ticket id (e.g. operations.sh resolve $op feature BTS-204)" >&2
          exit 1
        fi
        resolve_kind="feature-stasis"
        ticket="$OP_ARG2"
        parent_kind="issue"
      else
        if [[ -z "$project_id" ]]; then
          echo "ERROR: $op session kind requires integrations.providers.linear.project_id to be configured" >&2
          exit 1
        fi
        resolve_kind="session-stasis"
        ticket="$project_id"
        parent_kind="project"
      fi
      local doc_id
      doc_id=$(bash "$(dirname "${BASH_SOURCE[0]}")/linear-query.sh" resolve-document-id --kind "$resolve_kind" --ticket "$ticket")
      output_contract='["id","title","content","updatedAt"]'
      local cmd_str
      if [[ "${op##*.}" == "read" ]]; then
        cmd_str="bash .ccanvil/scripts/linear-query.sh get-document $(printf '%s' "$doc_id" | jq -Rr @sh)"
      else
        cmd_str="bash .ccanvil/scripts/linear-query.sh save-document --input-json -"
      fi
      jq -n --arg cmd "$cmd_str" --argjson output "$output_contract" \
        --arg kind "$stasis_kind" --arg ticket "$ticket" \
        --arg doc_id "$doc_id" --arg parent_kind "$parent_kind" \
        '{
          provider: "linear",
          mechanism: "http",
          invocation: {
            command: $cmd,
            endpoint: "https://api.linear.app/graphql",
            auth_env: "LINEAR_API_KEY"
          },
          contract: { output: $output, kind: $kind, ticket: $ticket, doc_id: $doc_id, parent_kind: $parent_kind }
        }'
      ;;
    *)
      # Unsupported operation for this provider — fall back to local
      local_adapter "$op"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# External provider adapter dispatch
# ---------------------------------------------------------------------------

external_adapter() {
  local op="$1" provider_name="$2" mechanism="$3" provider_config="$4" op_args="$5"

  case "$provider_name" in
    linear)
      linear_mcp_adapter "$op" "$provider_config" "$op_args"
      ;;
    *)
      # Generic passthrough for unknown providers
      jq -n --arg provider "$provider_name" --arg mechanism "$mechanism" \
        --argjson config "$provider_config" \
        '{"provider":$provider,"mechanism":$mechanism,"invocation":{"config":$config},"contract":{"output":[]}}'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

# @manifest
# purpose: Resolve a logical operation name (idea.add, ticket.transition, work.resolve, etc.) to a provider-specific invocation envelope by reading routing config — branches on local-vs-external provider, dispatches to local_adapter or external_adapter, and emits the {provider, mechanism, invocation} JSON callers eval to actually run the operation
# input: positional <op>
# input: env OP_ARGS
# output: stdout JSON envelope {provider, mechanism, invocation, contract}
# output: exit-codes 0 ok, 1 unknown-operation-or-missing-provider-config
# caller: skill:/idea
# caller: skill:/spec
# caller: skill:/recall
# caller: skill:/stasis
# caller: skill:/activate
# caller: skill:/land
# depends-on: jq
# depends-on: is_valid_operation
# depends-on: read_config
# depends-on: operation_group
# depends-on: local_adapter
# depends-on: external_adapter
# side-effect: reads-config-files
# failure-mode: unknown-operation | exit=1 | visible=stderr-ERROR-unknown-operation | mitigation=use-documented-op-name
# failure-mode: missing-provider-config | exit=1 | visible=stderr-ERROR-no-entry-in-integrations-providers | mitigation=add-provider-config
# contract: explicit-prefix-overrides-routing
# contract: work-ticket-backlog-groups-inherit-idea-routing
# anchor: BTS-246 (manifest seed)
cmd_resolve() {
  # @side-effect: reads-config-files
  local op="$1"

  # Validate operation name
  if ! is_valid_operation "$op"; then
    # @failure-mode: unknown-operation
    echo "ERROR: unknown operation \"$op\"" >&2
    exit 1
  fi

  # work.resolve: explicit <provider>:<id> prefix overrides routing config.
  # Recognized providers: linear, local. Unknown prefixes fall through to
  # normal routing (the id is treated as opaque by the provider adapter).
  local work_override=""
  if [[ "$op" == "work.resolve" && "$OP_ARGS" == *:* ]]; then
    local prefix="${OP_ARGS%%:*}"
    case "$prefix" in
      linear|local) work_override="$prefix" ;;
    esac
  fi

  # Read config (sets CONFIG_FILE or leaves empty)
  read_config

  # Determine routing: explicit prefix > routing.<group> > routing.idea (for
  # work group, since work operations share the idea provider) > local.
  local routed_provider=""
  if [[ -n "$work_override" ]]; then
    routed_provider="$work_override"
  elif [[ -z "$CONFIG_FILE" ]]; then
    routed_provider="local"
  else
    local group
    group=$(operation_group "$op")
    routed_provider=$(jq -r --arg g "$group" '.integrations.routing[$g] // ""' "$CONFIG_FILE")
    if [[ -z "$routed_provider" && ("$group" == "work" || "$group" == "ticket" || "$group" == "backlog") ]]; then
      # work, ticket, and backlog groups share the idea provider's routing —
      # on a Linear-configured node, `routing.idea=linear` alone is enough to
      # route work.resolve, ticket.transition, AND backlog.list through the
      # Linear adapter (BTS-175). The Linear backlog.list resolver still
      # validates state_ids.backlog presence and errors loudly if absent.
      #
      # Intentional only for read-side backlog ops (backlog.list).
      # backlog.create / backlog.prioritize fall through to the linear adapter's
      # *) branch and bounce to local_adapter — correct today, but a future
      # Linear case for those verbs would activate via the inheritance without
      # an explicit `routing.backlog = linear` opt-in. Re-evaluate if added.
      routed_provider=$(jq -r '.integrations.routing.idea // ""' "$CONFIG_FILE")
    fi
    [[ -z "$routed_provider" ]] && routed_provider="local"
  fi

  if [[ "$routed_provider" == "local" ]]; then
    local_adapter "$op"
    return 0
  fi

  # Non-local provider. Look up provider config (may be absent when the
  # explicit prefix override is used without a config file — adapters handle
  # that by emitting empty-url results for work.resolve).
  local provider_config="{}"
  if [[ -n "$CONFIG_FILE" ]]; then
    provider_config=$(jq -c --arg p "$routed_provider" '.integrations.providers[$p] // {}' "$CONFIG_FILE")
  fi

  # For standard (non-work.resolve) ops, provider MUST be configured.
  if [[ "$op" != "work.resolve" && "$provider_config" == "{}" ]]; then
    local group
    group=$(operation_group "$op")
    # @failure-mode: missing-provider-config
    echo "ERROR: provider \"$routed_provider\" is configured for $group but has no entry in integrations.providers" >&2
    exit 1
  fi

  local mechanism
  mechanism=$(echo "$provider_config" | jq -r '.mechanism // "mcp"')

  external_adapter "$op" "$routed_provider" "$mechanism" "$provider_config" "$OP_ARGS"
}

# @manifest
# purpose: Resolve an operation via cmd_resolve and execute it directly when the mechanism is bash or http (eval the .invocation.command) — for mcp-mechanism resolutions, emit the envelope verbatim so the caller dispatches externally. Provides a one-shot "do the thing" verb when the caller doesn't need the resolution envelope back
# input: positional <op>
# input: env OP_ARGS (forwarded to cmd_resolve)
# output: stdout output of the resolved command (for bash/http) or the resolution envelope (for mcp)
# output: exit-codes inherits from resolved command (0 ok, non-zero on dispatch failure), 1 unknown-operation
# depends-on: jq
# depends-on: cmd_resolve
# side-effect: dispatches-resolved-command
# failure-mode: unknown-operation-from-resolve | exit=1 | visible=stderr-from-cmd_resolve | mitigation=use-documented-op-name
# contract: bash-and-http-both-eval-via-invocation-command
# contract: mcp-mechanism-emits-envelope-for-external-dispatch
# anchor: BTS-246 (manifest seed)
cmd_exec() {
  local op="$1"

  # Resolve the operation to get routing info
  local resolution
  # @failure-mode: unknown-operation-from-resolve
  # @side-effect: dispatches-resolved-command
  resolution=$(cmd_resolve "$op")

  local mechanism
  mechanism=$(echo "$resolution" | jq -r '.mechanism')

  # BTS-211: bash AND http both carry .invocation.command (a shell command)
  # and should be eval'd. mcp resolutions carry .invocation.tool +
  # .invocation.params instead — caller must dispatch externally, so the
  # envelope is emitted verbatim. Pre-fix, only bash was eval'd, silently
  # breaking every caller of `operations.sh exec` for verbs migrated to
  # http (BTS-175 backlog.list, idea.count, etc.).
  case "$mechanism" in
    bash|http)
      local cmd
      cmd=$(echo "$resolution" | jq -r '.invocation.command')
      eval "$cmd"
      ;;
    *)
      # mcp or any unknown mechanism: caller dispatches externally.
      echo "$resolution"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$CMD" in
  resolve) cmd_resolve "$OPERATION" ;;
  exec) cmd_exec "$OPERATION" ;;
  merge-config) merge_config "$PROJECT_DIR" ;;
  *) usage ;;
esac
