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
# `--list-checks` prints what actually ran on the default branch's head as a starting
# point, but confirm the trigger in the workflow before requiring it.
set -euo pipefail

REPO=""
CHECKS="DCO"
DRY=0
LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        REPO="$2"; shift 2 ;;
    --checks)      CHECKS="$2"; shift 2 ;;
    --dry-run)     DRY=1; shift ;;
    --list-checks) LIST=1; shift ;;
    -h|--help)     sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null || { echo "gh CLI is required" >&2; exit 1; }

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi
BRANCH=$(gh api "repos/$REPO" --jq .default_branch)

if [ "$LIST" = 1 ]; then
  echo "checks that ran on $REPO@$BRANCH (confirm each runs on pull_request):"
  sha=$(gh api "repos/$REPO/commits/$BRANCH" --jq .sha)
  gh api "repos/$REPO/commits/$sha/check-runs" --jq '[.check_runs[].name]|unique|.[]' \
    | sed 's/^/  /'
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
  | jq -r '"protected \($ARGS.named.repo)@\($ARGS.named.branch): reviews=\(
      .required_pull_request_reviews.required_approving_review_count
    ) checks=\([.required_status_checks.checks[].context] | join(", "))"' \
      --args --arg repo "$REPO" --arg branch "$BRANCH"

cat <<'NOTE'

Admins are deliberately NOT included, matching the rest of the org — so this gates the
normal path and blocks accidents, but an admin can still merge without an approval. If
this repo needs a hard stop, re-run the PUT with "enforce_admins": true.
NOTE
