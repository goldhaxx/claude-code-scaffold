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
  resolve-document-id [flags]         Derive a deterministic UUID for a ccanvil lifecycle Document.
                                      Flags: --kind {spec|plan|feature-stasis|session-stasis},
                                             --ticket <BTS-N>. Pure compute (no API call).
  get-document <id-or-slug>           Fetch one Document by UUID or slug. Returns
                                      {id, title, content, slugId, url, updatedAt, createdAt,
                                       updatedBy, creator, project, issue}.
  save-document [flags]               Create or update a Document. Flags: --id, --title, --content,
                                      --issue-id, --project-id, --initiative-id, --trashed,
                                      --input-json - (stdin JSON; CLI flags override on collision).
                                      Auto-detects mode by id presence (in flag or stdin).
  document-updated-at <id-or-slug>    Cheap projection: returns {id, updatedAt, updatedBy}.
                                      Used for concurrent-edit pre-checks (rate-limit hygiene).
  trash-document <id-or-slug>         Soft-delete via documentDelete. Returns {success}.
                                      Linear has no hard-delete in the public API.
  list-documents [flags]              List Documents. Flags: --project, --issue, --initiative,
                                      --limit. Returns array of {id, title, slugId, updatedAt,
                                      createdAt}.
  document-history <id-or-slug>       Returns content snapshot history as
                                      [{id, snapshotAt, actor}]. Used for concurrent-edit
                                      diff surfacing.

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

# Walk up from $PWD looking for .git; when found AND LINEAR_API_KEY is unset
# AND a sibling .env exists, source it. Eliminates the per-shell
# `set -a; source .env; set +a` ritual that has to run before every Bash
# tool invocation that touches Linear (BTS-167).
#
# Walks $PWD only — not the script's own dirname — so test isolation works
# (tests cd into a controlled tmpdir) and the user-intent "my project's
# .env, found from where I am" stays the contract. If the script is invoked
# while $PWD is outside any git tree, no auto-source fires.
#
# Already-exported LINEAR_API_KEY always wins; .env is only consulted when
# the env var is unset (no override of operator intent).
_load_env_if_needed() {
  if [[ -n "${LINEAR_API_KEY:-}" ]]; then
    return 0
  fi
  local dir
  dir="$(pwd -P 2>/dev/null)" || return 0
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -d "$dir/.git" ]]; then
      if [[ -f "$dir/.env" ]]; then
        # `set -a` exports every var assigned during the source step; the
        # script ships with `set -euo pipefail`, so a parse error in .env
        # surfaces as a non-zero exit rather than a silent skip (AC-6).
        # Note: `set +a` is unreachable when the source aborts under
        # `set -e` — that's harmless because the script exits entirely.
        # Don't refactor this into a sourced helper without revisiting
        # this scope leak.
        set -a
        # shellcheck disable=SC1091
        . "$dir/.env"
        set +a
      fi
      return 0
    fi
    dir="$(dirname "$dir")"
  done
}

# Every subcommand calls this before doing any work. Exits 2 with a clear
# remediation hint when the env var is missing.
_require_api_key() {
  _load_env_if_needed
  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    _die 2 "LINEAR_API_KEY not set. Export it (export LINEAR_API_KEY=<key>) or add LINEAR_API_KEY=<key> to .env at the project root. Generate a key at https://linear.app/settings/api."
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

# @manifest
# purpose: Wrap the Linear GraphQL `viewer` query — used by /drift-watchdog preflight and operator smoke tests to verify LINEAR_API_KEY auth without side effects
# input: env LINEAR_API_KEY
# output: stdout JSON {id, name}
# output: exit-codes 0 ok, 2 missing-api-key, 3 graphql-or-http-error
# caller: cmd_drift_watchdog_preflight
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY-or-add-to-env
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error-or-HTTP-request-failed | mitigation=verify-network-and-key-validity
# contract: read-only-no-mutations
# anchor: BTS-245 (manifest seed)
cmd_viewer() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  local query='query { viewer { id name } }'
  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" | jq '.viewer'
}

