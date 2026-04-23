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
    idea.add|idea.list|idea.triage|idea.sync) return 0 ;;
    idea.promote|idea.defer|idea.dismiss|idea.merge) return 0 ;;
    idea.review-icebox) return 0 ;;
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
EOF
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

CMD=""
OPERATION=""
OP_ARGS=""

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

linear_mcp_adapter() {
  local op="$1" provider_config="$2" op_args="$3"
  local tool="" output_contract="" field_map=""
  local project team idea_label idea_status icebox_status
  project=$(echo "$provider_config" | jq -r '.project // ""')
  team=$(echo "$provider_config" | jq -r '.team // ""')
  idea_label=$(echo "$provider_config" | jq -r '.idea_label // "idea"')
  idea_status=$(echo "$provider_config" | jq -r '.idea_status // "Idea"')
  icebox_status=$(echo "$provider_config" | jq -r '.icebox_status // "Icebox"')

  case "$op" in
    backlog.list)
      tool="mcp__claude_ai_Linear__list_issues"
      output_contract='["id","title","status","priority"]'
      field_map='{"identifier":"id","title":"title","state.name":"status","priority":"priority"}'
      jq -n --arg tool "$tool" --arg project "$project" --arg team "$team" \
        --argjson output "$output_contract" --argjson fmap "$field_map" \
        '{"provider":"linear","mechanism":"mcp","invocation":{"tool":$tool,"params":{"project":$project,"team":$team}},"contract":{"output":$output,"field_map":$fmap}}'
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
    # The skill passes title + description out-of-band; this resolve only
    # communicates the tool + the invariant params (team, project, state,
    # label) that the skill stitches into a final MCP call.
    idea.add)
      tool="mcp__claude_ai_Linear__save_issue"
      output_contract='["id","title","status"]'
      # No `state` param: Linear routes API-created issues to the team's
      # native Triage intake surface automatically when Triage is enabled.
      # Specifying a state here would bypass Triage and drop the item
      # straight into the target state.
      jq -n --arg tool "$tool" --arg project "$project" --arg team "$team" \
        --arg label "$idea_label" \
        --argjson output "$output_contract" \
        '{"provider":"linear","mechanism":"mcp","invocation":{"tool":$tool,"params":{"project":$project,"team":$team,"labels":[$label]}},"contract":{"output":$output}}'
      ;;
    idea.list)
      tool="mcp__claude_ai_Linear__list_issues"
      output_contract='["id","title","status","createdAt"]'
      jq -n --arg tool "$tool" --arg project "$project" --arg team "$team" \
        --arg label "$idea_label" \
        --argjson output "$output_contract" \
        '{"provider":"linear","mechanism":"mcp","invocation":{"tool":$tool,"params":{"project":$project,"team":$team,"label":$label}},"contract":{"output":$output}}'
      ;;
    idea.triage)
      # stateId takes precedence over name-based state dispatch — when
      # configured, omit `state` to avoid the name/type collision trap
      # documented in the /idea skill's Rules section.
      tool="mcp__claude_ai_Linear__list_issues"
      output_contract='["id","title","status","createdAt"]'
      local triage_state_id
      triage_state_id=$(linear_state_id "$provider_config" "triage")
      jq -n --arg tool "$tool" --arg project "$project" --arg team "$team" \
        --arg label "$idea_label" --arg state "$idea_status" \
        --arg state_id "$triage_state_id" \
        --argjson output "$output_contract" \
        '{
          "provider":"linear",
          "mechanism":"mcp",
          "invocation":{
            "tool":$tool,
            "params":(
              {"project":$project,"team":$team,"label":$label}
              + (if $state_id != ""
                  then {"stateId":$state_id}
                  else {"state":$state}
                 end)
            )
          },
          "contract":{"output":$output}
        }'
      ;;
    idea.sync)
      # Sync is orchestration (drain the pending log, retry via MCP per entry).
      # Resolve to the local adapter even when Linear is configured — the local
      # command (`docs-check.sh idea-sync`) is responsible for the replay loop.
      local_adapter "$op"
      ;;
    # --- triage-outcome mutations ---
    # Each verb emits save_issue with a target stateId (+ duplicateOf for
    # merge). The skill fills in `id` (the source item being transitioned)
    # and priority (promote only) at dispatch time.
    # Each mutation resolver emits params.stateId only when state_ids is
    # configured; omitting it falls through to the skill's name-based
    # fallback (or surfaces the config gap as a visible error at dispatch).
    # Passing `stateId: ""` to Linear is silently no-op / API error — always
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
            "params":(if $state_id != "" then {"stateId":$state_id} else {} end)
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
            "params":(if $state_id != "" then {"stateId":$state_id} else {} end)
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
            "params":(if $state_id != "" then {"stateId":$state_id} else {} end)
          },
          "contract":{"output":$output}
        }'
      ;;
    idea.merge)
      # OP_ARGS is the source item uid (uniform with promote/defer/dismiss).
      # The merge target (duplicateOf) is NOT resolver-known — the skill
      # pairs it in at dispatch time from user input. The resolver only
      # tells the skill which tool + stateId to use.
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
            "params":(if $state_id != "" then {"stateId":$state_id} else {} end)
          },
          "contract":{"output":$output}
        }'
      ;;
    idea.review-icebox)
      tool="mcp__claude_ai_Linear__list_issues"
      output_contract='["id","title","status","createdAt"]'
      local icebox_state_id
      icebox_state_id=$(linear_state_id "$provider_config" "icebox")
      jq -n --arg tool "$tool" --arg project "$project" --arg team "$team" \
        --arg state_id "$icebox_state_id" --arg label "$idea_label" \
        --argjson output "$output_contract" \
        '{
          "provider":"linear","mechanism":"mcp",
          "invocation":{
            "tool":$tool,
            "params":(
              {"project":$project,"team":$team,"label":$label}
              + (if $state_id != "" then {"stateId":$state_id} else {} end)
            )
          },
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

  # Read config (sets CONFIG_FILE or leaves empty)
  read_config

  # No config or no integrations key → local adapter
  if [[ -z "$CONFIG_FILE" ]]; then
    local_adapter "$op"
    return 0
  fi

  # Check for integrations.routing.<group>
  local group
  group=$(operation_group "$op")
  local routed_provider
  routed_provider=$(jq -r --arg g "$group" '.integrations.routing[$g] // "local"' "$CONFIG_FILE")

  if [[ "$routed_provider" == "local" ]]; then
    local_adapter "$op"
    return 0
  fi

  # Look up the provider config
  local provider_config
  provider_config=$(jq -c --arg p "$routed_provider" '.integrations.providers[$p] // null' "$CONFIG_FILE")

  if [[ "$provider_config" == "null" ]]; then
    echo "ERROR: provider \"$routed_provider\" is configured for $group but has no entry in integrations.providers" >&2
    exit 1
  fi

  local mechanism
  mechanism=$(echo "$provider_config" | jq -r '.mechanism // "bash"')

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
