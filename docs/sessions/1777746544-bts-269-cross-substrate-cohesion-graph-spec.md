# Feature: Cross-substrate cohesion graph

> Feature: bts-269-cross-substrate-cohesion-graph
> Work: linear:BTS-269
> Created: 1777744329
> Subject: Cross-substrate cohesion graph
> Status: In Progress

## Summary

Today the manifest substrate (BTS-239) extracts per-primitive `caller`/`depends-on`/`side-effect` declarations, but there's no aggregate view of the dependency graph across all 187 manifested entries. Architecture-shaped change — like a PR introducing an edge that crosses two substrate clusters that have been kept disjoint — slips through file-shaped diff review. This ticket adds `module-manifest.sh graph [--format json|dot]` that emits the full caller/depends-on edge set as JSON (default) or Graphviz DOT (visualization). Cluster definition is path-prefix-based for v1 — every manifested entry is assigned to a cluster (skills, scripts, hooks, rules, agents, commands), and edges crossing cluster boundaries are surfaced in the JSON envelope's `cross_cluster_edges` array. Future tooling (`/review`, CI, future cohesion-aware checks) consumes the envelope.

## Job To Be Done

**When** an operator wants to understand the dependency topology of the substrate or detect when a PR introduces a cross-cluster edge,
**I want to** run `bash .ccanvil/scripts/module-manifest.sh graph` and get a deterministic JSON representation of every edge with cluster annotations,
**So that** Layer 3 has the data layer for cohesion-aware code review (file-shaped diff review can never catch architecture-shaped change).

## Acceptance Criteria

- [ ] **AC-1:** `bash .ccanvil/scripts/module-manifest.sh graph` (no flags, JSON default) emits an envelope `{nodes: [{id, path, cluster}], edges: [{from, to, kind}], cross_cluster_edges: [{from, to, kind, from_cluster, to_cluster}], status: "ok"}` to stdout. Exit 0 always (read-only graph extraction never errors on empty graphs — emits `{nodes:[], edges:[], cross_cluster_edges:[], status:"ok"}` when allowlist is empty/missing).
- [ ] **AC-2 (nodes):** One node per manifested entry. `id = <path>:<fn>` for function-level entries, `<path>` for file-level. `path` is the file path. `cluster` is one of: `script` (`.ccanvil/scripts/*.sh`), `hook` (`.claude/hooks/*.sh`), `skill` (`.claude/skills/*/SKILL.md`), `rule` (`.claude/rules/*.md`), `agent` (`.claude/agents/*.md`), `command` (`.claude/commands/*.md`).
- [ ] **AC-3 (caller edges):** For each manifested entry P, every `caller:` declaration emits an edge `{from: <caller-id-or-path>, to: P.id, kind: "calls"}`. Caller resolution uses the same `_diff_normalize_caller_path` logic as BTS-268 (skill: form maps to file path).
- [ ] **AC-4 (depends-on edges):** For each manifested entry P, every `depends-on:` declaration emits an edge `{from: P.id, to: <dep-token>, kind: "depends-on"}`. The `to` field stays as the literal declared token (`jq`, `linear-query.sh`, `_helper_fn`) — graph doesn't try to resolve external commands to nodes; only manifested-entry-to-manifested-entry edges feed cluster-crossing detection.
- [ ] **AC-5 (cross_cluster_edges):** For every edge whose `from` AND `to` both resolve to manifested nodes (i.e., both ends are in the `nodes` array), emit a derived entry into `cross_cluster_edges` ONLY when `from.cluster != to.cluster`. Includes both `from_cluster` and `to_cluster` fields for downstream consumption.
- [ ] **AC-6 (DOT format):** Given `--format dot`, emit Graphviz DOT source instead of JSON. Each cluster wrapped as a `subgraph cluster_<name>`; each cross-cluster edge styled with `[color=red]` to make the architecture-shaped surface visually obvious. Exit 0; stderr empty.
- [ ] **AC-7 (error: unknown format):** Given `--format <unknown>`, stderr surfaces `ERROR: unknown --format value: <unknown>; supported: json, dot` and exit code is 2.
- [ ] **AC-8 (live dogfood):** Run `module-manifest.sh graph` on the hub's current 187-entry allowlist; confirm the JSON envelope contains `nodes.length == 187`, `edges.length > 0`, and `cross_cluster_edges.length > 0` (e.g., the `code-reviewer.md` agent has callers in `command` cluster — agent ↔ command is cross-cluster).
- [ ] **AC-9:** New bats test file `hub/tests/module-manifest-graph.bats` covers AC-1 through AC-7 with fixture allowlists in `hub/tests/fixtures/manifest/graphs/` (small synthetic substrates with known cluster configurations + edge counts).
- [ ] **AC-10:** New `cmd_graph` primitive added to `.ccanvil/manifest-allowlist.txt` with complete `# @manifest` block — drift-guard remains 100% (187 → 188).

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/module-manifest.sh` | Modified — add `cmd_graph` + dispatch entry |
| `hub/tests/module-manifest-graph.bats` | New — bats coverage for AC-1..7 |
| `hub/tests/fixtures/manifest/graphs/*` | New — synthetic-substrate fixtures |
| `.ccanvil/manifest-allowlist.txt` | Modified — add `cmd_graph` entry |

## Dependencies

* **Requires:** `cmd_extract` (already shipped, BTS-239) for per-entry manifest data; the existing `_diff_normalize_caller_path` helper (BTS-268) for skill: → path mapping.
* **Blocked by:** none.

## Out of Scope

* `/review` integration. Detecting cross-cluster edges in a PR diff is a natural follow-up but ships separately if friction surfaces.
* Visual rendering UI (HTML/SVG via `dot -Tsvg`). DOT format is the substrate primitive; rendering happens in operator's choice of tooling.
* Cohesion heuristics beyond cross-cluster-edge detection (e.g., density, centrality, modularity scores). Those compose well with the JSON envelope and can be added as separate primitives.
* Caller resolution for non-manifested files (e.g., `bin/foo.py` calling `cmd_X`). The graph only includes nodes from the allowlist.
* Edge weights / call frequency. Edges are unweighted; one declaration = one edge.
* Auto-detecting cluster boundaries. Path-prefix-based clusters are the v1 definition; richer clustering (e.g., cohesion-derived clusters) is a research follow-up.

## Implementation Notes

* Pattern: `cmd_graph` follows `cmd_extract` / `cmd_validate` shape — manifest block, dispatch entry, pure bash + awk + jq (no graphviz dep — DOT is just text emission).
* Walk `cmd_index`'s output (`.ccanvil/state/manifests.json`) when present; otherwise re-extract per file from the allowlist (same fallback shape as `cmd_query`).
* Cluster derivation: a small helper `_node_cluster <path>` returns the cluster string per AC-2. Function-level entries inherit the file's cluster.
* Edge normalization: caller `skill:/<n>` form maps to `.claude/skills/<n>/SKILL.md` for matching against nodes (re-uses `_diff_normalize_caller_path`).
* DOT rendering: tight emission — `digraph G { ...; subgraph cluster_<name> { ... }; <edges>; }`. No external dot binary dependency at substrate level; that's the consumer's call.
* Live-API contract risk: NONE. Pure local file walk + JSON/text emission.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