# @manifest
# purpose: Wrap the Linear GraphQL `issues` query with a composable IssueFilter (project/team/state/label/limit) — auto-detects UUID-shaped --state values and filters by state.id.eq vs state.type.eq so callers can use either form symmetrically
# input: --project <name>
# input: --team <name>
# input: --state <type-or-uuid>
# input: --label <name>
# input: --limit <int>
# input: env LINEAR_API_KEY
# output: stdout JSON array [{id, title, status, statusType, priority, createdAt, updatedAt, labels[]}]
# output: exit-codes 0 ok, 2 missing-api-key-or-unknown-flag, 3 graphql-or-http-error
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: unknown-flag | exit=2 | visible=stderr-list-issues-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error-or-HTTP-request-failed | mitigation=verify-filter-shape-and-key
# contract: emits-empty-array-when-no-matches
# contract: filter-uuid-state-by-id-eq-non-uuid-by-type-eq
# anchor: BTS-245 (manifest seed)
cmd_list_issues() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key

  local project="" team="" state="" label="" limit="50"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --team)    team="$2";    shift 2 ;;
      --state)   state="$2";   shift 2 ;;
      --label)   label="$2";   shift 2 ;;
      --limit)   limit="$2";   shift 2 ;;
      # @failure-mode: unknown-flag
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
    # BTS-175: auto-detect UUID-shaped values and filter by state.id.eq
    # rather than state.type.eq. Linear's IssueFilter accepts either form;
    # `save-issue --state` already treats the value as a stateId UUID, so
    # this aligns the list-issues semantics for symmetric state plumbing.
    if [[ "$state" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
      filter=$(printf '%s' "$filter" | jq --arg v "$state" '. + {state:{id:{eq:$v}}}')
    else
      filter=$(printf '%s' "$filter" | jq --arg v "$state" '. + {state:{type:{eq:$v}}}')
    fi
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

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
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

# @manifest
# purpose: Wrap the Linear GraphQL `issue` query — fetches a single issue by identifier (e.g. BTS-164) including the full description, status, labels, and timestamps so /spec, /idea triage, and operator queries get full context in one call
# input: positional <issue-identifier>
# input: env LINEAR_API_KEY
# output: stdout JSON {id, uuid, title, status, statusType, priority, createdAt, updatedAt, description, labels[]}
# output: exit-codes 0 ok, 2 missing-api-key-or-missing-positional, 3 graphql-or-http-error
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: missing-positional | exit=2 | visible=stderr-get-issue-requires-an-issue-identifier | mitigation=supply-issue-id
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-issue-exists-and-key
# contract: read-only-no-mutations
# anchor: BTS-245 (manifest seed)
cmd_get_issue() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  if [[ $# -lt 1 ]]; then
    # @failure-mode: missing-positional
    _die 2 "get-issue requires an issue identifier (e.g., BTS-164)"
  fi
  local id="$1"

  local variables
  variables=$(jq -nc --arg id "$id" '{id:$id}')

  local query='query ($id: String!) {
    issue(id: $id) {
      id identifier title priority createdAt updatedAt description
      state { name type id }
      labels { nodes { name } }
    }
  }'

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" "$variables" | jq '.issue | {
    id: .identifier,
    uuid: .id,
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

# @manifest
# purpose: Wrap the Linear GraphQL `workflowStates` query — emits {id, name, type} per state for a given team so operations.sh ticket.transition resolvers can map role names to state UUIDs at config time
# input: --team <name>
# input: env LINEAR_API_KEY
# output: stdout JSON array [{id, name, type}]
# output: exit-codes 0 ok, 2 missing-api-key-or-unknown-flag, 3 graphql-or-http-error
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: unknown-flag | exit=2 | visible=stderr-list-states-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-team-name-and-key
# contract: emits-empty-array-when-no-matches
# anchor: BTS-245 (manifest seed)
cmd_list_states() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  local team=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team) team="$2"; shift 2 ;;
      # @failure-mode: unknown-flag
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

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" "$variables" | jq '[.workflowStates.nodes[] | {id, name, type}]'
}

# @manifest
# purpose: Wrap the Linear GraphQL `issueLabels` query with optional team scoping (--team name, --team-id UUID, or --workspace-scoped for null-team labels) — used by save-issue label-resolution and BTS-170's workspace-vs-team label disambiguation
# input: --team <name>
# input: --team-id <uuid>
# input: --workspace-scoped (mutually exclusive with --team / --team-id)
# input: env LINEAR_API_KEY
# output: stdout JSON array [{id, name}]
# output: exit-codes 0 ok, 2 missing-api-key-or-unknown-flag-or-mutex-violation, 3 graphql-or-http-error
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: unknown-flag | exit=2 | visible=stderr-list-labels-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: workspace-team-mutex | exit=2 | visible=stderr-workspace-scoped-is-mutually-exclusive | mitigation=pick-one-scoping-mode
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-filter-shape-and-key
# contract: --team-id-wins-over-team-when-both-present
# contract: workspace-scoped-uses-null-team-direct-boolean
# anchor: BTS-245 (manifest seed)
cmd_list_labels() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  local team="" team_id="" workspace_scoped=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team)             team="$2";    shift 2 ;;
      --team-id)          team_id="$2"; shift 2 ;;
      --workspace-scoped) workspace_scoped=true; shift ;;
      # @failure-mode: unknown-flag
      *) _die 2 "list-labels: unknown flag: $1" ;;
    esac
  done

  # BTS-170: --workspace-scoped is mutually exclusive with team scoping —
  # workspace-scoped means "no team filter," not "team filter AND null."
  if $workspace_scoped && [[ -n "$team_id" || -n "$team" ]]; then
    # @failure-mode: workspace-team-mutex
    _die 2 "list-labels: --workspace-scoped is mutually exclusive with --team / --team-id"
  fi

  # BTS-166: --team-id wins over --team for scoping (mirrors save-issue
  # precedence). Allows multi-team-aware callers to pass the already-known
  # UUID and skip a name-resolution roundtrip while still scoping the label
  # filter precisely.
  local filter='{}'
  if $workspace_scoped; then
    # BTS-170: Linear's NullableTeamFilter uses a direct boolean for `null`,
    # not the BooleanComparator wrapper. `{team:{null:true}}` matches labels
    # where team is null (workspace-scoped). Verified against live API
    # 2026-04-26 — `{team:{null:{eq:true}}}` is rejected.
    filter=$(printf '%s' "$filter" | jq '. + {team:{null:true}}')
  elif [[ -n "$team_id" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team_id" '. + {team:{id:{eq:$v}}}')
  elif [[ -n "$team" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team" '. + {team:{name:{eq:$v}}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: IssueLabelFilter) {
    issueLabels(filter: $filter) {
      nodes { id name }
    }
  }'

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" "$variables" | jq '[.issueLabels.nodes[] | {id, name}]'
}

# BTS-166: name-based create flags in save-issue need NAME→ID lookups for
# team and project. Both follow the same shape as list-labels: optional
# --name filter, returns [{id, name}].

# @manifest
# purpose: Wrap the Linear GraphQL `teams` query with optional --name filter — emits {id, name, key} per team so save-issue can resolve team names to UUIDs without a name-lookup roundtrip per call
# input: --name <name>
# input: env LINEAR_API_KEY
# output: stdout JSON array [{id, name, key}]
# output: exit-codes 0 ok, 2 missing-api-key-or-unknown-flag, 3 graphql-or-http-error
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: unknown-flag | exit=2 | visible=stderr-list-teams-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-team-name-and-key
# contract: emits-empty-array-when-no-matches
# anchor: BTS-245 (manifest seed)
cmd_list_teams() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      # @failure-mode: unknown-flag
      *) _die 2 "list-teams: unknown flag: $1" ;;
    esac
  done

  local filter='{}'
  if [[ -n "$name" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$name" '. + {name:{eq:$v}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: TeamFilter) {
    teams(filter: $filter) {
      nodes { id name key }
    }
  }'

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" "$variables" | jq '[.teams.nodes[] | {id, name, key}]'
}

# @manifest
# purpose: Wrap the Linear GraphQL `projects` query with optional --name filter — emits {id, name, slugId} per project so save-issue can resolve project names to UUIDs at create time
# input: --name <name>
# input: env LINEAR_API_KEY
# output: stdout JSON array [{id, name, slugId}]
# output: exit-codes 0 ok, 2 missing-api-key-or-unknown-flag, 3 graphql-or-http-error
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: unknown-flag | exit=2 | visible=stderr-list-projects-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-project-name-and-key
# contract: emits-empty-array-when-no-matches
# anchor: BTS-245 (manifest seed)
cmd_list_projects() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      # @failure-mode: unknown-flag
      *) _die 2 "list-projects: unknown flag: $1" ;;
    esac
  done

  local filter='{}'
  if [[ -n "$name" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$name" '. + {name:{eq:$v}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: ProjectFilter) {
    projects(filter: $filter) {
      nodes { id name slugId }
    }
  }'

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" "$variables" | jq '[.projects.nodes[] | {id, name, slugId}]'
}

