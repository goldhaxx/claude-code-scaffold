---
tier: 0
stack: any
anchors: {}
---

# Missing Scope With Leak

Frontmatter present but no `scope:` key. Body references `bats-report.sh`
directly. Per AC-1, missing scope defaults to universal — so the leak-scan
should still fire here.
