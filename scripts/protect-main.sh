#!/usr/bin/env bash
# Apply the org's standard branch protection to a repository's default branch.
#
# GitHub templates copy FILES, not settings — a repo created from this template starts
# with `main` wide open, which is how more than one rossoctl repo ended up merging
# pull requests with nothing required. This script is the step that closes that gap,
# and `README.md`'s bootstrapping section calls it.
#
# The baseline, which matches every protected repo in the org:
#
#   * one approving review before merge
#   * the DCO check, plus whatever checks the repo's own CI runs ON PULL REQUESTS
#   * no force pushes, no branch deletion
#   * admins NOT included — a solo maintainer keeps a break-glass path, and the
#     protection still stops accidents and still gates the normal path
#
# Usage:
#   scripts/protect-main.sh                          # this repo, DCO only
#   scripts/protect-main.sh --checks DCO,lint,test   # also require those contexts
#   scripts/protect-main.sh --repo owner/name        # a different repo
#   scripts/protect-main.sh --dry-run                # print the request, send nothing
#
# **Only require a check that runs on `pull_request`.** A required context that is
# push- or schedule-triggered never reports on a PR, so the PR waits for it forever.
# `--list-checks` prints the contexts seen on the default branch's head AND on the
# newest pull request's head, as a starting point — the branch head alone shows only
# push-triggered checks, so a PR-only context like DCO would be missing from it. Still
# confirm the trigger in the workflow before requiring anything.
set -euo pipefail

REPO=""
CHECKS="DCO"
DRY=0
LIST=0

# --help prints the header comment above, stopping at `set -euo pipefail` so the range
# stays correct however much that comment is edited.
usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d; s/^# \{0,1\}//'
}

need_value() {
  [ $# -ge 2 ] || { echo "$1 requires a value" >&2; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        need_value "$@"; REPO="$2"; shift 2 ;;
    --checks)      need_value "$@"; CHECKS="$2"; shift 2 ;;
    --dry-run)     DRY=1; shift ;;
    --list-checks) LIST=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null || { echo "gh CLI is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi
BRANCH=$(gh api "repos/$REPO" --jq .default_branch)

list_contexts() {
  # Contexts arrive by two different APIs: Actions jobs and app checks (DCO included)
  # are check-runs, while some apps post commit *statuses* instead. Either kind can be
  # required, so list both.
  gh api "repos/$REPO/commits/$1/check-runs" --jq '.check_runs[].name'
  gh api "repos/$REPO/commits/$1/status"     --jq '.statuses[].context'
}

if [ "$LIST" = 1 ]; then
  # The default branch's head only ever shows what runs on PUSH. A PR-only context --
  # DCO being exactly that -- never appears there, so also read the newest pull request's
  # head commit. Listing the union is the point: a context missing from the branch head
  # but present on a PR head is a pull_request-triggered check, which is the only kind
  # that is safe to require.
  echo "checks seen on $REPO (confirm each runs on pull_request before requiring it):"
  {
    list_contexts "$(gh api "repos/$REPO/commits/$BRANCH" --jq .sha)"

    # A brand-new repo has no pull requests yet; that is fine, just skip this half.
    pr_sha=$(gh api "repos/$REPO/pulls?state=all&sort=updated&direction=desc&per_page=1" \
      --jq '.[0].head.sha // empty')
    if [ -n "$pr_sha" ]; then list_contexts "$pr_sha"; fi
  } | sort -u | sed 's/^/  /'
  exit 0
fi

# jq builds the checks array so a context containing a space or slash survives —
# "lint (3.12)" and "verify-pr-title / pr-title-check" are both real in this org.
BODY=$(jq -n --arg checks "$CHECKS" '
  {
    required_status_checks: {
      strict: false,
      checks: ($checks | split(",") | map(select(length > 0) | {context: .}))
    },
    enforce_admins: false,
    required_pull_request_reviews: {
      dismiss_stale_reviews: false,
      require_code_owner_reviews: false,
      required_approving_review_count: 1,
      require_last_push_approval: false
    },
    restrictions: null,
    allow_force_pushes: false,
    allow_deletions: false,
    block_creations: false,
    required_conversation_resolution: false,
    required_linear_history: false,
    lock_branch: false,
    allow_fork_syncing: false
  }')

if [ "$DRY" = 1 ]; then
  echo "would PUT repos/$REPO/branches/$BRANCH/protection:"
  echo "$BODY"
  exit 0
fi

printf '%s' "$BODY" \
  | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - \
  | jq -r --arg repo "$REPO" --arg branch "$BRANCH" \
      '"protected \($repo)@\($branch): reviews=\(
        .required_pull_request_reviews.required_approving_review_count
      ) checks=\([.required_status_checks.checks[].context] | join(", "))"'

cat <<'NOTE'

Admins are deliberately NOT included, matching the rest of the org — so this gates the
normal path and blocks accidents, but an admin can still merge without an approval. If
this repo needs a hard stop, re-run the PUT with "enforce_admins": true.
NOTE
