# BTS-118 — shared bats fixture for the "local repo + bare origin + pushed main"
# pattern. Consumed via `load helpers/seed-repo` from any bats file in hub/tests/.
#
# Functions:
#   seed_repo_with_origin [--docs-specs]
#     Creates a local repo with an init commit, a bare origin, and pushes main.
#     Sets REPO and BARE variables in the caller's scope. Pass --docs-specs
#     to also mkdir -p "$REPO/docs/specs" (needed by activate flow tests).

seed_repo_with_origin() {
  local with_docs_specs=0
  for arg in "$@"; do
    case "$arg" in
      --docs-specs) with_docs_specs=1 ;;
    esac
  done

  REPO=$(mktemp -d)
  BARE=$(mktemp -d)

  git -C "$REPO" init -q -b main
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  git -C "$BARE" init --bare -q -b main
  git -C "$REPO" remote add origin "$BARE"
  git -C "$REPO" push -q -u origin main

  if (( with_docs_specs )); then
    mkdir -p "$REPO/docs/specs"
  fi
}
