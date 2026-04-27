# Hub Operations

Operational notes for agents, schedulers, and automation that run **against the hub** (not distributed to downstream nodes). Anything in this file is hub-operator-only — `/ccanvil-init` and `/ccanvil-pull` do not propagate `hub/` to nodes by design.

## Drift-watchdog (launchd LaunchAgent)

The drift-watchdog is a weekly headless Claude Code session that checks every registered downstream node for hub drift and files Linear tickets when drift is detected. It runs via macOS's native `launchd` (NOT cron, NOT the Claude harness's `/schedule` system).

### Plist location

```
~/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist
```

The plist is local to the operator's machine — it intentionally lives outside the repo. Setup is one-time-per-machine.

### Schedule

Every **Monday at 9:13 AM** local time. The plist `StartCalendarInterval` keys are:

| Key | Value | Meaning |
|---|---|---|
| `Weekday` | `1` | Monday (launchd: Sun=0, Mon=1) |
| `Hour` | `9` | 9 AM local |
| `Minute` | `13` | :13 minutes past |

`RunAtLoad` is `false` — the agent does NOT fire on system boot, only on the calendar trigger.

### Command

```
cd /Users/zacharywright/projects/ccanvil && claude --model claude-opus-4-7 -p "/drift-watchdog" --max-budget-usd 5.00
```

The `--max-budget-usd 5.00` cap prevents runaway cost in the unlikely case the skill enters a loop.

### Logs

Inside the repo, gitignored:

- stdout: `.ccanvil/drift-watchdog.log`
- stderr: `.ccanvil/drift-watchdog.err`

### Output the agent produces

One Linear ticket per drifted downstream node, titled `[drift-watchdog] <node>: <hash>`. Recent examples in the backlog: BTS-191 through BTS-197, all filed by past firings.

### How to inspect

```bash
launchctl list | grep ccanvil                                  # is it loaded?
launchctl print gui/$(id -u)/com.ccanvil.drift-watchdog        # full state, last exit, next trigger
cat ~/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist    # source plist
tail -f .ccanvil/drift-watchdog.log                            # follow stdout
```

### How to disable / re-enable

```bash
launchctl unload ~/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist   # disable
launchctl load   ~/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist   # re-enable
```

### How to recreate (new machine, accidental delete)

The plist below is the canonical source. Save it to `~/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist`, adjust the `PATH` line for the new machine, and `launchctl load` it.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ccanvil.drift-watchdog</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>cd "/Users/zacharywright/projects/ccanvil" &amp;&amp; claude --model claude-opus-4-7 -p "/drift-watchdog" --max-budget-usd 5.00</string>
  </array>
  <key>WorkingDirectory</key>
  <string>/Users/zacharywright/projects/ccanvil</string>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>1</integer>
    <key>Hour</key>
    <integer>9</integer>
    <key>Minute</key>
    <integer>13</integer>
  </dict>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/Users/zacharywright/projects/ccanvil/.ccanvil/drift-watchdog.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/zacharywright/projects/ccanvil/.ccanvil/drift-watchdog.err</string>
</dict>
</plist>
```

The `PATH` shown above is minimal — the live plist on the original machine carries a longer `PATH` with `nvm`, `pyenv`, etc. Only those segments needed to find `claude`, `bash`, `git`, and `jq` are required for the agent itself; the `claude` binary is typically at `/usr/local/bin/claude` or `/opt/homebrew/bin/claude` depending on install method.

Update both `WorkingDirectory` and the `cd` argument to match the actual repo path on the new machine.

## SSOT-Linear routing on this hub (post-BTS-217)

As of 2026-04-27, this hub's `.claude/ccanvil.local.json` carries:

```json
{
  "integrations": {
    "routing": {
      "idea":   "linear",
      "spec":   "linear",
      "plan":   "linear",
      "stasis": "linear"
    }
  }
}
```

Lifecycle docs for new features are written to Linear Documents parented to the linked ticket and archived into `docs/sessions/<epoch>-<feature>-{spec,plan,stasis}.md` at `/pr` time. The local `docs/spec.md`, `docs/plan.md`, `docs/stasis.md` are still produced (they ride the activate commit and are read by every `pr-cleanup` invocation), but they are removed by `pr-cleanup`'s `cmd_complete` and the durable post-merge state lives in Linear + `docs/sessions/`.

**Hub-only.** Routing config lives in `.claude/ccanvil.local.json`, which is gitignored. `/ccanvil-pull` and `broadcast` never propagate the flip — every downstream node opts in independently by editing its own `.claude/ccanvil.local.json`. See `feedback_provider_neutral_schemas` memory for the design rationale.

**Substrate provenance:** BTS-204 (substrate origin) → BTS-213 (route-aware `/spec` + `cmd_activate`) → BTS-214 (archive batch-read) → BTS-216 (RFC 4122 v4 UUID fix). All shipped 2026-04-25 → 2026-04-27. BTS-217 was the operator-decision-only flip + dogfood validation against the live API.

**To revert** (rare — substrate is proven, but the override exists):

```bash
jq 'del(.integrations.routing.spec, .integrations.routing.plan, .integrations.routing.stasis)' \
  .claude/ccanvil.local.json | sponge .claude/ccanvil.local.json
```

`routing.idea = "linear"` stays — it's been live since BTS-115.

## Three scheduling surfaces — easy to confuse

The ccanvil ecosystem has three distinct ways to run code on a schedule. Mixing them up wastes context and produces resurrection mistakes (e.g., recreating a remote routine via in-session `CronCreate` and watching it die at session exit).

| Surface | Persistence | Visible where | Used for |
|---|---|---|---|
| **launchd LaunchAgent** | Survives session, reboot, logout | `launchctl list`, `~/Library/LaunchAgents/` | Recurring headless `claude -p` runs (e.g., drift-watchdog) |
| **`/schedule`** (remote routine) | Persists in Anthropic's cloud across sessions | `RemoteTrigger` action `list`, `claude.ai/code/routines/` | One-shot or recurring soak follow-ups (e.g., BTS-163 drainage check) |
| **In-session `CronCreate`** | Dies on session exit | "Background work running" panel on session exit | Ephemeral polling within a single live session |

The "Background work running" panel that shows on Claude Code exit is **always** the third (in-session `CronCreate`) — never the first two. If you see a routine listed there and want it to outlive the session, it must be migrated to `/schedule` or a launchd plist.
