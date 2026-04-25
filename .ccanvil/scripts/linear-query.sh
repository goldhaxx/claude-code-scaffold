#!/usr/bin/env bash
# linear-query.sh — Linear GraphQL client wrapper for bash scripts.
#
# BTS-164: provides curl + jq + LINEAR_API_KEY env-var auth so docs-check.sh,
# radar-gather, operations.sh resolvers, etc. can read+write Linear without
# routing through MCP. Uniform path for scripts and skills; closes the
# read-path provider asymmetry (cmd_idea_count was opening the local JSONL
# log directly even on Linear-routed projects).
#
# Subcommands ship in phases:
#   v1 — viewer, list-issues, get-issue, list-states, list-labels, save-issue
#
# Auth: requires LINEAR_API_KEY in the environment for every subcommand
# except --help. Endpoint defaults to https://api.linear.app/graphql; tests
# override via LINEAR_QUERY_ENDPOINT.
#
# Exit codes:
#   0 — success
#   2 — usage / configuration error (missing env var, unknown subcommand)
#   3 — runtime error (network, API error response, malformed JSON)

set -euo pipefail

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: linear-query.sh <subcommand> [args...]

Subcommands:
  viewer                              Auth smoke test — returns {id, name} for the authenticated user.
  list-issues  [flags]                List issues. Flags: --project, --team, --state, --label, --limit.
  get-issue    <id>                   Fetch one issue by identifier (e.g., BTS-164).
  list-states  [flags]                List workflow states. Flags: --team.
  list-labels  [flags]                List labels. Flags: --team.
  save-issue   [flags]                Create or update an issue. Flags: --id, --title, --description,
                                      --state, --priority, --labels, --project, --team, --parent-id,
                                      --duplicate-of.

Environment:
  LINEAR_API_KEY        Required for every subcommand except --help.
                        Generate one at https://linear.app/settings/api.
  LINEAR_QUERY_ENDPOINT Optional override (default: https://api.linear.app/graphql).
                        Tests use this to point at a stub endpoint.

Exit codes:
  0  ok
  2  usage / configuration error (missing env var, unknown subcommand, bad flags)
  3  runtime error (network, API error, malformed response)
EOF
}

