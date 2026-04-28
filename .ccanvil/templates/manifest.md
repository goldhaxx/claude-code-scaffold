# Module Manifest Format

Layer 2 of the Dark Code framework — Self-Describing Systems. Every substrate primitive on the manifest allowlist (`.ccanvil/manifest-allowlist.txt`) carries a `# @manifest` comment block above its function definition that documents its contract in a form readable by humans, future-Claude, and CI.

Substrate: `.ccanvil/scripts/module-manifest.sh` (verbs: `extract`, `validate`, `query`, `index`).

## Block syntax

```bash
# @manifest
# <key>: <value>
# <key>: <value>
# ...
<function-name>() {
  ...
}
```

A block opens with a line whose content (after `# ` prefix) is exactly `@manifest`. Subsequent comment lines of the form `# <key>: <value>` are parsed as kv pairs until the first non-conforming line — typically the function definition. The function name on the first non-comment, non-blank line below the block becomes the manifest's `id` field.

Whitespace is tolerated (`# <key>:<value>`, `# <key>:  <value>` both work). Multi-line values are not supported — decompose into separate keys instead.

## Keys

**Required (validate enforces non-empty):**

| Key | Shape | Meaning |
|---|---|---|
| `purpose` | scalar string | One-line summary — what does this primitive do |
| `input` | array | Each form of input (positional, flag, env-var, stdin) |
| `output` | array | Each form of output (stdout, stderr, file, exit-code class) |
| `side-effect` | array | Mutations beyond the call (writes, transitions, log appends) |
| `failure-mode` | array (structured) | Each enumerated failure path (see schema below) |
| `contract` | array | Invariants the primitive guarantees |
| `anchor` | array | BTS-N references that anchor design or change |

**Optional:**

| Key | Shape | Meaning |
|---|---|---|
| `routes-by` | scalar string | Configuration key that drives behavior, if any |
| `caller` | array | Known callers (function names or `skill:/<name>`) |
| `depends-on` | array | Other primitives, helpers, or external commands the body invokes |

Repeated keys collapse into a JSON array. Scalar keys (`id`, `purpose`, `routes-by`) are emitted as plain strings; the rest are always arrays even when length 1.

## `failure-mode` line schema

Each `failure-mode:` value is a pipe-delimited record:

```
<id> | exit=<value> | visible=<phrase> | mitigation=<phrase>
```

Only `<id>` is required. Remaining segments are optional `key=value` pairs. `exit=` accepts numeric codes (`exit=2`, `exit=4`) or special tokens (`exit=passthrough`, `exit=propagate`, `exit=*`) when the code varies by called subcommand.

Example:

```
# failure-mode: concurrent-edit | exit=4 | visible=stderr-with-history-hint | mitigation=ALLOW_CONCURRENT_EDIT_OVERRIDE=1
```

## Source markers

Each declared `failure-mode: <id>` and `side-effect: <id>` requires at least one matching marker comment inside the function body:

```bash
cmd_artifact_write() {
  # @failure-mode: validation-error
  [[ -z "$kind" ]] && { echo "ERROR..."; return 2; }

  # @side-effect: writes-local-doc
  printf '%s' "$content" > "$target"
}
```

The marker carries the same `<id>` as the manifest entry. Markers are how drift-guard catches *behavior* changes (new exit path, new write site) without matching declarations in the manifest. Bidirectional: every manifest declaration must have a marker; markers without a manifest declaration are not yet enforced.

## Validation contract

`bash .ccanvil/scripts/module-manifest.sh validate [--json]` walks `.ccanvil/manifest-allowlist.txt` and asserts, per entry:

1. The file exists.
2. A manifest block exists with the named `id`.
3. Every required key is non-empty.
4. Every `failure-mode` record parses (non-empty id; segments are key=value).
5. Every `caller:` entry actually invokes the primitive — function-name callers have the primitive name in their body (word-boundary), or skill callers have it in the skill markdown (`.claude/skills/<n>/SKILL.md` or `.claude/commands/<n>.md`). Both function-name (`cmd_X`) and dispatch-verb (`X`-with-dashes) forms are accepted matches.
6. Every `depends-on:` entry appears (word-boundary) inside the primitive's body.
7. Every `failure-mode: <id>` and `side-effect: <id>` has a matching `# @failure-mode: <id>` or `# @side-effect: <id>` marker inside the body.

Any violation surfaces a `DRIFT: <path>:<id> reason=<class> [value=<v>]` line on stderr; `--json` mode also emits a structured envelope `{coverage, drift, status}`. Exit 0 on full validity; 2 on any drift.

## Allowlist format

```
# .ccanvil/manifest-allowlist.txt
.ccanvil/scripts/<file>.sh:<function>   # function-level entry
.ccanvil/scripts/<file>.sh              # file-level entry (id = basename without .sh)
```

Comments (`#` prefix) and blank lines are ignored. Entries are evaluated in file order.

## Worked example — function-level

The substrate's own `cmd_extract` (`.ccanvil/scripts/module-manifest.sh:cmd_extract`):

```bash
# @manifest
# purpose: Parse # @manifest blocks from a single file → JSON array, one object per block.
# input: positional <path>
# output: stdout JSON array
# output: exit-codes 0 ok, 2 usage-error|file-not-found|malformed-manifest
# depends-on: jq
# depends-on: _validate_failure_mode_value
# depends-on: _compose_block
# side-effect: writes-temp-file
# failure-mode: missing-path-arg | exit=2 | visible=stderr-usage
# failure-mode: file-not-found | exit=2 | visible=stderr-error
# failure-mode: malformed-manifest | exit=2 | visible=stderr-MALFORMED
# contract: emits-empty-array-for-no-blocks
# contract: never-partial-write-on-malformed
# anchor: BTS-239 (origin)
cmd_extract() {
  local path="${1:-}"
  # @failure-mode: missing-path-arg
  if [[ -z "$path" ]]; then
    ...
```

## Index and query

`module-manifest.sh index` walks all source dirs and writes a derived `<path>:<id>`-keyed JSON object to `.ccanvil/state/manifests.json` (gitignored, regenerated on demand). `query '<key>:<value>'` filters that index by substring match across scalar and array fields:

```
$ bash .ccanvil/scripts/module-manifest.sh query 'depends-on:linear-query.sh'
[
  { "id": "cmd_artifact_write", "purpose": "...", ... }
]
```

The index regenerates lazily — when any source file's mtime exceeds the index file's mtime, or when the index is missing.

## Out of scope (first ship — BTS-239)

- Markdown frontmatter manifests (skills, rules, agents). Shell only at first ship.
- Pre-commit hook (warn-only on mismatch). Drift-guard CI is the actual fence.
- `code-reviewer` agent / `/review` skill manifest-aware checks. Layer 3 ramps after coverage > 50%.
- Composable query expressions (AND/OR, regex). Substring-match suffices for v1.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
