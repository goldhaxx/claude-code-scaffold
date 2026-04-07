# How To Use ccanvil

You've run `/init`, named your project, and the preset is in place. Now what?

---

## The Short Version

Talk to Claude Code like you'd talk to a competent developer you just hired. Describe what you want the software to do. Claude Code handles the technical decisions — what framework to use, how to structure the code, which libraries to pull in. The preset enforces the discipline: every feature gets a spec, every spec gets tests, every test gets verified.

You don't need to learn special syntax. You don't need to make technical decisions upfront. Just describe outcomes.

---

## Your First Feature

Open Claude Code in your project directory and describe what you want:

```
"I want a CLI tool that takes a CSV file and outputs a summary
of the data — row count, column names, and basic stats for
numeric columns."
```

That's it. Here's what happens next:

**Claude Code writes a specification.** It creates `docs/spec.md` with acceptance criteria — concrete, binary pass/fail statements like "When given a CSV with 3 numeric columns, the output includes mean, median, and min/max for each." It asks you to review.

**You review and adjust.** Read the acceptance criteria. If something is wrong or missing, say so in plain language:

```
"Add a criterion for handling empty CSV files gracefully.
Also, I want it to detect and skip non-numeric columns automatically."
```

Claude Code updates the spec.

**When the spec looks right, say:**

```
/plan
```

Claude Code reads the spec and creates `docs/plan.md` — an ordered list of implementation steps, each sized for one test-driven cycle. It does NOT start coding yet.

**Review the plan. When it looks right, say:**

```
"Start building."
```

Claude Code enters the TDD cycle. For each step in the plan:
1. Writes a failing test
2. Runs it to confirm the failure
3. Writes the minimum code to pass
4. Runs the full test suite
5. Refactors if needed
6. Commits

You can watch, intervene, or let it run. If something looks wrong, say so. If it's going well, let it work.

---

## How Technical Decisions Get Made

Your CLAUDE.md starts with the tech stack as "TBD." That's intentional. When Claude Code starts building your first feature, it will need to make technical choices — which language, which test framework, which libraries. It makes those decisions based on what the feature needs, then updates CLAUDE.md with what it chose.

If you have preferences, state them anytime:

```
"Use Python for this project."
"I prefer Vitest over Jest."
"Let's use SQLite for storage."
```

If you don't have preferences, Claude Code picks sensible defaults and tells you what it chose. The CLAUDE.md evolves as the project grows — you'll see the Tech Stack, Commands, and Architecture sections fill in over the first few features.

---

## The Rhythm of a Session

A session has one objective. You state it, work toward it, and when it's done (or you need to stop), you checkpoint and clear. Here's what that looks like:

### Starting fresh
```
claude
"I want to add PDF export to the report generator."
```

### Picking up where you left off
```
claude
/catchup
```

Claude Code reads `docs/checkpoint.md` and recent git history, then tells you where things stand and what's next. It does NOT start working — it orients and reports. When you're ready:

```
"Continue."
```

### Taking a break mid-feature
Just say:
```
"Checkpoint this and stop."
```

Claude Code writes progress, current state, and next steps to `docs/checkpoint.md`, commits any uncommitted work, and tells you it's ready for `/clear`.

```
/clear
```

This resets context. Your progress is safe in git and the checkpoint file.

### Switching to something urgent
```
"I need to pause this and fix a bug — the login page
throws a 500 error when the session cookie is expired."
```

Claude Code checkpoints the current work, and you start fresh on the bug:
```
/clear
"Fix the login 500 error when the session cookie is expired."
```

---

## When To Use Commands vs. Natural Language

Most of the time, natural language is all you need. The preset's rules and agents activate automatically based on what you're doing. But there are four slash commands worth knowing:

| You type | What happens | When to use it |
|---|---|---|
| `/plan` | Creates an ordered implementation plan from the current spec | After you've reviewed and approved `docs/spec.md` |
| `/review` | Spawns a sub-agent to review all uncommitted changes | Before committing significant work — catches issues in a fresh context |
| `/catchup` | Reads checkpoint + git state, reports where things stand | After a `/clear` or when starting a new session on an existing project |
| `/clear` | Resets the context window (built-in) | Between tasks, when switching focus, or when a session feels degraded |

You don't need to type `/spec` — just describe what you want and Claude Code will spec it. You don't need to type `/tdd` — the preset's rules enforce the test-first workflow automatically. You don't need to type `/commit` — Claude Code commits after each passing TDD cycle.