# Print to stderr and exit. First arg = exit code, rest = message.
_die() {
  local code="$1"; shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

# Every subcommand calls this before doing any work. Exits 2 with a clear
# remediation hint when the env var is missing.
_require_api_key() {
  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    _die 2 "LINEAR_API_KEY not set. Generate a key at https://linear.app/settings/api and export it: export LINEAR_API_KEY=<key>"
  fi
}

# POST a GraphQL query to Linear. Args:
#   $1 — the GraphQL query string
#   $2 — variables JSON (object), defaults to {}
# Emits the parsed response payload (the .data field) on stdout.
# Exits 3 with the GraphQL error message on stderr if the response carries
# an "errors" array.
_post_graphql() {
  local query="$1"
  # NOTE: do NOT use ${2:-{}} — bash parameter expansion reads only to the
  # first '}', making the default '{' and leaving a stray '}' as literal.
  local variables="${2:-}"
  [[ -z "$variables" ]] && variables='{}'
  local endpoint="${LINEAR_QUERY_ENDPOINT:-https://api.linear.app/graphql}"

  local body
  body=$(jq -nc --arg q "$query" --argjson v "$variables" '{query:$q,variables:$v}')

  local response rc
  response=$(
    curl -sS -X POST "$endpoint" \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body"
  )
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _die 3 "linear-query: HTTP request failed (curl exit $rc)"
  fi

  # GraphQL errors: surface the first one and exit 3. Linear's WAF and auth
  # layer both return 200 OK with an errors array, so HTTP status alone is
  # not a reliable signal.
  local err
  err=$(printf '%s' "$response" | jq -r '.errors[0].message // empty' 2>/dev/null || true)
  if [[ -n "$err" ]]; then
    _die 3 "linear-query: GraphQL error: $err"
  fi

  printf '%s' "$response" | jq '.data'
}

# -----------------------------------------------------------------------------
# Subcommand stubs (filled in by later steps in the BTS-164 plan)
# -----------------------------------------------------------------------------

cmd_viewer() {
  _require_api_key
  local query='query { viewer { id name } }'
  _post_graphql "$query" | jq '.viewer'
}

cmd_list_issues() {
  _require_api_key

  local project="" team="" state="" label="" limit="50"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --team)    team="$2";    shift 2 ;;
      --state)   state="$2";   shift 2 ;;
      --label)   label="$2";   shift 2 ;;
      --limit)   limit="$2";   shift 2 ;;
      *) _die 2 "list-issues: unknown flag: $1" ;;
    esac
  done

  # Compose the IssueFilter object incrementally so callers only pay for
  # the dimensions they constrain. Linear's filter shape is canonical:
  # field: { type/name/id: { eq: value } }, with labels using `some`.
  local filter='{}'
  if [[ -n "$project" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$project" '. + {project:{name:{eq:$v}}}')
  fi
  if [[ -n "$team" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team" '. + {team:{name:{eq:$v}}}')
  fi
  if [[ -n "$state" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$state" '. + {state:{type:{eq:$v}}}')
  fi
  if [[ -n "$label" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$label" '. + {labels:{some:{name:{eq:$v}}}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" --argjson n "$limit" '{filter:$f, first:$n}')

  local query='query ($filter: IssueFilter, $first: Int) {
    issues(filter: $filter, first: $first) {
      nodes {
        identifier title priority createdAt updatedAt
        state { name type id }
        labels { nodes { name } }
      }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.issues.nodes[] | {
    id: .identifier,
    title: .title,
    status: .state.name,
    statusType: .state.type,
    priority: (.priority // null),
    createdAt: .createdAt,
    updatedAt: .updatedAt,
    labels: [.labels.nodes[].name]
  }]'
}

cmd_get_issue() {
  _require_api_key
  if [[ $# -lt 1 ]]; then
    _die 2 "get-issue requires an issue identifier (e.g., BTS-164)"
  fi
  local id="$1"

  local variables
  variables=$(jq -nc --arg id "$id" '{id:$id}')

  local query='query ($id: String!) {
    issue(id: $id) {
      identifier title priority createdAt updatedAt description
      state { name type id }
      labels { nodes { name } }
    }
  }'

  _post_graphql "$query" "$variables" | jq '.issue | {
    id: .identifier,
    title: .title,
    status: .state.name,
    statusType: .state.type,
    priority: (.priority // null),
    createdAt: .createdAt,
    updatedAt: .updatedAt,
    description: .description,
    labels: [.labels.nodes[].name]
  }'
}

cmd_list_states() {
  _require_api_key
  local team=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team) team="$2"; shift 2 ;;
      *) _die 2 "list-states: unknown flag: $1" ;;
    esac
  done

  local filter='{}'
  if [[ -n "$team" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team" '. + {team:{name:{eq:$v}}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: WorkflowStateFilter) {
    workflowStates(filter: $filter) {
      nodes { id name type }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.workflowStates.nodes[] | {id, name, type}]'
}

cmd_list_labels() {
  _require_api_key
  local team=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team) team="$2"; shift 2 ;;
      *) _die 2 "list-labels: unknown flag: $1" ;;
    esac
  done

  local filter='{}'
  if [[ -n "$team" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team" '. + {team:{name:{eq:$v}}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: IssueLabelFilter) {
    issueLabels(filter: $filter) {
      nodes { id name }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.issueLabels.nodes[] | {id, name}]'
}

cmd_save_issue() {
  _require_api_key

  # Mode selector: presence of --id triggers update; absence triggers create.
  # Caller-provided IDs only — name resolution (team/project/label NAMES → IDs)
  # is the resolver's job in Step 7. The wrapper stays focused on transport.
  local id="" title="" description="" state=""
  local team_id="" project_id="" parent_id="" duplicate_of=""
  local priority="" label_ids=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)            id="$2";           shift 2 ;;
      --title)         title="$2";        shift 2 ;;
      --description)   description="$2";  shift 2 ;;
      --state)         state="$2";        shift 2 ;;
      --team-id)       team_id="$2";      shift 2 ;;
      --project-id)    project_id="$2";   shift 2 ;;
      --parent-id)     parent_id="$2";    shift 2 ;;
      --duplicate-of)  duplicate_of="$2"; shift 2 ;;
      --priority)      priority="$2";     shift 2 ;;
      --label-ids)     label_ids="$2";    shift 2 ;;
      *) _die 2 "save-issue: unknown flag: $1" ;;
    esac
  done

  # Build the input object incrementally — Linear's IssueCreateInput and
  # IssueUpdateInput share the same field names for everything we set.
  local input='{}'
  if [[ -n "$title" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$title" '. + {title:$v}')
  fi
  if [[ -n "$description" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$description" '. + {description:$v}')
  fi
  if [[ -n "$state" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$state" '. + {stateId:$v}')
  fi
  if [[ -n "$team_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$team_id" '. + {teamId:$v}')
  fi
  if [[ -n "$project_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$project_id" '. + {projectId:$v}')
  fi
  if [[ -n "$parent_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$parent_id" '. + {parentId:$v}')
  fi
  if [[ -n "$duplicate_of" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$duplicate_of" '. + {duplicateOf:$v}')
  fi
  if [[ -n "$priority" ]]; then
    input=$(printf '%s' "$input" | jq --argjson v "$priority" '. + {priority:$v}')
  fi
  if [[ -n "$label_ids" ]]; then
    # CSV → JSON array of strings.
    local arr
    arr=$(printf '%s' "$label_ids" | jq -R 'split(",")')
    input=$(printf '%s' "$input" | jq --argjson v "$arr" '. + {labelIds:$v}')
  fi

  if [[ -z "$id" ]]; then
    # Create mode. Required: title. team_id is required by Linear's schema
    # but emitting a clear error here surfaces the gap before the API call.
    if [[ -z "$title" ]]; then
      _die 2 "save-issue create requires --title"
    fi
    if [[ -z "$team_id" ]]; then
      _die 2 "save-issue create requires --team-id (use list-teams to discover)"
    fi

    local query='mutation IssueCreate($input: IssueCreateInput!) {
      issueCreate(input: $input) { success issue { identifier title } }
    }'
    local variables
    variables=$(jq -n --argjson i "$input" '{input:$i}')
    _post_graphql "$query" "$variables" | jq '.issueCreate.issue | {
      id: .identifier,
      title: .title
    }'
  else
    # Update mode. Linear's issueUpdate accepts the same input shape minus
    # creation-only fields (teamId is rejected for update, but we already
    # don't add it for the update path's expected callers).
    local query='mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) { success issue { identifier title } }
    }'
    local variables
    variables=$(jq -n --arg id "$id" --argjson i "$input" '{id:$id, input:$i}')
    _post_graphql "$query" "$variables" | jq '.issueUpdate.issue | {
      id: .identifier,
      title: .title
    }'
  fi
}

# -----------------------------------------------------------------------------
# Dispatcher
# -----------------------------------------------------------------------------

main() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi

  local subcommand="$1"; shift

  case "$subcommand" in
    -h|--help|help)
      usage
      exit 0
      ;;
    viewer)       cmd_viewer       "$@" ;;
    list-issues)  cmd_list_issues  "$@" ;;
    get-issue)    cmd_get_issue    "$@" ;;
    list-states)  cmd_list_states  "$@" ;;
    list-labels)  cmd_list_labels  "$@" ;;
    save-issue)   cmd_save_issue   "$@" ;;
    *)
      _die 2 "Unknown subcommand: $subcommand. Run 'linear-query.sh --help' for usage."
      ;;
  esac
}

main "$@"
