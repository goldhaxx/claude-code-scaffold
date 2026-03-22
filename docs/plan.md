# Implementation Plan: Deterministic Manifest Verification

> Created: 2026-03-22
> Based on: checkpoint next-step discussion

## Objective

Make README manifest verification maximally deterministic by pushing discovery, comparison, and diffing into a script, leaving Claude only the semantic judgment calls.

## Design

### The Problem

Manifest verification currently has three parts:
1. **File existence** — does each manifest path exist? Are there untracked files? → Fully computable
2. **Description accuracy** — does each description still match the file's purpose? → Seems stochastic, but can be decomposed
3. **Missing entry detection** — which files should be in the manifest but aren't? → Seems stochastic, but can be decomposed

### The Key Insight

Descriptions become stale when files change. If a file hasn't changed since its description was last verified, the description is still valid. This converts "read the file and judge the description" into "has the hash changed?" — a computable operation.

When a hash *has* changed, showing the *diff* since last verification is far more constrained than re-reading the whole file. Claude judges "does this diff affect the stated purpose?" rather than "is this 200-line file accurately described?"

For missing entries, the script extracts identity metadata (comment headers for scripts, first heading + frontmatter for markdown) to give Claude enough context to write a description without reading the full file.

### Architecture

```
scripts/manifest-check.sh     — deterministic: parse, hash, diff, discover
.claude/manifest.lock          — baseline: hashes + git commit at verification time
Claude                         — judgment on structured results only
```

### Stochastic Surface Area: Before vs After

| Operation | Before | After |
|-----------|--------|-------|
| Parse README tables, extract paths | Claude reads README, eyeballs it | **Script** parses markdown tables |
| Check file existence | Claude runs `ls` per file | **Script** batch-checks all paths |
| Find untracked files | Claude scans dirs, guesses what's tracked | **Script** compares dir listing vs manifest |
| Judge description accuracy | Claude reads full file + description | Claude reads **diff only** for changed files; unchanged files **auto-verified** |
| Extract identity for new files | Claude reads full file | **Script** extracts comment header / frontmatter / first heading |
| Write new descriptions | Claude (unavoidable) | Claude — but with structured metadata input |

**Result:** Claude's judgment is invoked only for stale descriptions (with a diff) and new entry descriptions (with identity metadata). Everything else is deterministic.

### manifest.lock Format

```json
{
  "meta": {
    "last_verified": "2026-03-22",
    "commit": "abc1234"
  },
  "entries": {
    ".claude/rules/tdd.md": {
      "file_hash": "sha256",
      "verified_at_commit": "abc1234",
      "verified": "2026-03-22"
    }
  }
}
```

Storing the git commit at verification time enables `git diff <commit> -- <path>` to produce the exact diff since last verification.

### Script Output (JSON)

```json
{
  "verified": [
    { "path": ".claude/rules/tdd.md", "status": "unchanged" }
  ],
  "stale": [
    {
      "path": ".claude/rules/workflow.md",
      "description": "current description from README",
      "diff": "--- a/.claude/rules/workflow.md\n+++ b/..."
    }
  ],
  "missing_from_manifest": [
    {
      "path": "scripts/new-thing.sh",
      "identity": "# new-thing.sh — Does X for Y\n# Usage: ...",
      "size_bytes": 1234
    }
  ],
  "missing_from_disk": [
    { "path": ".claude/rules/deleted.md", "description": "was: ..." }
  ],
  "summary": {
    "total": 30, "verified": 25, "stale": 2,
    "missing_from_manifest": 2, "missing_from_disk": 1
  }
}
```

## Sequence

### Step 1: Parse README manifest tables

- **Test:** Script parses a README with markdown tables, extracts `(path, description)` pairs from rows matching `| path | ... |` pattern
- **Implement:** `cmd_parse` function. Split on `|`, extract column 1 (path) and column 3 (description), trim whitespace and backticks. Skip header/separator rows.
- **Files:** `scripts/manifest-check.sh`, `tests/manifest-check.bats`
- **Verify:** Parse actual README, confirm all known entries extracted. Count matches expected total.

