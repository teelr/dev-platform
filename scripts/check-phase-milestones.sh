#!/usr/bin/env bash
# scripts/check-phase-milestones.sh — flag GitHub milestones left OPEN whose
# attached issues/PRs are ALL closed (a completed-but-not-closed milestone).
#
# This is the mechanical backstop for the standard post-merge Roadmap-Phase-
# completion step (see /home/rich/dev/CLAUDE.md). Every phase, someone must
# close the phase's milestone when its last Change merges; forgetting is the
# recurring drift issue #50 documents. This script catches the leftover.
#
# WHAT IT CATCHES (honest scope): milestones with open_issues == 0 AND
# closed_issues >= 1 — i.e. every issue/PR assigned to the milestone is
# closed, but the milestone itself is still open. Because /pr assigns each PR
# to its milestone, a fully-merged phase lands exactly here.
#
# WHAT IT CANNOT CATCH: a phase whose PRs were NEVER assigned to a milestone
# (closed_issues == 0) — via the API that is indistinguishable from a future
# phase not yet started, so flagging it would fire on every planned-but-unstarted
# milestone. That never-assigned gap is a *behavioral* one, covered by the
# post-merge step + /pr's milestone assignment, not by this detector. Do not
# read a clean result as "every unclosed phase milestone is fine."
#
# NOT wired into gate_fast.sh: it makes gh network calls (same rationale as
# scripts/check-comms-delivery.sh). Only its offline mock-gh test suite
# (tests/phase-milestones/) is gate-discovered.
#
# Usage:
#   ./scripts/check-phase-milestones.sh                    # current repo (from origin)
#   ./scripts/check-phase-milestones.sh --repo OWNER/REPO  # explicit repo
#   ./scripts/check-phase-milestones.sh --json             # JSON array of flagged milestones
#   ./scripts/check-phase-milestones.sh --help
#
# Exit codes:
#   0  clean — no open-but-complete milestones
#   1  one or more flagged milestones found (action needed: close them)
#   2  error — bad args, missing gh/jq, unresolvable repo, or fetch failure
#
# Requires: gh CLI authenticated, jq.

set -uo pipefail

REPO=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --repo requires an argument (owner/repo)" >&2; exit 2; }
            REPO="$1"
            ;;
        --json)
            JSON_OUT=1
            ;;
        --help|-h)
            cat <<'HELP'
scripts/check-phase-milestones.sh — flag milestones left OPEN whose issues/PRs are all closed.

The mechanical backstop for the post-merge Roadmap-Phase-completion step: when a
phase's last Change merges, its GitHub milestone should be closed. This flags any
milestone still open with 0 open issues and >= 1 closed issue.

Usage:
  ./scripts/check-phase-milestones.sh                    Current repo (derived from origin).
  ./scripts/check-phase-milestones.sh --repo OWNER/REPO  Check an explicit repo.
  ./scripts/check-phase-milestones.sh --json             Emit a JSON array of flagged milestones.
  ./scripts/check-phase-milestones.sh --help, -h         Show this help.

Exit: 0 clean, 1 flagged milestone(s) found, 2 error.

Scope: catches open_issues == 0 && closed_issues >= 1. Cannot catch a phase whose
PRs were never assigned to a milestone (closed_issues == 0) — that is covered by
the post-merge step + /pr's milestone assignment, not this detector.
HELP
            exit 0
            ;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

command -v gh >/dev/null || { echo "ERROR: gh CLI required (https://cli.github.com)" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 2; }

# Resolve target repo. Explicit --repo wins; otherwise derive owner/repo from
# the current git checkout's origin (handles git@github.com:owner/repo.git and
# https://github.com/owner/repo.git). Same origin lookup idiom as verify-remotes.sh.
if [[ -z "${REPO}" ]]; then
    origin_url="$(git remote get-url origin 2>/dev/null || echo "")"
    if [[ -z "${origin_url}" ]]; then
        echo "ERROR: no repo given and no git origin found — pass --repo OWNER/REPO" >&2
        exit 2
    fi
    REPO="$(echo "${origin_url}" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
fi

if [[ ! "${REPO}" =~ ^[^/]+/[^/]+$ ]]; then
    echo "ERROR: could not resolve a valid owner/repo (got '${REPO}')" >&2
    exit 2
fi

# Fetch open milestones (array of {number,title,open_issues,closed_issues,html_url}).
# A fetch failure (auth/network) is an ERROR, not "clean".
if ! milestones="$(gh api "repos/${REPO}/milestones?state=open&per_page=100" 2>/dev/null)"; then
    echo "ERROR: failed to fetch milestones for ${REPO} (gh auth/network?)" >&2
    exit 2
fi

# Flag rule: open milestone with every attached issue/PR closed.
flagged="$(echo "${milestones}" | jq '[.[] | select(.open_issues == 0 and .closed_issues >= 1)
    | {number, title, open_issues, closed_issues, html_url}]')"
count="$(echo "${flagged}" | jq 'length')"

if [[ ${JSON_OUT} -eq 1 ]]; then
    echo "${flagged}"
    [[ "${count}" -gt 0 ]] && exit 1 || exit 0
fi

if [[ "${count}" -eq 0 ]]; then
    echo "No open-but-complete milestones in ${REPO}."
    exit 0
fi

echo "Open-but-complete milestone(s) in ${REPO} — close each at phase completion:"
echo ""
while IFS= read -r m; do
    number="$(echo "${m}" | jq -r '.number')"
    title="$(echo "${m}" | jq -r '.title')"
    closed="$(echo "${m}" | jq -r '.closed_issues')"
    url="$(echo "${m}" | jq -r '.html_url')"
    echo "  ⚠ OPEN-BUT-COMPLETE: ${title} (#${number}) — ${closed} closed, 0 open"
    echo "      close it: gh api -X PATCH repos/${REPO}/milestones/${number} -f state=closed"
    echo "      ${url}"
done < <(echo "${flagged}" | jq -c '.[]')

exit 1