# BTS-228: create an Issue↔Issue relation. Linear's IssueUpdateInput does
# NOT support duplicate/blocks/related fields — those are separate
# IssueRelation entities created via issueRelationCreate. This subcommand
# wraps that mutation as a clean primitive; cmd_save_issue's --duplicate-of
# convenience flag dispatches through this path internally.
# @manifest
# purpose: Wrap the Linear GraphQL `issueRelationCreate` mutation — creates one of three relation types (duplicate, blocks, related) between two issues so the duplicate-of dispatch path in /idea triage and cmd_save_issue's BTS-228 follow-up can record the link as a proper IssueRelation entity (not as an IssueUpdateInput field, which Linear rejects)
# input: --type <duplicate|blocks|related>
# input: --issue <uuid>
# input: --related <uuid>
# input: env LINEAR_API_KEY
# output: stdout JSON {id, type}
# output: exit-codes 0 ok, 2 missing-api-key-or-unknown-flag-or-missing-required-flag-or-bad-type, 3 graphql-or-http-error
# caller: cmd_save_issue
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: creates-issue-relation-on-linear
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: unknown-flag | exit=2 | visible=stderr-create-relation-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: missing-type | exit=2 | visible=stderr-create-relation-type-required | mitigation=supply-type-flag
# failure-mode: bad-type | exit=2 | visible=stderr-create-relation-unknown-type | mitigation=use-duplicate-blocks-or-related
# failure-mode: missing-issue | exit=2 | visible=stderr-create-relation-issue-required | mitigation=supply-issue-uuid
# failure-mode: missing-related | exit=2 | visible=stderr-create-relation-related-required | mitigation=supply-related-uuid
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-uuids-and-key
# contract: requires-uuid-not-identifier-shaped-args
# anchor: BTS-245 (manifest seed)
cmd_create_relation() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  local rel_type="" issue_id="" related_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)    rel_type="$2";    shift 2 ;;
      --issue)   issue_id="$2";    shift 2 ;;
      --related) related_id="$2";  shift 2 ;;
      # @failure-mode: unknown-flag
      *) _die 2 "create-relation: unknown flag: $1" ;;
    esac
  done
  case "$rel_type" in
    duplicate|blocks|related) ;;
    # @failure-mode: missing-type
    "")  _die 2 "create-relation: --type required (duplicate|blocks|related)" ;;
    # @failure-mode: bad-type
    *)   _die 2 "create-relation: unknown --type '$rel_type' (valid: duplicate|blocks|related)" ;;
  esac
  # @failure-mode: missing-issue
  [[ -z "$issue_id" ]]   && _die 2 "create-relation: --issue required (issue UUID)"
  # @failure-mode: missing-related
  [[ -z "$related_id" ]] && _die 2 "create-relation: --related required (related issue UUID)"

  local query='mutation IssueRelationCreate($input: IssueRelationCreateInput!) {
    issueRelationCreate(input: $input) {
      success
      issueRelation { id type }
    }
  }'
  local variables
  variables=$(jq -nc \
    --arg type "$rel_type" \
    --arg issueId "$issue_id" \
    --arg relatedIssueId "$related_id" \
    '{input:{type:$type, issueId:$issueId, relatedIssueId:$relatedIssueId}}')

  # @failure-mode: graphql-or-http-error
  # @side-effect: creates-issue-relation-on-linear
  _post_graphql "$query" "$variables" | jq '.issueRelationCreate.issueRelation | {id, type}'
}

