# Ideas

- [ ] 2026-04-09: Mature the feature lifecycle: branch creation should move to pre-spec (post-idea), and the PR/merge/land tail should be clearly documented as distinct steps. Currently activate creates branches but it happens after spec writing. The full chain should be: idea → branch → spec → plan → implement → complete → merge → land, with each transition point clearly defined. <!-- status:new -->
- [ ] 2026-04-10: Bug: /init in new downstream node projects doesn't register the project with the hub. Need to diagnose and resolve. <!-- status:new -->
- [ ] 2026-04-10: ideas.md timestamps use date format — should use epoch (unix timestamp) for consistency with spec/plan/checkpoint metadata <!-- status:new -->
- [ ] 2026-04-10: Addendum to previous: ideas.md should lead with epoch timestamp but also include a human-readable date/time <!-- status:new -->
- [ ] 2026-04-10: Ideas should have a UID; feedback on a previous idea should update that entry instead of creating a new one <!-- status:new -->
- [ ] 2026-04-10: Bug: init-apply jq error 'Cannot index object with number' at init-plan.json:78 during new project init (taxes). Likely jq array vs object indexing issue in cmd_init_apply. <!-- status:new -->
- [ ] 2026-04-10: Addendum to init-apply bug: root cause is init-preflight outputs {plan:[...], summary:{...}} but init-apply expects a bare array. Workaround: jq '.plan' to extract. Fix: init-apply should handle the wrapper object, or both commands should agree on format. <!-- status:new -->
- [ ] 2026-04-10: Bug: /init doesn't create a .gitignore for new projects and doesn't register the project with the hub. Init should always create a default .gitignore and run registration. <!-- status:new -->
- [ ] 2026-04-10: Evaluate whether checkpoint is still needed given /compact, /catchup, and auto-memory. Original purpose: retain context/decisions/insights before clearing. May be redundant now — or may need to evolve into something more targeted (e.g., decision log, session summary for auto-memory). Determine if it should become a /checkpoint skill, merge into another mechanism, or be retired. <!-- status:new -->
