#!/usr/bin/env bash
# scripts/migrate-workflow-chain.sh — rewrite old workflow chain references
# in a project's CLAUDE.md to the current canonical chain.
#
# Per the Scope-rule carve-out in /home/rich/dev/CLAUDE.md (Exception —
# v0.9 migration tooling). Touches ONLY workflow chain line(s) in CLAUDE.md.
# ALL other content in the project's CLAUDE.md is left untouched.
#
# Usage:
#   ./scripts/migrate-workflow-chain.sh --project <name>           # dry-run
#   ./scripts/migrate-workflow-chain.sh --project <name> --apply   # rewrite
#   ./scripts/migrate-workflow-chain.sh --registry <path>          # tests
#   ./scripts/migrate-workflow-chain.sh --help
#
# Exit codes:
#   0 — dry-run completed (or already up-to-date), OR --apply rewrote successfully
#   1 — guard failure (no CLAUDE.md, idempotency check failed, project not found)
#   2 — setup error (jq absent, missing registry, missing args)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO_ROOT}/monitoring/projects.json"

NEW_CHAIN="/plan → /code → /gate fast → commit → push → /pr → CI → /merge → post-merge"

PROJECT=""
APPLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --project requires an argument (project name)" >&2; exit 2; }
            PROJECT="$1"
            ;;
        --apply)
            APPLY=1
            ;;
        --registry)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --registry requires an argument (path to projects.json)" >&2; exit 2; }
            REGISTRY="$1"
            ;;
        --help|-h)
            cat <<'HELP'
scripts/migrate-workflow-chain.sh — rewrite old workflow chain references
in a project's CLAUDE.md to the current canonical chain.

Modes:
  (default)   Dry-run: show diff, write nothing.
  --apply     Actually rewrite the CLAUDE.md.

Options:
  --project <name>    Required. Project name from monitoring/projects.json.
  --registry <path>   Override registry path (for tests).
  --help, -h          Show this help.

Detection: any line containing "/code → /test" or "/test → /review"
is treated as an old-chain reference and rewritten.

The script rewrites EXACTLY the workflow chain line(s) in:
  <project_path>/CLAUDE.md

This is the ONLY mutation v0.9 migration tooling performs against projects/,
governed by the Scope-rule carve-out in /home/rich/dev/CLAUDE.md
("Exception — v0.9 migration tooling"). NO --all flag exists; per-project
opt-in only.
HELP
            exit 0
            ;;
        *)
            echo "ERROR: unknown arg: $1" >&2
            exit 2
            ;;
    esac
    shift
done

command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 2; }
[[ -f "${REGISTRY}" ]] || { echo "ERROR: registry not found at ${REGISTRY}" >&2; exit 2; }
[[ -n "${PROJECT}" ]] || { echo "ERROR: --project <name> is required" >&2; exit 2; }

# Resolve the project from the registry.
match="$(jq --arg n "${PROJECT}" '.[] | select(.name == $n)' "${REGISTRY}")"
if [[ -z "${match}" ]]; then
    echo "ERROR: project '${PROJECT}' not found in registry (${REGISTRY})" >&2
    exit 1
fi

project_path="$(echo "${match}" | jq -r '.path')"

# Compute the CLAUDE.md target path. Absolute or repo-relative.
if [[ "${project_path}" == /* ]]; then
    claude_md="${project_path}/CLAUDE.md"
else
    claude_md="${REPO_ROOT}/${project_path}/CLAUDE.md"
fi

if [[ ! -f "${claude_md}" ]]; then
    echo "ERROR: CLAUDE.md not found at ${claude_md}" >&2
    exit 1
fi

# Check if any old-chain patterns are present.
# Pattern requires trailing " →" after /test to avoid matching carve-out documentation.
if ! grep -qE "/code → /test →|/test → /review" "${claude_md}"; then
    echo "migrate-workflow-chain — project=${PROJECT}"
    echo "  CLAUDE.md: ${claude_md}"
    echo "  Status:    already up-to-date"
    exit 0
fi

# Apply all 6 known old-chain sed rewrites. The NEW_CHAIN string replaces
# only the chain substring — surrounding context (bullet prefixes, etc.) is
# preserved because sed operates on the matching portion, not the whole line.
apply_rewrite() {
    local file="$1"
    # Handle line-wrapped variant (chain split across two lines after /gate).
    # perl -0pe slurps the whole file so \n in the pattern matches real newlines.
    perl -i -0pe \
        "s|/plan → /code → /test → /review → /gate\n→ /docs → commit → push|${NEW_CHAIN}|g" \
        "${file}" 2>/dev/null || true
    sed -i \
        -e "s|/plan → /code → /test → /review → /gate fast → /docs → commit → push → /pr → CI → /merge → post-merge|${NEW_CHAIN}|g" \
        -e "s|/plan → /code → /test → /review → /gate fast → /docs → commit → push|${NEW_CHAIN}|g" \
        -e "s|/plan → /code → /test → /review → /gate fast → commit → push|${NEW_CHAIN}|g" \
        -e "s|/plan → /code → /test → /review → /gate → /docs → commit → push|${NEW_CHAIN}|g" \
        -e "s|/plan → /code → /test → /review → commit|${NEW_CHAIN}|g" \
        -e "s|/plan → /code → /test → /gate → /docs → release|${NEW_CHAIN}|g" \
        "${file}"
}

echo "migrate-workflow-chain — project=${PROJECT}"
echo "  CLAUDE.md: ${claude_md}"
echo "  Mode:      $([[ ${APPLY} -eq 1 ]] && echo "APPLY" || echo "dry-run")"
echo ""

if [[ ${APPLY} -eq 0 ]]; then
    # Dry-run: show what would change without writing.
    tmp="$(mktemp)"
    cp "${claude_md}" "${tmp}"
    apply_rewrite "${tmp}"
    diff -u "${claude_md}" "${tmp}" || true
    rm -f "${tmp}"
    echo ""
    echo "Dry-run — re-run with --apply to rewrite."
else
    # Apply: rewrite in place.
    apply_rewrite "${claude_md}"

    # Idempotency guard: old patterns must be gone after rewrite.
    if grep -qE "/code → /test →|/test → /review" "${claude_md}"; then
        echo "ERROR: sed rewrite incomplete — old chain pattern still present in ${claude_md}" >&2
        echo "       A new chain variant may exist that this script does not cover." >&2
        exit 1
    fi

    echo "Rewrite applied. Old chain patterns removed from ${claude_md}."
    echo "Verify with: grep -n 'gate fast' ${claude_md}"
fi
