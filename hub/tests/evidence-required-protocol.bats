#!/usr/bin/env bats
# BTS-201 — drift-guards for the capture-time evidence requirement.
#
# These tests assert structural properties across the rule file, the three
# skill files (/idea, /stasis, /recall), and the stasis template — guarding
# against regression of the "evidence, not suspicions" protocol that closes
# the failure mode that produced BTS-198.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
RULE="$REPO_ROOT/.claude/rules/evidence-required-for-captures.md"
IDEA_SKILL="$REPO_ROOT/.claude/skills/idea/SKILL.md"
STASIS_SKILL="$REPO_ROOT/.claude/skills/stasis/SKILL.md"
RECALL_SKILL="$REPO_ROOT/.claude/skills/recall/SKILL.md"
STASIS_TPL="$REPO_ROOT/.ccanvil/templates/stasis.md"

# =========================================================================
# AC-1, AC-2: rule file
# =========================================================================

@test "AC-1: rule file exists" {
  [ -f "$RULE" ]
}

@test "AC-2: rule documents the four evidence anchors" {
  set -e
  grep -qF 'Command:' "$RULE"
  grep -qF 'Output:' "$RULE"
  grep -qF 'Exit:' "$RULE"
  grep -qF 'Reproduce:' "$RULE"
}

@test "AC-2: rule documents DIAGNOSE: vs FIX: titling convention" {
  set -e
  grep -qF 'DIAGNOSE:' "$RULE"
  grep -qF 'FIX:' "$RULE"
}

@test "AC-2: rule documents the four anchor names by label" {
  set -e
  grep -qE 'exact command' "$RULE"
  grep -qE 'exit code' "$RULE"
  grep -qE 'reproducer' "$RULE"
}

@test "AC-2: rule is anchored on BTS-198 (origin incident) and BTS-201 (this ship)" {
  set -e
  grep -qF 'BTS-198' "$RULE"
  grep -qF 'BTS-201' "$RULE"
}

# =========================================================================
# AC-3, AC-4: /idea skill — Step 0.5 evidence gate
# =========================================================================

@test "AC-3: /idea SKILL.md contains the bug-shape heuristic regex" {
  # Anchor on the regex shape — alternation across the documented terms.
  grep -qF "fail|false[- ]positive|broken|errored?|blocked by|doesn'?t work|crashes?|hang(s|ing)?" "$IDEA_SKILL"
}

@test "AC-3: /idea SKILL.md describes Step 0.5 evidence gate" {
  set -e
  # Section header — Step 0.5 anchored deterministically.
  grep -qE '^### Step 0\.5' "$IDEA_SKILL"
  # Refusal flow + DIAGNOSE: alternative explicitly named.
  grep -qF 'DIAGNOSE:' "$IDEA_SKILL"
}

@test "AC-4: /idea SKILL.md documents the four evidence anchors" {
  set -e
  # All four anchors must appear in the skill body so the agent can
  # identify them programmatically when scanning capture text.
  grep -qF 'Command:' "$IDEA_SKILL"
  grep -qF 'Output:' "$IDEA_SKILL"
  grep -qF 'Exit:' "$IDEA_SKILL"
  grep -qF 'Reproduce:' "$IDEA_SKILL"
}

@test "AC-1: /idea SKILL.md references evidence-required-for-captures rule" {
  grep -qF 'evidence-required-for-captures' "$IDEA_SKILL"
}

# =========================================================================
# AC-5, AC-6: /stasis skill wires the scan + writes ## Evidence Gaps
# =========================================================================

@test "AC-5: /stasis SKILL.md invokes evidence-scan-session" {
  grep -qF 'evidence-scan-session' "$STASIS_SKILL"
}

@test "AC-6: /stasis SKILL.md references the ## Evidence Gaps section" {
  grep -qF '## Evidence Gaps' "$STASIS_SKILL"
}

@test "AC-6: /stasis SKILL.md documents the empty-state literal" {
  grep -qF 'No evidence gaps this session.' "$STASIS_SKILL"
}

@test "AC-1: /stasis SKILL.md references evidence-required-for-captures rule" {
  grep -qF 'evidence-required-for-captures' "$STASIS_SKILL"
}

# =========================================================================
# AC-6: stasis template carries the empty-state literal
# =========================================================================

@test "AC-6: stasis template includes ## Evidence Gaps heading" {
  grep -qF '## Evidence Gaps' "$STASIS_TPL"
}

@test "AC-6: stasis template includes the empty-state literal" {
  grep -qF 'No evidence gaps this session.' "$STASIS_TPL"
}

# =========================================================================
# AC-7: /recall surfaces carried-forward gaps
# =========================================================================

@test "AC-7: /recall SKILL.md reads ## Evidence Gaps from prior stasis" {
  grep -qF '## Evidence Gaps' "$RECALL_SKILL"
}

@test "AC-7: /recall SKILL.md uses the surface heading literal" {
  grep -qF '**Evidence Gaps from prior session:**' "$RECALL_SKILL"
}

@test "AC-7: /recall SKILL.md silently omits when empty-state literal matches" {
  # Anchor on the empty-state phrase so the recall skill parses it.
  grep -qF 'No evidence gaps this session.' "$RECALL_SKILL"
}

@test "AC-1: /recall SKILL.md references evidence-required-for-captures rule" {
  grep -qF 'evidence-required-for-captures' "$RECALL_SKILL"
}
