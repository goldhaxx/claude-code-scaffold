# Plan: Idea capture and roadmap foundation

> Feature: idea-capture
> Spec hash: (from docs/spec.md)
> Created: 1775757518

## Approach

Add idea management subcommands to docs-check.sh (idea-add, idea-list, idea-count, idea-update), create the `/idea` skill, add the roadmap template, and wire into `/catchup`. TDD throughout.

## Steps

### Step 1: Create roadmap template
**File:** `preset/.ccanvil/templates/roadmap.md`

Simple markdown with guided sections. No script logic needed — this is a user document.

### Step 2: Test — idea-add creates file and appends (RED → GREEN)
**File:** `hub/tests/docs-check.bats`

Test: no ideas.md exists, run idea-add "test idea", assert file created with correct format.
Test: ideas.md exists with one entry, run idea-add "second idea", assert two entries.

**Implement:** `cmd_idea_add` in docs-check.sh. Creates `docs/ideas.md` if missing, appends `- [ ] <date>: <text> <!-- status:new -->`.

### Step 3: Test — idea-list outputs JSON (RED → GREEN)
Test: file with 3 entries (new, promoted, dismissed), run idea-list, assert JSON array with 3 items. Run idea-list --status new, assert 1 item.

**Implement:** `cmd_idea_list` — parse markdown lines with regex, output JSON.

### Step 4: Test — idea-count (RED → GREEN)
Test: file with mixed statuses, run idea-count, assert correct totals.

**Implement:** `cmd_idea_count` — count by status, output JSON.

### Step 5: Test — idea-update changes status (RED → GREEN)
Test: file with 3 entries, run idea-update 2 promoted, assert line 2 updated and checkbox checked.

**Implement:** `cmd_idea_update` — sed replacement on the target line.

### Step 6: Register subcommands in dispatch
Add idea-add, idea-list, idea-count, idea-update to the case statement.

### Step 7: Create `/idea` skill
**File:** `preset/.claude/skills/idea/SKILL.md`

The skill calls `docs-check.sh idea-add` for capture, `idea-list` for listing, and provides the triage logic (Claude reasoning over data from idea-list + roadmap + backlog).

### Step 8: Create `/idea triage` skill variant
Triage reads ideas, roadmap, and backlog. Presents recommendations. Updates statuses on approval. This is the judgment layer.

### Step 9: Update /init to copy roadmap template
**File:** `global-commands/init.md`

Add roadmap.md to the docs setup step (skip if exists).

### Step 10: Update /catchup to report idea count
**File:** `preset/.claude/commands/catchup.md`

Add step: run `docs-check.sh idea-count`, report untriaged count if > 0.

### Step 11: Update docs-check.sh recommend
When untriaged idea count > 3, include "Triage ideas" as a recommended action.

### Step 12: Run full suite, verify 394+ green

### Step 13: Commit
```
feat(ideas): add idea capture, roadmap template, and triage skill
```