### Step 2: File existence + untracked file discovery

- **Test:** Given parsed entries, report which paths exist and which don't. Given tracked directories, report files not in manifest.
- **Implement:** `cmd_check_existence` function. Tracked directories: `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, `.claude/skills/`, `.claude/hooks/`, `scripts/`, `docs/templates/`. List files in each, diff against manifest paths.
- **Files:** `scripts/manifest-check.sh`, `tests/manifest-check.bats`
- **Verify:** Add an untracked file to a tracked dir, confirm it appears in `missing_from_manifest`

### Step 3: manifest.lock init + hash comparison

- **Test:** `manifest-check.sh init` creates `.claude/manifest.lock` from current README + file hashes + current git commit. `manifest-check.sh check` compares current hashes against lockfile.
- **Implement:** `cmd_init` creates lockfile. `cmd_check` re-hashes files, compares, categorizes as `verified` (unchanged) or `stale` (hash differs).
- **Files:** `scripts/manifest-check.sh`, `tests/manifest-check.bats`
- **Verify:** Init, modify a file, re-run check → file shows as stale

### Step 4: Diff generation for stale entries

- **Test:** Stale entries include a unified diff showing what changed since last verification
- **Implement:** Use `git diff <verified_at_commit> -- <path>` to produce the diff. Fallback to `diff` if commit is unavailable (rebase, shallow clone).
- **Files:** `scripts/manifest-check.sh`, `tests/manifest-check.bats`
- **Verify:** Modify a tracked file, commit, run check → diff shows the actual changes

### Step 5: Identity extraction for untracked files

- **Test:** For files not in the manifest, extract identity metadata. `.sh` → comment header lines (leading `#` block). `.md` → first heading + YAML frontmatter. Other → first 3 lines.
- **Implement:** `extract_identity` function
- **Files:** `scripts/manifest-check.sh`, `tests/manifest-check.bats`
- **Verify:** Add a new script with comment header, confirm identity extraction captures it

### Step 6: Full JSON report + verify subcommand

- **Test:** `manifest-check.sh check` produces complete JSON. `manifest-check.sh verify <paths...>` updates lockfile for confirmed entries.
- **Implement:** Wire all functions together for `check`. Add `cmd_verify` that updates hashes + commit SHA + timestamp for specified paths.
- **Files:** `scripts/manifest-check.sh`, `tests/manifest-check.bats`
- **Verify:** Full cycle: init → modify file → check (shows stale) → verify → check (shows verified)

### Step 7: Integration — slash command or workflow

- **Test:** N/A (documentation + wiring)
- **Implement:** Decide whether this warrants a `/manifest-check` command or integrates into `/scaffold-audit`. Update GUIDE.md and README with the new script.
- **Files:** GUIDE.md, README.md, possibly `.claude/commands/`
- **Verify:** End-to-end: run the command, review structured output, verify entries

## Risks

- **README table parsing fragility** — Markdown tables have variable formatting. Mitigation: test with actual README. Parser should fail loudly on unparseable rows rather than silently missing entries.
- **Git commit tracking for diffs** — Requires commits to exist (rebases, shallow clones may break). Mitigation: fall back to showing `[hash changed, diff unavailable]` and let Claude read the file.
- **Tracked directories list becomes stale** — If new directories are added to the scaffold. Mitigation: hardcode in script header with a comment. If the list is wrong, `missing_from_manifest` will be incomplete but nothing breaks.

## Definition of Done

- [ ] `manifest-check.sh init` creates `.claude/manifest.lock`
- [ ] `manifest-check.sh check` produces structured JSON with all 4 categories
- [ ] `manifest-check.sh verify <paths...>` updates lockfile entries
- [ ] Unchanged files auto-verified (no Claude needed)
- [ ] Changed files show diff (not full content) for Claude review
- [ ] Untracked files show identity metadata for description writing
- [ ] All new tests pass
- [ ] Existing 77 tests unaffected
