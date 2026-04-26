#!/usr/bin/env bats
# BTS-168 — gitignore Claude Code's session-local scheduled-task artifacts.
#
# Claude Code's /loop and /schedule features emit ephemeral
# .claude/scheduled_tasks* files. They don't survive /compact and aren't
# committable state — gitignore them so they never appear in /stasis
# snapshots, /pr cleanup checks, or commit drafts.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."

@test "BTS-168 AC-1: .gitignore excludes .claude/scheduled_tasks*" {
  grep -q 'scheduled_tasks' "$REPO_ROOT/.gitignore"
}

# `git status --porcelain` collapses untracked directories (shows `.claude/`
# rather than every nested file), so a directory-form assertion via
# string-search is unreliable. Use `git check-ignore` for the explicit
# "is this path ignored?" check — exit 0 means ignored, exit 1 means not.

@test "BTS-168 AC-2: bare .claude/scheduled_tasks file is ignored (git check-ignore)" {
  set -e
  local repo
  repo=$(mktemp -d)
  cd "$repo"
  git init -q
  cp "$REPO_ROOT/.gitignore" .gitignore
  mkdir -p .claude
  : > .claude/scheduled_tasks
  run git check-ignore .claude/scheduled_tasks
  [ "$status" -eq 0 ]
  rm -rf "$repo"
}

@test "BTS-168 AC-2: .claude/scheduled_tasks directory is ignored (git check-ignore)" {
  set -e
  local repo
  repo=$(mktemp -d)
  cd "$repo"
  git init -q
  cp "$REPO_ROOT/.gitignore" .gitignore
  mkdir -p .claude/scheduled_tasks
  : > .claude/scheduled_tasks/sentinel
  run git check-ignore .claude/scheduled_tasks/sentinel
  [ "$status" -eq 0 ]
  rm -rf "$repo"
}

@test "BTS-168 AC-2: .claude/scheduled_tasks_<variant> shapes are ignored" {
  set -e
  local repo
  repo=$(mktemp -d)
  cd "$repo"
  git init -q
  cp "$REPO_ROOT/.gitignore" .gitignore
  mkdir -p .claude
  : > .claude/scheduled_tasks_foo
  : > .claude/scheduled_tasks_bar.json
  run git check-ignore .claude/scheduled_tasks_foo .claude/scheduled_tasks_bar.json
  [ "$status" -eq 0 ]
  # Both paths should appear in the output (each on its own line).
  [[ "$output" == *scheduled_tasks_foo* ]]
  [[ "$output" == *scheduled_tasks_bar.json* ]]
  rm -rf "$repo"
}
