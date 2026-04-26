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

is_valid_operation() {
  case "$1" in
    backlog.list|backlog.create|backlog.prioritize|backlog.get) return 0 ;;
    spec.read|spec.write|spec.list|spec.activate|spec.complete) return 0 ;;
    plan.read|plan.write) return 0 ;;
    stasis.read|stasis.write) return 0 ;;
    status.get|status.update) return 0 ;;
    pr.create|pr.list) return 0 ;;
    review.run) return 0 ;;
    idea.add|idea.list|idea.count|idea.triage|idea.sync) return 0 ;;
    idea.promote|idea.defer|idea.dismiss|idea.merge) return 0 ;;
    idea.review-icebox) return 0 ;;
    work.resolve) return 0 ;;
    ticket.transition|ticket.get) return 0 ;;
    ticket.find-by-title) return 0 ;;
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
# EXACT is only consumed by ticket.find-by-title. Other operations ignore it
# harmlessly. Do not add new operations that read $EXACT without also
# renaming/scoping this variable.
EXACT=0

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
    --exact)
      EXACT=1; shift ;;
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

# merge_config — Merge ccanvil.json (hub) with ccanvil.local.json (node).
#
# Outputs the effective config JSON to stdout. Uses RFC 7396 deep merge
# via jq's * operator — node wins on conflict (permissive, Option A).
#
# Exit 0: success (even if both files are missing — outputs {}).
# Exit 1: a file exists but contains invalid JSON.
merge_config() {
  local dir="$1"
  local hub_file="$dir/.claude/ccanvil.json"
  local local_file="$dir/.claude/ccanvil.local.json"

  # Neither file exists → empty config
  if [[ ! -f "$hub_file" && ! -f "$local_file" ]]; then
    echo '{}'
    return 0
  fi

  # Validate hub file if it exists
  if [[ -f "$hub_file" ]]; then
    if ! jq empty "$hub_file" 2>/dev/null; then
      echo "ERROR: .claude/ccanvil.json is not valid JSON" >&2
      return 1
    fi
  fi

  # Validate local file if it exists
  if [[ -f "$local_file" ]]; then
    if ! jq empty "$local_file" 2>/dev/null; then
      echo "ERROR: .claude/ccanvil.local.json is not valid JSON" >&2
      return 1
    fi
  fi

  # Only hub file → return hub content
  if [[ -f "$hub_file" && ! -f "$local_file" ]]; then
    jq '.' "$hub_file"
    return 0
  fi

  # Only local file → return local content
  if [[ ! -f "$hub_file" && -f "$local_file" ]]; then
    jq '.' "$local_file"
    return 0
  fi

  # Both files exist → deep merge (node wins on conflict)
  jq -s '.[0] * .[1]' "$hub_file" "$local_file"
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
    backlog.get)
      cmd="cat docs/specs/${OP_ARGS}.md"
      output_contract='["feature_id","status","created","body"]'
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
      # Local sync is a no-op; the command exists for contract uniformity.
      cmd=".ccanvil/scripts/docs-check.sh idea-sync"
      output_contract='["synced","pending"]'
      ;;
    idea.review-icebox)
      cmd=".ccanvil/scripts/docs-check.sh idea-review-icebox"
      output_contract='["uid","created","title","status"]'
      ;;
    # --- triage-outcome mutations ---
    # Each verb maps to idea-update <uid> <target-status>. OP_ARGS is the
    # source idea uid; the skill substitutes it at dispatch time.
    idea.promote)
      cmd=".ccanvil/scripts/docs-check.sh idea-update ${OP_ARGS} backlog"
      output_contract='["uid","status"]'
      ;;
    idea.defer)
      cmd=".ccanvil/scripts/docs-check.sh idea-update ${OP_ARGS} icebox"
      output_contract='["uid","status"]'
      ;;
    idea.dismiss)
      cmd=".ccanvil/scripts/docs-check.sh idea-update ${OP_ARGS} canceled"
      output_contract='["uid","status"]'
      ;;
    idea.merge)
      # OP_ARGS is the SOURCE item uid being marked duplicate (uniform with
      # promote/defer/dismiss). Merge target (duplicateOf) is only
      # meaningful for Linear; the local log has no cross-entry link.
      cmd=".ccanvil/scripts/docs-check.sh idea-update ${OP_ARGS} duplicate"
      output_contract='["uid","status"]'
      ;;
    ticket.transition)
      # ticket.transition is a Linear-specific primitive (state-ID based).
      # On local-provider nodes there is no equivalent surface — fail loud
      # rather than silently succeeding with an empty command.
      echo "ERROR: provider 'local' does not support ticket.transition — configure a Linear provider in .claude/ccanvil.json to enable" >&2
      exit 1
      ;;
    ticket.find-by-title)
      # Local-provider fast path — no Linear backend means no tickets to
      # find. Emit a bash command that prints an empty array so callers get
      # a deterministic `[]` and can proceed with the capture (e.g. /idea
      # sync treating "no duplicates found" as green light).
      cmd="echo '[]'"
      output_contract='[]'
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
    backlog.get)
      tool="mcp__claude_ai_Linear__get_issue"
      output_contract='["id","title","status","priority","description"]'
      field_map='{"identifier":"id","title":"title","state.name":"status","priority":"priority"}'
      jq -n --arg tool "$tool" --arg id "$op_args" \
        --argjson output "$output_contract" --argjson fmap "$field_map" \
        '{"provider":"linear","mechanism":"mcp","invocation":{"tool":$tool,"params":{"id":$id}},"contract":{"output":$output,"field_map":$fmap}}'
      ;;
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
    idea.promote)
      tool="mcp__claude_ai_Linear__save_issue"
      output_contract='["id","status","priority"]'
      local backlog_state_id
      backlog_state_id=$(linear_state_id "$provider_config" "backlog")
      jq -n --arg tool "$tool" --arg state_id "$backlog_state_id" \
        --argjson output "$output_contract" \
        '{
          "provider":"linear","mechanism":"mcp",
          "invocation":{
            "tool":$tool,
            "params":(if $state_id != "" then {"state":$state_id} else {} end)
          },
          "contract":{"output":$output}
        }'
      ;;
    idea.defer)
      tool="mcp__claude_ai_Linear__save_issue"
      output_contract='["id","status"]'
      local icebox_state_id
      icebox_state_id=$(linear_state_id "$provider_config" "icebox")
      jq -n --arg tool "$tool" --arg state_id "$icebox_state_id" \
        --argjson output "$output_contract" \
        '{
          "provider":"linear","mechanism":"mcp",
          "invocation":{
            "tool":$tool,
            "params":(if $state_id != "" then {"state":$state_id} else {} end)
          },
          "contract":{"output":$output}
        }'
      ;;
    idea.dismiss)
      tool="mcp__claude_ai_Linear__save_issue"
      output_contract='["id","status"]'
      local canceled_state_id
      canceled_state_id=$(linear_state_id "$provider_config" "canceled")
      jq -n --arg tool "$tool" --arg state_id "$canceled_state_id" \
        --argjson output "$output_contract" \
        '{
          "provider":"linear","mechanism":"mcp",
          "invocation":{
            "tool":$tool,
            "params":(if $state_id != "" then {"state":$state_id} else {} end)
          },
          "contract":{"output":$output}
        }'
      ;;
    idea.merge)
      # OP_ARGS is the source item uid (uniform with promote/defer/dismiss).
      # The merge target (duplicateOf) is NOT resolver-known — the skill
      # pairs it in at dispatch time from user input. The resolver only
      # tells the skill which tool + state to use.
      tool="mcp__claude_ai_Linear__save_issue"
      output_contract='["id","status","duplicateOf"]'
      local dup_state_id
      dup_state_id=$(linear_state_id "$provider_config" "duplicate")
      jq -n --arg tool "$tool" --arg state_id "$dup_state_id" \
        --argjson output "$output_contract" \
        '{
          "provider":"linear","mechanism":"mcp",
          "invocation":{
            "tool":$tool,
            "params":(if $state_id != "" then {"state":$state_id} else {} end)
          },
          "contract":{"output":$output}
        }'
      ;;
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
    ticket.find-by-title)
      # BTS-129 — resolve emits a list_issues invocation + a client-side jq
      # filter template. Callers dispatch the MCP tool, then apply the
      # template with `jq --arg title "<raw title>" -e "$template"` on the
      # result. Splitting invocation from filter keeps operations.sh pure
      # bash and the title-quoting safe (jq --arg, not string interpolation).
      if [[ -z "$op_args" ]]; then
        echo "ERROR: ticket.find-by-title requires a title as the first argument" >&2
        echo "" >&2
        echo "  Usage:" >&2
        echo "    operations.sh resolve ticket.find-by-title \"<title>\" [--exact]" >&2
        exit 1
      fi
      tool="mcp__claude_ai_Linear__list_issues"
      output_contract='["id","title","status","url"]'
      local filter_mode filter_template
      # The template accepts either the wrapped Linear MCP response
      # ({issues: [...], hasNextPage}) or a bare array — `(.issues? // .)`
      # unwraps the former, passes the latter through.
      # For status, use `.status // .state.name` so the template works
      # against both the MCP-level shape (top-level `.status` string) and
      # any internal GraphQL shape (`.state.name`) that older tooling emits.
      if (( EXACT )); then
        filter_mode="exact"
        filter_template='[ (.issues? // .) | .[] | select(.title == $title) | {id, title, status: (.status // .state.name), url} ]'
      else
        filter_mode="substring"
        filter_template='[ (.issues? // .) | .[] | select((.title | ascii_downcase) | contains($title | ascii_downcase)) | {id, title, status: (.status // .state.name), url} ]'
      fi
      jq -n --arg tool "$tool" --arg project "$project" --arg team "$team" \
        --arg query "$op_args" --arg mode "$filter_mode" \
        --arg template "$filter_template" --argjson output "$output_contract" \
        '{
          "provider":"linear","mechanism":"mcp",
          "invocation":{
            "tool":$tool,
            "params":{"project":$project,"team":$team,"query":$query}
          },
          "client_filter":{"mode":$mode,"jq_template":$template,"title_arg":$query},
          "contract":{"output":$output}
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

cmd_resolve() {
  local op="$1"

  # Validate operation name
  if ! is_valid_operation "$op"; then
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
      # Intentional only for read-side backlog ops (backlog.list, backlog.get).
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
    echo "ERROR: provider \"$routed_provider\" is configured for $group but has no entry in integrations.providers" >&2
    exit 1
  fi

  local mechanism
  mechanism=$(echo "$provider_config" | jq -r '.mechanism // "mcp"')

  external_adapter "$op" "$routed_provider" "$mechanism" "$provider_config" "$OP_ARGS"
}

cmd_exec() {
  local op="$1"

  # Resolve the operation to get routing info
  local resolution
  resolution=$(cmd_resolve "$op")

  local mechanism
  mechanism=$(echo "$resolution" | jq -r '.mechanism')

  if [[ "$mechanism" == "bash" ]]; then
    # Extract and execute the command directly
    local cmd
    cmd=$(echo "$resolution" | jq -r '.invocation.command')
    eval "$cmd"
  else
    # MCP or other mechanisms: output resolution JSON for Claude to dispatch
    echo "$resolution"
  fi
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
