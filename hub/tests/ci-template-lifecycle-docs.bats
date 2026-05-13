#!/usr/bin/env bats
# BTS-482 — drift-guard for the hub-shipped CI workflow template.
#
# The lifecycle-docs job in .ccanvil/templates/github/workflows/ci.yml must
# fire on PR events ONLY when the PR is non-draft. Drafts represent
# in-flight feature branches whose docs/spec.md + docs/plan.md + docs/stasis.md
# are present BY DESIGN (only removed at /pr pr-cleanup). Without the
# draft-guard, the job fails on every implementation push and floods the
# operator with false-positive CI failure emails.

bats_require_minimum_version 1.5.0

CI_YML="$BATS_TEST_DIRNAME/../../.ccanvil/templates/github/workflows/ci.yml"

@test "AC-1: CI template file exists" {
  [ -f "$CI_YML" ]
}

@test "AC-1: lifecycle-docs job is declared in the template" {
  grep -qE '^[[:space:]]*lifecycle-docs:' "$CI_YML"
}

@test "AC-1: lifecycle-docs if-condition skips draft PRs" {
  # The job's if: condition must include the draft-guard. The full expression
  # is: github.event_name == 'pull_request' && github.event.pull_request.draft == false
  # Use grep on the substring so whitespace/quoting variations don't trip us.
  grep -qF "github.event.pull_request.draft == false" "$CI_YML"
}

@test "AC-1: lifecycle-docs if-condition still gates on pull_request event" {
  grep -qF "github.event_name == 'pull_request'" "$CI_YML"
}

@test "AC-2: workflow on: block still triggers on pull_request (regression)" {
  # The pull_request trigger entry must remain — we are NOT removing the
  # event subscription, only adding a draft filter to the lifecycle-docs job.
  grep -qE '^[[:space:]]*pull_request:' "$CI_YML"
}

@test "AC-2: lifecycle-docs preserves the cleanup-required error message (regression)" {
  # The job's intent is unchanged: when stale lifecycle docs reach a ready
  # PR, surface the same actionable error. Only the gating condition changes.
  grep -qF 'Lifecycle docs must be cleaned up before merge' "$CI_YML"
}

@test "AC-1: pull_request trigger includes ready_for_review activity type" {
  # BTS-482: default pull_request activity types (opened/synchronize/reopened)
  # exclude the draft→ready conversion. Without ready_for_review, lifecycle-docs
  # never fires on that transition — defeats the gate's intent. The trigger
  # must opt into the additional type explicitly.
  grep -qF 'ready_for_review' "$CI_YML"
  grep -qE '^[[:space:]]+types:[[:space:]]+\[' "$CI_YML"
}