# @manifest
# purpose: Wrap the Linear GraphQL `issueCreate` and `issueUpdate` mutations under a single command — branches on --id presence (update vs create), supports name-based resolution of team/project/label via list-teams/list-projects/list-labels round-trips, layers stdin-JSON over CLI flags so callers can pre-compose IssueCreateInput shape, and dispatches duplicate-of as a follow-up issueRelationCreate (BTS-228 — Linear rejects duplicate-of inside IssueUpdateInput)
# input: --id <issue-id-for-update>
# input: --title / --description / --state / --team-id / --project-id / --parent-id / --duplicate-of / --priority / --label-ids / --team / --project / --labels / --input-json -
# input: env LINEAR_API_KEY
# input: stdin JSON object when --input-json - is supplied
# output: stdout JSON {id, title}
# output: exit-codes 0 ok, 2 missing-api-key-or-unknown-flag-or-missing-required-on-create-or-unresolved-name-or-bad-stdin-json, 3 graphql-or-http-error
# caller: skill:/idea
# caller: skill:/spec
# caller: skill:/activate
# caller: skill:/land
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# depends-on: cmd_list_teams
# depends-on: cmd_list_projects
# depends-on: cmd_list_labels
# depends-on: cmd_create_relation
# depends-on: cat
# depends-on: head
# depends-on: printf
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: reads-stdin-when-input-json
# side-effect: creates-or-updates-issue-on-linear
# side-effect: creates-issue-relation-when-duplicate-of-supplied
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: unknown-flag | exit=2 | visible=stderr-save-issue-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: unresolved-team-name | exit=2 | visible=stderr-save-issue-team-did-not-resolve | mitigation=verify-team-name-or-use-team-id
# failure-mode: unresolved-project-name | exit=2 | visible=stderr-save-issue-project-did-not-resolve | mitigation=verify-project-name-or-use-project-id
# failure-mode: unresolved-label-name | exit=2 | visible=stderr-save-issue-labels-did-not-resolve | mitigation=verify-label-name-and-team-scoping
# failure-mode: bad-input-json-shape | exit=2 | visible=stderr-save-issue-input-json-not-valid-object | mitigation=supply-valid-json-object-on-stdin
# failure-mode: input-json-non-stdin | exit=2 | visible=stderr-save-issue-input-json-only-supports-stdin | mitigation=use-input-json-dash
# failure-mode: missing-create-title | exit=2 | visible=stderr-save-issue-create-requires-title | mitigation=supply-title-or-include-in-stdin-json
# failure-mode: missing-create-team-id | exit=2 | visible=stderr-save-issue-create-requires-team-id | mitigation=supply-team-id-or-team-name
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-input-shape-and-key
# failure-mode: relation-create-warning | exit=0 | visible=stderr-WARN-save-issue-relation-create-failed | mitigation=run-printed-create-relation-retry-recipe
# contract: cli-flags-override-stdin-json-on-key-collision
# contract: id-flags-take-precedence-over-name-resolution-flags
# contract: duplicate-of-dispatched-as-separate-relation-mutation-after-update
# anchor: BTS-245 (manifest seed)
cmd_save_issue() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key

  # Mode selector: presence of --id triggers update; absence triggers create.
  # Caller-provided IDs only — name resolution (team/project/label NAMES → IDs)
  # is the resolver's job in Step 7. The wrapper stays focused on transport.
  local id="" title="" description="" state=""
  local team_id="" project_id="" parent_id="" duplicate_of=""
  local priority="" label_ids=""
  local input_json=""
  local team_name="" project_name="" labels_csv=""

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
      --input-json)    input_json="$2";   shift 2 ;;
      --team)          team_name="$2";    shift 2 ;;
      --project)       project_name="$2"; shift 2 ;;
      --labels)        labels_csv="$2";   shift 2 ;;
      # @failure-mode: unknown-flag
      *) _die 2 "save-issue: unknown flag: $1" ;;
    esac
  done

  # BTS-166 AC-2: name-based create flags. Resolve NAME→ID via list-teams /
  # list-projects / list-labels when --*-id wasn't passed. -id flags take
  # precedence on collision (caller knows the UUID; skip the extra roundtrip).
  #
  # Round-trip cost for the all-names-no-ids path: 3 GraphQL calls before
  # the issueCreate (teams → projects → labels [+ optional teams again
  # internal to list-labels' team-name filter]). For high-frequency callers
  # that already have IDs in config, prefer --*-id to skip the lookups.
  if [[ -z "$team_id" && -n "$team_name" ]]; then
    team_id=$(cmd_list_teams --name "$team_name" | jq -r '.[0].id // ""')
    if [[ -z "$team_id" ]]; then
      # @failure-mode: unresolved-team-name
      _die 2 "save-issue: --team '$team_name' did not resolve to a team id"
    fi
  fi
  if [[ -z "$project_id" && -n "$project_name" ]]; then
    project_id=$(cmd_list_projects --name "$project_name" | jq -r '.[0].id // ""')
    if [[ -z "$project_id" ]]; then
      # @failure-mode: unresolved-project-name
      _die 2 "save-issue: --project '$project_name' did not resolve to a project id"
    fi
  fi
  if [[ -z "$label_ids" && -n "$labels_csv" ]]; then
    # Resolve each NAME → ID with proper team scoping. Prefer the resolved
    # team_id (UUID) when present; fall back to team_name. Without scoping,
    # multi-team workspaces could silently pick the wrong label when two
    # teams share a label name.
    local resolved_ids=""
    local IFS_old="$IFS"; IFS=,
    for label_name in $labels_csv; do
      local label_filter=()
      if [[ -n "$team_id" ]]; then
        label_filter=(--team-id "$team_id")
      elif [[ -n "$team_name" ]]; then
        label_filter=(--team "$team_name")
      fi
      local lid
      # Safe-expand for empty label_filter under `set -u` (bash 4.x quirk).
      lid=$(cmd_list_labels "${label_filter[@]+"${label_filter[@]}"}" | jq -r --arg n "$label_name" '.[] | select(.name == $n) | .id' | head -1)
      # BTS-170: when team-scoping was set but the team-scoped lookup found
      # no label by that name, fall through to a workspace-scoped lookup.
      # Workspace-scoped labels (team:null) are NOT included in the team
      # filter; without this fallback, e.g. `--labels idea` fails on
      # workspaces where 'idea' is workspace-scoped, not team-scoped.
      if [[ -z "$lid" && ${#label_filter[@]} -gt 0 ]]; then
        lid=$(cmd_list_labels --workspace-scoped | jq -r --arg n "$label_name" '.[] | select(.name == $n) | .id' | head -1)
      fi
      if [[ -z "$lid" ]]; then
        # @failure-mode: unresolved-label-name
        _die 2 "save-issue: --labels '$label_name' did not resolve to a label id"
      fi
      resolved_ids="${resolved_ids:+${resolved_ids},}${lid}"
    done
    IFS="$IFS_old"
    label_ids="$resolved_ids"
  fi

  # BTS-166 AC-1: --input-json -  reads a JSON object from stdin and seeds the
  # input object. CLI flags layered on top, so command-line values override
  # stdin fields on key collision (matches the typical "config + override" UX).
  local stdin_input='{}'
  if [[ -n "$input_json" ]]; then
    if [[ "$input_json" == "-" ]]; then
      # @side-effect: reads-stdin-when-input-json
      stdin_input=$(cat)
    else
      # @failure-mode: input-json-non-stdin
      _die 2 "save-issue: --input-json currently supports only '-' (stdin)"
    fi
    # Validate it's a JSON object before merging.
    if ! printf '%s' "$stdin_input" | jq -e 'type == "object"' >/dev/null 2>&1; then
      # @failure-mode: bad-input-json-shape
      _die 2 "save-issue: --input-json - did not receive a valid JSON object on stdin"
    fi
  fi

  # Build the input object incrementally — Linear's IssueCreateInput and
  # IssueUpdateInput share the same field names for everything we set.
  # BTS-166: seed the input object from stdin-JSON when present. CLI flags
  # below merge on top, so flag values override stdin fields on collision.
  local input="$stdin_input"
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
  # BTS-228: do NOT append duplicateOf to IssueUpdateInput — Linear rejects
  # the field. Duplicate-of is an IssueRelation entity created via a separate
  # issueRelationCreate mutation (cmd_create_relation). The relation dispatch
  # happens AFTER a successful issueUpdate, below.
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
    # Create mode. Required: title (in $title or stdin-JSON), team_id (same).
    # Linear's schema requires both; emitting a clear error here surfaces the
    # gap before the API call. Check the merged input, not just the flag vars,
    # so stdin-JSON-only callers (BTS-166) aren't flagged spuriously.
    if [[ -z "$(echo "$input" | jq -r '.title // ""')" ]]; then
      # @failure-mode: missing-create-title
      _die 2 "save-issue create requires --title"
    fi
    if [[ -z "$(echo "$input" | jq -r '.teamId // ""')" ]]; then
      # @failure-mode: missing-create-team-id
      _die 2 "save-issue create requires --team-id (use list-teams to discover)"
    fi

    local query='mutation IssueCreate($input: IssueCreateInput!) {
      issueCreate(input: $input) { success issue { identifier title } }
    }'
    local variables
    variables=$(jq -n --argjson i "$input" '{input:$i}')
    # @failure-mode: graphql-or-http-error
    # @side-effect: creates-or-updates-issue-on-linear
    _post_graphql "$query" "$variables" | jq '.issueCreate.issue | {
      id: .identifier,
      title: .title
    }'
  else
    # Update mode. Linear's issueUpdate accepts the same input shape minus
    # creation-only fields (teamId is rejected for update, but we already
    # don't add it for the update path's expected callers).
    # BTS-228: query also returns the issue UUID (`id`) so the post-update
    # relation dispatch (when --duplicate-of was supplied) can use it.
    local query='mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) { success issue { id identifier title } }
    }'
    local variables
    variables=$(jq -n --arg id "$id" --argjson i "$input" '{id:$id, input:$i}')
    local update_response
    update_response=$(_post_graphql "$query" "$variables")

    # BTS-228: dispatch the IssueRelation as a follow-up when --duplicate-of
    # was supplied. State transition has already succeeded; relation failure
    # is non-fatal (WARN + retry recipe). Linear's relation API requires
    # both endpoints as UUIDs.
    if [[ -n "$duplicate_of" ]]; then
      local issue_uuid
      issue_uuid=$(printf '%s' "$update_response" | jq -r '.issueUpdate.issue.id // empty')
      if [[ -n "$issue_uuid" ]]; then
        # @side-effect: creates-issue-relation-when-duplicate-of-supplied
        if ! cmd_create_relation --type duplicate --issue "$issue_uuid" --related "$duplicate_of" >/dev/null 2>&1; then
          # @failure-mode: relation-create-warning
          echo "WARN: save-issue: relation-create-failed — type=duplicate from=$id to=$duplicate_of" >&2
          echo "Retry: bash linear-query.sh create-relation --type duplicate --issue $issue_uuid --related $duplicate_of" >&2
        fi
      else
        echo "WARN: save-issue: relation-create-failed — could not resolve issue uuid for relation dispatch" >&2
        echo "Retry: bash linear-query.sh create-relation --type duplicate --issue <uuid-of-$id> --related $duplicate_of" >&2
      fi
    fi

    # Re-emit the existing output shape ({id: identifier, title}) for callers.
    printf '%s' "$update_response" | jq '.issueUpdate.issue | {
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
    list-teams)    cmd_list_teams    "$@" ;;
    list-projects) cmd_list_projects "$@" ;;
    save-issue)   cmd_save_issue   "$@" ;;
    create-relation) cmd_create_relation "$@" ;;
    resolve-document-id) cmd_resolve_document_id "$@" ;;
    get-document) cmd_get_document "$@" ;;
    save-document) cmd_save_document "$@" ;;
    document-updated-at) cmd_document_updated_at "$@" ;;
    trash-document) cmd_trash_document "$@" ;;
    list-documents) cmd_list_documents "$@" ;;
    document-history) cmd_document_history "$@" ;;
    *)
      _die 2 "Unknown subcommand: $subcommand. Run 'linear-query.sh --help' for usage."
      ;;
  esac
}

