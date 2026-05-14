# Feature: Split hub-managed CI checks into own workflow + heal across nodes

> Feature: bts-488-ccanvil-checks-workflow-split
> Work: linear:BTS-488
> Created: 1778728052
> Subject: Split hub-managed CI checks into own workflow + heal across nodes
> Status: In Progress

## Summary

Phase A.5 of the CI fire-drill. BTS-482 fixed the lifecycle-docs CI design bug on hub but the fix never reached downstream nodes — `.github/workflows/ci.yml` is not registered in any production node's `.ccanvil/ccanvil.lock`, so broadcast skips it (BTS-489 is the captured init-time root cause). Compounding: hub's `ci.yml` mixes concerns — `test:` is meant to be node-customized (e.g. inbox-toolbox wires `bats install + bats tests/`), while `lifecycle-docs:` + `security:` are meant to be hub-managed. A single file means hub can't ship gate updates without colliding with node customization. Solution: split hub-managed checks into a separate workflow file, `.github/workflows/ccanvil-checks.yml`, that is fully hub-owned (no per-node customization). A one-shot `heal-ci-workflows` substrate verb copies it onto every registered node, registers the file in each lockfile (so future broadcasts maintain it), and strips the now-duplicate `lifecycle-docs` + `security` jobs from each node's existing `ci.yml`.

## Job To Be Done

**When** I ship a hub-managed CI gate update (draft-guard, security threshold, fixture-allowlist),
**I want to** broadcast the change to all 14 registered downstream nodes deterministically,
**So that** the gate behavior stays consistent across the fleet without manual yaml surgery in every node.

## Acceptance Criteria

- [ ] **AC-1:** New file `.ccanvil/templates/github/workflows/ccanvil-checks.yml` exists with structure: `name: ccanvil-checks`, `on:` declares `pull_request: { branches: [main], types: [opened, synchronize, reopened, ready_for_review] }`, jobs include `lifecycle-docs:` (with BTS-482 `if: github.event_name == 'pull_request' && github.event.pull_request.draft == false`) and `security:`.
- [ ] **AC-2:** Hub's existing `.ccanvil/templates/github/workflows/ci.yml` is reduced to ONLY the `test:` job (placeholder `echo TODO`). Strings `lifecycle-docs:` and `security:` no longer appear in this file.
- [ ] **AC-3:** `INIT_GITHUB_TEMPLATES` array in `.ccanvil/scripts/ccanvil-sync.sh` includes the new mapping `workflows/ccanvil-checks.yml:.github/workflows/ccanvil-checks.yml`.
- [ ] **AC-4:** New substrate verb `cmd_heal_ci_workflows` in `ccanvil-sync.sh` accepts `--dry-run` flag, iterates registered nodes in `.ccanvil/registry.json`, skips entries whose path doesn't exist (the same predicate `cmd_broadcast` uses today). For each reachable node it: copies hub's `ccanvil-checks.yml` to node's `.github/workflows/ccanvil-checks.yml` (creating directories as needed), upserts a lockfile entry with `origin: "hub", hub_hash: <sha256>, local_hash: <sha256>, status: "clean", sync: "tracked"`, strips `lifecycle-docs:` and `security:` job blocks from node's existing `.github/workflows/ci.yml` (preserving the `test:` job and any other node-added jobs), and commits via `git -C <path> commit -m "chore(ccanvil-checks): split hub-managed CI gates (BTS-488)"` (no push — operator pushes manually after review).
- [ ] **AC-5 (idempotency):** Re-running `heal-ci-workflows` on an already-healed node is a no-op — no file write (because hashes match), no lockfile mutation, no commit (because git status is clean). Verified in bats by running the verb twice on a fixture node and asserting `git rev-parse HEAD` is unchanged between runs.
- [ ] **AC-6 (preservation):** When the node's existing `ci.yml` contains a customized `test:` job (e.g. additional steps beyond the hub placeholder), the heal preserves the `test:` job verbatim and ONLY strips `lifecycle-docs:` + `security:` blocks. Verified in bats by seeding a fixture with `test:` containing `Install bats` + `bats tests/` steps and asserting they survive heal.
- [ ] **AC-7 (graceful no-ci.yml):** When a node's `.github/workflows/ci.yml` doesn't exist, heal writes `ccanvil-checks.yml` cleanly and skips the strip phase. No error.
- [ ] **AC-8 (error path):** When `git -C <path> commit` fails (unrelated dirty tree), heal emits a clear stderr error citing the node and skips it (continues to next node). The fleet-wide loop never aborts on one node's failure.
- [ ] **AC-9 (regression):** Hub's full bats suite (`docs-check.sh test-suite-run --parallel`) passes 100%. Manifest stays 195/195, drift 0.
- [ ] **AC-10 (post-merge):** Operator runs `bash .ccanvil/scripts/ccanvil-sync.sh heal-ci-workflows` from hub; healed nodes show `ccanvil-checks.yml` present + `ci.yml` stripped + lockfile entry registered. NOT automated in the spec — manual post-merge verification.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/templates/github/workflows/ccanvil-checks.yml` | New — hub-managed gate workflow with draft-guard + security |
| `.ccanvil/templates/github/workflows/ci.yml` | Modified — reduced to `test:` job placeholder only |
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — adds `cmd_heal_ci_workflows` (~100 lines), updates `INIT_GITHUB_TEMPLATES`, registers main dispatch |
| `hub/tests/ccanvil-checks-workflow.bats` | New — yaml structure assertions on new + reduced templates |
| `hub/tests/heal-ci-workflows.bats` | New — substrate-verb behavior + idempotency + preservation + error-path tests |
| `.ccanvil/manifest-allowlist.txt` | Modified — register `cmd_heal_ci_workflows` |

## Dependencies

- **Requires:** existing `cmd_broadcast`'s node-iteration pattern (path-exists predicate, registry walk)
- **Requires:** existing lockfile shape (`origin`, `hub_hash`, `local_hash`, `status`, `sync`) — same shape as every other tracked file entry
- **Blocked by:** nothing

## Out of Scope

- Fix init-time lockfile registration bug (BTS-489, separate ticket). This spec heals existing nodes; init-time fix is upstream.
- Hub-level `.gitignore` distribution for credential-file patterns (BTS-490, separate ticket).
- Section-merge style yaml editing for the test job (we strip whole job blocks; we never merge). Yaml-aware editing is out of scope — heal uses anchored sed/awk patterns.
- Auto-push from heal. Heal commits but operator runs `git -C <path> push` (or aggregate via a follow-up substrate) to keep the operator in the loop.

## Implementation Notes

**ccanvil-checks.yml structure (hub template):**

```yaml
name: ccanvil-checks

