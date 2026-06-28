#!/usr/bin/env bash
# scripts/setup-consumer-labels.sh — create the consumer:* triage labels on
# each upstream dependency repo named in monitoring/comms-consumers.json.
#
# This is a coordination tool, NOT a code change to any dependency repo. It
# calls the GitHub label API (`gh label create`) on the upstream repo; it never
# clones, checks out, or edits a file under projects/. Creating a label is the
# same sanctioned cross-repo channel as `gh issue create` (the inbound comms
# transport) — it writes repo metadata, not repo files.
#
# Dry-run by default — prints the gh commands it would run. Pass --apply to run
# them. `gh label create --force` updates an existing label instead of erroring,
# so --apply is idempotent and safe to re-run.
#
# Usage:
#   ./scripts/setup-consumer-labels.sh                       # dry-run, all repos
#   ./scripts/setup-consumer-labels.sh --apply               # create the labels
#   ./scripts/setup-consumer-labels.sh --repo teelr/kermit-harness
#   ./scripts/setup-consumer-labels.sh --registry <path>     # override (tests)
#   ./scripts/setup-consumer-labels.sh --help
#
# Exit code:
#   0 — dry-run completed, or --apply succeeded for every label
#   1 — at least one `gh label create` failed under --apply
#   2 — gh CLI not available under --apply, or bad flag

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO}/monitoring/comms-consumers.json"
APPLY=0
REPO_FILTER=""
LABEL_COLOR="0e8a16"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            echo "Usage: setup-consumer-labels.sh [--apply] [--repo <owner/repo>] [--registry <path>]"
            echo ""
            echo "Creates the consumer:* triage labels from monitoring/comms-consumers.json"
            echo "on each upstream dependency repo. Dry-run by default; --apply runs gh."
            echo "Idempotent under --apply (uses gh label create --force)."
            exit 0
            ;;
        --apply) APPLY=1; shift ;;
        --repo) REPO_FILTER="$2"; shift 2 ;;
        --registry) REGISTRY="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -f "${REGISTRY}" ]]; then
    echo "ERROR: registry not found at ${REGISTRY}" >&2
    exit 2
fi

# gh is only needed for the actual create. Dry-run prints commands without it.
if [[ ${APPLY} -eq 1 ]] && ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: --apply requires the gh CLI, which is not on PATH." >&2
    exit 2
fi

ERRORS=0
CREATED=0

# Emit one unique (label, upstream_repo) pair per line as TSV. Dedup so two
# consumers sharing an upstream repo don't double-create the same label.
while IFS=$'\t' read -r label upstream_repo; do
    [[ -z "${label}" ]] && continue
    [[ -n "${REPO_FILTER}" && "${upstream_repo}" != "${REPO_FILTER}" ]] && continue

    # consumer:pa -> "pa" for the description.
    consumer="${label#consumer:}"
    description="Ask filed by the ${consumer} consumer"

    if [[ ${APPLY} -eq 1 ]]; then
        if gh label create "${label}" --repo "${upstream_repo}" \
                --color "${LABEL_COLOR}" --description "${description}" --force; then
            echo "  OK    ${label} on ${upstream_repo}"
            CREATED=$((CREATED + 1))
        else
            echo "  X     ${label} on ${upstream_repo}: gh label create failed" >&2
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo "  would: gh label create ${label} --repo ${upstream_repo} --color ${LABEL_COLOR} --description \"${description}\" --force"
    fi
done < <(python3 - "${REGISTRY}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
seen = set()
for entry in data:
    label = entry["label"]
    repo = entry["upstream_repo"]
    key = (label, repo)
    if key in seen:
        continue
    seen.add(key)
    print(label, repo, sep="\t")
PY
)

echo ""
if [[ ${APPLY} -eq 1 ]]; then
    if [[ ${ERRORS} -gt 0 ]]; then
        echo "Label setup FAILED: ${ERRORS} error(s), ${CREATED} created/updated."
        exit 1
    fi
    echo "Label setup complete: ${CREATED} label(s) created/updated."
else
    echo "Dry-run only. Re-run with --apply to create the labels."
fi
