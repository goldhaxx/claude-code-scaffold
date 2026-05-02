---
manifest:
  id: review
  purpose: Three-layer review of uncommitted changes — (1) spawns the code-reviewer sub-agent for INFO/WARN/CRITICAL findings, (2) runs the deterministic security-audit substrate (--files-only), (3) lightweight self-review per `.claude/rules/self-review.md` for stochastic-op candidates. Recommends commit-or-fix-first.
  routes-by: /review
  input:
    - "no positional args (synthesizes from current uncommitted diff)"
  output:
    - "stdout: combined review + security audit + self-review summary with recommendation"
  depends-on:
    - security-audit.sh
  side-effect:
    - reads-only-no-mutations
  failure-mode:
    - "no-uncommitted-changes | exit=0 | visible=stdout-clean-message | mitigation=run-after-edits"
    - "critical-finding | exit=non-zero | visible=critical-list-with-rationale | mitigation=fix-before-commit"
  contract:
    - read-only
    - three-layer-coverage
  anchor:
    - BTS-256 (manifest seed)
---

Review the current uncommitted changes using the code-reviewer sub-agent.

## Step 0: Manifest pre-flight (BTS-257 Layer 3 ramp; BTS-268 deterministic gate)

Before spawning the code-reviewer agent, run two manifest pre-flight checks:

**Check A: structural drift (existing state).**

```bash
bash .ccanvil/scripts/module-manifest.sh validate --json 2>/dev/null
```

When `.ccanvil/manifest-allowlist.txt` exists, parse the JSON envelope:

- `coverage.covered == coverage.total` AND `drift == []` → silent pass.
- `(.drift | length) > 0` → render `## Manifest drift (existing state)` with one bullet per drifted entry (`<path>:<id> — <reason> [value]`).

**Check B: diff-introduced drift (BTS-268 deterministic Layer 3 gate).**

```bash
git diff main...HEAD | bash .ccanvil/scripts/module-manifest.sh diff-vs-manifest --diff -
```

Parse the JSON envelope:

- `status == "ok"` (drift == []) → silent pass.
- `status == "drift"` → render `## Manifest drift (introduced by this branch)` with one bullet per entry, format: `**<drift_type>** — <path> — value: <value>`. **All entries are BLOCKING** regardless of agent commentary. The operator must either (a) update the primitive's manifest declaration to include the new caller / depends-on / exit-path / side-effect, or (b) revert the introducing change.

Skip both checks silently when the allowlist is missing (downstream nodes that haven't adopted Layer 2 yet).

## Step 1: Code review

Delegate to the `code-reviewer` agent with this task:
"Review all uncommitted changes in this repository. Check for correctness, test coverage, security issues, performance concerns, manifest drift (BTS-257 Layer 3), and adherence to project conventions defined in CLAUDE.md."

## Step 2: Security audit

After the code review completes, run the security audit (deterministic):

```bash
bash .ccanvil/scripts/security-audit.sh --files-only
```

## Step 3: Self-review

Then do a quick self-review per `.claude/rules/self-review.md`: were there any stochastic operations in this session that should become deterministic? If so, note them briefly.

Summarize all three checks (code review, security audit, self-review) and recommend whether to commit or what to fix first.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