on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, ready_for_review]

permissions:
  contents: read

jobs:
  lifecycle-docs:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request' && github.event.pull_request.draft == false
    steps:
      - uses: actions/checkout@v4
      - name: Check for stale lifecycle docs
        run: |
          stale=""
          [ -f docs/spec.md ] && stale="$stale docs/spec.md"
          [ -f docs/plan.md ] && stale="$stale docs/plan.md"
          [ -f docs/stasis.md ] && stale="$stale docs/stasis.md"
          if [ -n "$stale" ]; then
            echo "::error::Lifecycle docs must be cleaned up before merge:$stale"
            echo "Run: docs-check.sh complete <feature-id>"
            exit 1
          fi

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Security audit
        run: bash .ccanvil/scripts/security-audit.sh
```

**ci.yml reduced (hub template):**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # NODE-SPECIFIC: Replace with your project's test setup and command.
      - name: Run tests
        run: "echo TODO: Replace with your project test command"
```

**heal-ci-workflows job-strip pattern:**

```bash
# Strip a top-level job block (`  <name>:` through next top-level job key or EOF)
awk '
  /^  lifecycle-docs:/ || /^  security:/ { skip = 1; next }
  skip && /^  [a-zA-Z]/ { skip = 0 }
  !skip { print }
' "$ci_yml" > "$tmp" && mv "$tmp" "$ci_yml"
```

This preserves the `test:` job (and any other custom job) since we only skip while we're inside `lifecycle-docs:` or `security:` — re-enable at the next top-level `  <name>:` key.

**Test patterns to follow:**

- `hub/tests/ci-template-lifecycle-docs.bats` (BTS-482) for yaml grep-assertions
- `hub/tests/broadcast-resolve-auto.bats` for fixture-node iteration patterns
- `hub/tests/test-suite-run.bats` (BTS-460) for manifest registration pattern

**Manifest discipline:**

- `cmd_heal_ci_workflows` needs a `# @manifest` block per `.ccanvil/templates/manifest.md`. Registration in `.ccanvil/manifest-allowlist.txt` required.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