# -----------------------------------------------------------------------------
# BTS-204: lifecycle-Document deterministic ID namespace.
# Pinned hex string used as the salt for SHA-256-based deterministic ID
# derivation. The output is UUID-shaped (8-4-4-4-12 hex) but is NOT an
# RFC-4122 v5 UUID — version/variant bits are not set. Linear's API accepts
# any UUID-format string. Changing this constant breaks every existing
# document mapping. Don't.
# -----------------------------------------------------------------------------
BTS_NS="5b8e4a8e-4f3c-4d2a-9c1e-bf204550b91d"

# @manifest
# purpose: Deterministically derive a Linear-Document UUID from (BTS_NS, kind, ticket) by SHA-256-hashing the composite input and substituting RFC 4122 v4 version + variant nibbles — provides stable, no-network UUIDs for the SSOT-Linear flow's spec/plan/stasis Documents so artifact-write upserts hit the same target across sessions
# input: --kind <spec|plan|feature-stasis|session-stasis>
# input: --ticket <ticket-id>
# input: env BTS_NS (namespace prefix)
# output: stdout one v4-shaped UUID
# output: exit-codes 0 ok, 2 missing-or-bad-flag
# caller: cmd_artifact_read
# caller: cmd_artifact_write
# depends-on: shasum
# depends-on: awk
# depends-on: printf
# depends-on: _die
# side-effect: pure-no-mutations
# failure-mode: unknown-flag | exit=2 | visible=stderr-resolve-document-id-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: missing-kind | exit=2 | visible=stderr-resolve-document-id-kind-is-required | mitigation=supply-kind-flag
# failure-mode: missing-ticket | exit=2 | visible=stderr-resolve-document-id-ticket-is-required | mitigation=supply-ticket-flag
# failure-mode: bad-kind | exit=2 | visible=stderr-resolve-document-id-unknown-kind | mitigation=use-spec-plan-feature-stasis-or-session-stasis
# contract: deterministic-no-network
# contract: emits-rfc-4122-v4-shaped-uuid-not-rng-actual-v4
# anchor: BTS-245 (manifest seed)
cmd_resolve_document_id() {
  # @side-effect: pure-no-mutations
  local kind="" ticket=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind)   kind="${2:-}";   shift 2 ;;
      --ticket) ticket="${2:-}"; shift 2 ;;
      # @failure-mode: unknown-flag
      *) _die 2 "resolve-document-id: unknown flag: $1" ;;
    esac
  done

  # @failure-mode: missing-kind
  [[ -z "$kind" ]]   && _die 2 "resolve-document-id: --kind is required"
  # @failure-mode: missing-ticket
  [[ -z "$ticket" ]] && _die 2 "resolve-document-id: --ticket is required"

  case "$kind" in
    spec|plan|feature-stasis|session-stasis) ;;
    # @failure-mode: bad-kind
    *) _die 2 "resolve-document-id: unknown kind '$kind' (must be one of: spec, plan, feature-stasis, session-stasis)" ;;
  esac

  local input hash
  input="${BTS_NS}:${kind}:${ticket}"
  hash=$(printf '%s' "$input" | shasum -a 256 | awk '{print $1}')

  # BTS-216: force RFC 4122 v4-shaped version + variant nibbles. Linear's
  # GraphQL validator (`class-validator` isUuid('4')) accepts ONLY UUID v4
  # — v3/v5 are live-rejected with `"id must be a UUID"`. Live-validated
  # against api.linear.app/graphql on 2026-04-27 with hand-crafted control
  # UUIDs: `aaaaaaaa-bbbb-4ccc-8ddd-...` succeeded, `5ccc` variant failed.
  #
  # Substituting the version nibble with literal '4' (UUID v4 — random)
  # and variant with '8' (10xx) makes every output a structurally-valid
  # RFC 4122 v4-shaped UUID while keeping the derivation deterministic.
  # Note: this is "v4-shaped" not actually-v4 (which would require RNG);
  # we deterministically derive from SHA-256 of "<NS>:<kind>:<ticket>"
  # and force the version/variant nibbles. The validator checks shape,
  # not entropy. Stable across re-runs because we substitute with constants.
  local time_hi="4${hash:13:3}"        # version field (high nibble of byte 6) → 4
  local clock_seq_hi="8${hash:17:3}"   # variant field (high nibble of byte 8) → 10xx
  printf '%s-%s-%s-%s-%s\n' \
    "${hash:0:8}" "${hash:8:4}" "$time_hi" "$clock_seq_hi" "${hash:20:12}"
}