---

## What You're Responsible For

You are the product owner. Your job is to:

**Describe what the software should do.** Not how — what. "Users should be able to reset their password via email" not "Create a POST endpoint at /api/reset-password that generates a JWT token and sends it via SendGrid."

**Review specs and plans before building starts.** This is the highest-leverage moment. A bad acceptance criterion produces bad code that passes bad tests. Spend your attention here.

**Review Claude Code's work periodically.** Let it run the TDD cycle, but glance at what it's producing. If it's heading in a direction you don't like, say so early.

**Make judgment calls when asked.** Claude Code will occasionally surface decisions that require your input — tradeoffs between approaches, UX choices, or cases where the spec is ambiguous. Answer these and it keeps building.

**Say when something is done.** Claude Code doesn't know your definition of "good enough." When a feature meets the acceptance criteria and you're satisfied, say so and move on.

---

## What Claude Code Is Responsible For

Claude Code is the engineer. Its job is to:

**Choose and configure the tech stack** based on what the project needs, updating CLAUDE.md as decisions are made.

**Write specifications** with testable acceptance criteria when you describe a feature.

**Plan implementation** in ordered steps, each sized for one TDD cycle.

**Write tests first, then implementation** following the red-green-refactor cycle.

**Commit frequently** with conventional commit messages after each passing cycle.

**Manage its own context** by checkpointing progress, using sub-agents for research, and staying within the preset's rules.

**Update CLAUDE.md** as the project evolves — new commands, architecture changes, conventions that emerge from development.

---

## Common Scenarios

### "I have a vague idea"

```
"I want to build something that helps me track my reading list
and reminds me to finish books I started."
```

Claude Code will ask clarifying questions to narrow the scope, then write a spec. You don't need to have it all figured out.

### "I found a bug"

```
"There's a bug — when I upload a file larger than 10MB,
the app hangs instead of showing an error."
```

Claude Code treats bugs the same as features: spec the expected behavior, write a failing test that reproduces the bug, fix it, verify the test passes.

### "I want to change how something works"

```
"The search results page currently shows 50 results at once.
I want it to paginate with 10 results per page."
```

Claude Code updates the spec, writes tests for the new behavior, modifies the implementation, and verifies nothing else broke.

### "I don't like the technical direction"

```
"I don't want to use SQLite anymore. Let's switch to PostgreSQL."
```

Claude Code will plan the migration, update affected tests, modify the implementation, and update CLAUDE.md to reflect the new stack.

### "This session feels slow or confused"

```
"Checkpoint this."
/clear
/catchup
"Continue."
```

Fresh context fixes most issues. ccanvil is designed for short, focused sessions — not marathon coding.

---

## The Lifecycle of a Feature

```
 ┌─────────────────────────────────────────────────────┐
 │                                                     │
 │   1. DESCRIBE   "I want the app to do X"            │
 │        │                                            │
 │        ▼                                            │
 │   2. SPEC       Claude writes docs/spec.md          │
 │        │        You review acceptance criteria       │
 │        ▼                                            │
 │   3. PLAN       /plan → Claude writes docs/plan.md  │
 │        │        You review the ordered steps         │
 │        ▼                                            │
 │   4. BUILD      Claude executes TDD cycles:         │
 │        │        test → implement → verify → commit   │
 │        │        (repeat for each plan step)          │
 │        ▼                                            │
 │   5. REVIEW     /review → sub-agent checks work     │
 │        │                                            │
 │        ▼                                            │
 │   6. DONE       Move to next feature or stop        │
 │                                                     │
 └─────────────────────────────────────────────────────┘

 Between features: /clear to reset context
 Between sessions: "checkpoint" → /clear → /catchup to resume
```

---

## Things That Will Feel Unusual

**You barely touch code.** That's the point. You describe outcomes, review specs, and make judgment calls. Claude Code writes the code, tests, and commits.

**The CLAUDE.md fills in over time.** It starts mostly empty and grows as technical decisions are made. This is by design — decisions are deferred until there's enough context to make them well.

**You `/clear` a lot.** Short focused sessions produce better results than long degraded ones. If you're clearing context 5–10 times in a day, you're doing it right.

**Specs feel like overhead at first.** They're not. A 5-minute spec review prevents 30 minutes of building the wrong thing. This is where your attention has the highest return.

**Claude Code commits more often than you would.** Every passing TDD cycle gets a commit. This gives you fine-grained rollback points. Squash later if you prefer cleaner history.