# @manifest
# purpose: Wrap the Linear GraphQL `document` query — fetches a single document by UUID or slug including title, markdown content, parent linkage (project/issue), and authorship metadata so the SSOT-Linear flow's artifact-read primitive can hydrate spec/plan/stasis bodies into local-shape envelopes
# input: positional <id-or-slug>
# input: env LINEAR_API_KEY
# output: stdout JSON {id, title, content, slugId, url, updatedAt, createdAt, updatedBy, creator, project, issue}
# output: exit-codes 0 ok, 2 missing-api-key-or-missing-positional, 3 graphql-or-http-error
# caller: cmd_artifact_read
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: missing-positional | exit=2 | visible=stderr-get-document-requires-an-id-or-slug | mitigation=supply-id-or-slug
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-id-and-key
# contract: read-only-no-mutations
# anchor: BTS-245 (manifest seed)
cmd_get_document() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  if [[ $# -lt 1 ]]; then
    # @failure-mode: missing-positional
    _die 2 "get-document requires an id or slug (e.g., 5b8e4a8e-... or spec-bts-204)"
  fi
  local id="$1"

  local variables
  variables=$(jq -nc --arg id "$id" '{id:$id}')

  local query='query ($id: String!) {
    document(id: $id) {
      id title content slugId url updatedAt createdAt
      updatedBy { id name }
      creator { id name }
      project { id }
      issue { id identifier }
    }
  }'

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" "$variables" | jq '.document | {
    id: .id,
    title: .title,
    content: .content,
    slugId: .slugId,
    url: .url,
    updatedAt: .updatedAt,
    createdAt: .createdAt,
    updatedBy: (.updatedBy // null),
    creator: (.creator // null),
    project: (.project // null),
    issue: (.issue // null)
  }'
}

cmd_save_document() {
  _require_api_key

  local id="" title="" content=""
  local issue_id="" project_id="" initiative_id=""
  local trashed="" input_json=""
  # BTS-204: --create-with-id forces documentCreate even when stdin .id is
  # set, treating that id as DocumentCreateInput.id (caller-supplied UUID
  # for idempotent first-write). Without this flag, stdin .id triggers
  # documentUpdate (existing behavior preserved for back-compat).
  local create_with_id=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)             id="$2";             shift 2 ;;
      --title)          title="$2";          shift 2 ;;
      --content)        content="$2";        shift 2 ;;
      --issue-id)       issue_id="$2";       shift 2 ;;
      --project-id)     project_id="$2";     shift 2 ;;
      --initiative-id)  initiative_id="$2";  shift 2 ;;
      --trashed)        trashed="$2";        shift 2 ;;
      --input-json)     input_json="$2";     shift 2 ;;
      --create-with-id) create_with_id=1;    shift   ;;
      *) _die 2 "save-document: unknown flag: $1" ;;
    esac
  done

  # Stdin-JSON seed (BTS-166 pattern). CLI flags layer on top.
  local stdin_input='{}'
  if [[ -n "$input_json" ]]; then
    if [[ "$input_json" == "-" ]]; then
      stdin_input=$(cat)
    else
      _die 2 "save-document: --input-json currently supports only '-' (stdin)"
    fi
    if ! printf '%s' "$stdin_input" | jq -e 'type == "object"' >/dev/null 2>&1; then
      _die 2 "save-document: --input-json - did not receive a valid JSON object on stdin"
    fi
  fi

  # Promote stdin .id into $id so mode-detection works for stdin-only callers.
  # When --create-with-id is set, the id stays in input (DocumentCreateInput.id)
  # and we DON'T promote it to $id (which would route to update mode).
  if [[ "$create_with_id" -eq 0 && -z "$id" ]]; then
    id=$(printf '%s' "$stdin_input" | jq -r '.id // ""')
  fi

  local input
  if [[ "$create_with_id" -eq 1 ]]; then
    # Keep id in input → routes to DocumentCreateInput.id
    input="$stdin_input"
  else
    input=$(printf '%s' "$stdin_input" | jq 'del(.id)')   # id is a path arg, not input
  fi
  if [[ -n "$title" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$title" '. + {title:$v}')
  fi
  if [[ -n "$content" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$content" '. + {content:$v}')
  fi
  if [[ -n "$issue_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$issue_id" '. + {issueId:$v}')
  fi
  if [[ -n "$project_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$project_id" '. + {projectId:$v}')
  fi
  if [[ -n "$initiative_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$initiative_id" '. + {initiativeId:$v}')
  fi
  if [[ -n "$trashed" ]]; then
    input=$(printf '%s' "$input" | jq --argjson v "$trashed" '. + {trashed:$v}')
  fi

  if [[ -z "$id" || "$create_with_id" -eq 1 ]]; then
    # Create. Title required; exactly one parent (issueId | projectId | initiativeId).
    if [[ -z "$(echo "$input" | jq -r '.title // ""')" ]]; then
      _die 2 "save-document create requires --title"
    fi
    local parents
    parents=$(echo "$input" | jq '[.issueId, .projectId, .initiativeId] | map(select(. != null and . != "")) | length')
    if [[ "$parents" -ne 1 ]]; then
      _die 2 "save-document create requires exactly one parent: --issue-id, --project-id, or --initiative-id"
    fi

    local query='mutation DocumentCreate($input: DocumentCreateInput!) {
      documentCreate(input: $input) {
        success
        document { id title content updatedAt }
      }
    }'
    local variables
    variables=$(jq -n --argjson i "$input" '{input:$i}')
    _post_graphql "$query" "$variables" | jq '.documentCreate.document | {
      id: .id,
      title: .title,
      content: .content,
      updatedAt: .updatedAt
    }'
  else
    # Update. Path arg = id; body = remaining input.
    local query='mutation DocumentUpdate($id: String!, $input: DocumentUpdateInput!) {
      documentUpdate(id: $id, input: $input) {
        success
        document { id title content updatedAt }
      }
    }'
    local variables
    variables=$(jq -n --arg id "$id" --argjson i "$input" '{id:$id, input:$i}')
    _post_graphql "$query" "$variables" | jq '.documentUpdate.document | {
      id: .id,
      title: .title,
      content: .content,
      updatedAt: .updatedAt
    }'
  fi
}

# @manifest
# purpose: Wrap the Linear GraphQL `document` query projecting only id + updatedAt + updatedBy — used by BTS-237's concurrent-edit guard to detect mid-flight document mutation by comparing remote updatedAt against the timestamp captured before the local write composed
# input: positional <id-or-slug>
# input: env LINEAR_API_KEY
# output: stdout JSON {id, updatedAt, updatedBy}
# output: exit-codes 0 ok, 2 missing-api-key-or-missing-positional, 3 graphql-or-http-error
# caller: cmd_artifact_write
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: missing-positional | exit=2 | visible=stderr-document-updated-at-requires-an-id | mitigation=supply-id-or-slug
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-id-and-key
# contract: read-only-no-mutations
# contract: minimal-projection-for-fast-conflict-check
# anchor: BTS-245 (manifest seed)
cmd_document_updated_at() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  if [[ $# -lt 1 ]]; then
    # @failure-mode: missing-positional
    _die 2 "document-updated-at requires an id or slug"
  fi
  local id="$1"

  local variables
  variables=$(jq -nc --arg id "$id" '{id:$id}')

  local query='query ($id: String!) {
    document(id: $id) {
      id updatedAt
      updatedBy { id name }
    }
  }'

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" "$variables" | jq '.document | {
    id: .id,
    updatedAt: .updatedAt,
    updatedBy: (.updatedBy // null)
  }'
}

cmd_trash_document() {
  _require_api_key
  if [[ $# -lt 1 ]]; then
    _die 2 "trash-document requires an id or slug"
  fi
  local id="$1"

  local variables
  variables=$(jq -nc --arg id "$id" '{id:$id}')

  local query='mutation DocumentDelete($id: String!) {
    documentDelete(id: $id) { success }
  }'

  _post_graphql "$query" "$variables" | jq '.documentDelete | {success: .success}'
}

# @manifest
# purpose: Wrap the Linear GraphQL `documents` query with optional parent scoping (--project / --issue / --initiative IDs) and an optional --with-content flag — emits {id, title, slugId, updatedAt, createdAt} per document so cmd_resolve_document_id and the SSOT-Linear flow can locate documents without per-call lookups
# input: --project <uuid>
# input: --issue <uuid>
# input: --initiative <uuid>
# input: --limit <int>
# input: --with-content (include markdown body in projection)
# input: env LINEAR_API_KEY
# output: stdout JSON array [{id, title, slugId, updatedAt, createdAt, +optional content}]
# output: exit-codes 0 ok, 2 missing-api-key-or-unknown-flag, 3 graphql-or-http-error
# depends-on: jq
# depends-on: _require_api_key
# depends-on: _post_graphql
# depends-on: _die
# side-effect: reads-env-LINEAR_API_KEY
# side-effect: makes-graphql-http-call
# failure-mode: missing-api-key | exit=2 | visible=stderr-LINEAR_API_KEY-not-set | mitigation=set-LINEAR_API_KEY
# failure-mode: unknown-flag | exit=2 | visible=stderr-list-documents-unknown-flag | mitigation=use-documented-flag-name
# failure-mode: graphql-or-http-error | exit=3 | visible=stderr-linear-query-GraphQL-error | mitigation=verify-filter-shape-and-key
# contract: emits-empty-array-when-no-matches
# contract: with-content-flag-toggles-projection
# anchor: BTS-245 (manifest seed)
cmd_list_documents() {
  # @failure-mode: missing-api-key
  # @side-effect: reads-env-LINEAR_API_KEY
  _require_api_key
  local project_id="" issue_id="" initiative_id=""
  local limit="50"
  local with_content=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)        project_id="$2";    shift 2 ;;
      --issue)          issue_id="$2";      shift 2 ;;
      --initiative)     initiative_id="$2"; shift 2 ;;
      --limit)          limit="$2";         shift 2 ;;
      --with-content)   with_content=1;     shift ;;
      # @failure-mode: unknown-flag
      *) _die 2 "list-documents: unknown flag: $1" ;;
    esac
  done

  local filter='{}'
  if [[ -n "$project_id" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$project_id" '. + {project:{id:{eq:$v}}}')
  fi
  if [[ -n "$issue_id" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$issue_id" '. + {issue:{id:{eq:$v}}}')
  fi
  if [[ -n "$initiative_id" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$initiative_id" '. + {initiative:{id:{eq:$v}}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" --argjson l "$limit" '{filter:$f, first:$l}')

  # BTS-214: --with-content flag includes the markdown body in the projection.
  # Used by _complete_archive_linear to batch-read all 3 lifecycle Documents
  # in one call (replaces 3 sequential get-document calls).
  local query projection
  if [[ $with_content -eq 1 ]]; then
    query='query ($filter: DocumentFilter, $first: Int) {
      documents(filter: $filter, first: $first) {
        nodes { id title content slugId updatedAt createdAt }
      }
    }'
    projection='[.documents.nodes[] | {
      id: .id,
      title: .title,
      content: .content,
      slugId: .slugId,
      updatedAt: .updatedAt,
      createdAt: .createdAt
    }]'
  else
    query='query ($filter: DocumentFilter, $first: Int) {
      documents(filter: $filter, first: $first) {
        nodes { id title slugId updatedAt createdAt }
      }
    }'
    projection='[.documents.nodes[] | {
      id: .id,
      title: .title,
      slugId: .slugId,
      updatedAt: .updatedAt,
      createdAt: .createdAt
    }]'
  fi

  # @failure-mode: graphql-or-http-error
  # @side-effect: makes-graphql-http-call
  _post_graphql "$query" "$variables" | jq "$projection"
}

cmd_document_history() {
  _require_api_key
  if [[ $# -lt 1 ]]; then
    _die 2 "document-history requires an id or slug"
  fi
  local id="$1"

  local variables
  variables=$(jq -nc --arg id "$id" '{id:$id}')

  local query='query ($id: String!) {
    documentContentHistory(id: $id) {
      history {
        id
        contentDataSnapshotAt
        actorIds
      }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.documentContentHistory.history[] | {
    id: .id,
    snapshotAt: .contentDataSnapshotAt,
    actorIds: (.actorIds // [])
  }]'
}

main "$@"
