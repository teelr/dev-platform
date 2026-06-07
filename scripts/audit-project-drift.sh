#!/usr/bin/env bash
# scripts/audit-project-drift.sh — read-only cross-project drift report.
#
# Checks each enabled project in the registry for:
#   (1) chain_drift  — old workflow chain in CLAUDE.md
#   (2) taxonomy_drift — killed-term headers in ROADMAP.md / planning.md
#   (3) has_claude_md — CLAUDE.md presence
#
# Read-only. Makes NO changes. Exit 0 always — this is a reporter, not a gate.
# Use scripts/migrate-workflow-chain.sh --apply to fix chain drift.
#
# Usage:
#   ./scripts/audit-project-drift.sh
#   ./scripts/audit-project-drift.sh --project <name>
#   ./scripts/audit-project-drift.sh --registry <path>
#   ./scripts/audit-project-drift.sh --json
#   ./scripts/audit-project-drift.sh --help

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO_ROOT}/monitoring/projects.json"
TAXONOMY_CHECK="${REPO_ROOT}/scripts/check_spec_taxonomy.sh"
SINGLE_PROJECT=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --project requires an argument" >&2; exit 2; }
            SINGLE_PROJECT="$1"
            ;;
        --registry)
            shift
            [[ $# -eq 0 ]] && { echo "ERROR: --registry requires an argument" >&2; exit 2; }
            REGISTRY="$1"
            ;;
        --json)
            JSON_OUT=1
            ;;
        --help|-h)
            cat <<'HELP'
scripts/audit-project-drift.sh — read-only cross-project drift report.

Checks each enabled project for:
  (1) Old workflow chain in CLAUDE.md (chain_drift)
  (2) Taxonomy violations in ROADMAP.md / planning.md (taxonomy_drift)
  (3) Missing CLAUDE.md (has_claude_md)

Read-only. Exit 0 always — this is a reporter, not a gate.
Use scripts/migrate-workflow-chain.sh --apply to fix chain drift.

Options:
  --project <name>    Only audit the named project.
  --registry <path>   Override registry path (for tests).
  --json              Emit JSON array instead of markdown table.
  --help, -h          Show this help.
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

# Load projects. If --project is set, filter to that one entry.
if [[ -n "${SINGLE_PROJECT}" ]]; then
    projects="$(jq -c --arg n "${SINGLE_PROJECT}" '[.[] | select(.name == $n and .enabled == true)]' "${REGISTRY}")"
    count="$(echo "${projects}" | jq 'length')"
    if [[ "${count}" -eq 0 ]]; then
        echo "ERROR: project '${SINGLE_PROJECT}' not found or not enabled in registry" >&2
        exit 2
    fi
else
    projects="$(jq -c '[.[] | select(.enabled == true)]' "${REGISTRY}")"
fi

today="$(date '+%Y-%m-%d')"

# Per-project audit function. Writes one result line to stdout as JSON.
audit_project() {
    local name="$1"
    local path="$2"

    # Resolve absolute path.
    local abs_path
    if [[ "${path}" == /* ]]; then
        abs_path="${path}"
    else
        abs_path="${REPO_ROOT}/${path}"
    fi

    local claude_md="${abs_path}/CLAUDE.md"

    # Check 1: CLAUDE.md presence.
    local has_claude_md
    if [[ -f "${claude_md}" ]]; then
        has_claude_md="YES"
    else
        has_claude_md="NO"
    fi

    # Check 2: chain drift in CLAUDE.md.
    local chain_status
    if [[ "${has_claude_md}" == "NO" ]]; then
        chain_status="NO_CLAUDE_MD"
    elif grep -qE "/code → /test →|/test → /review|/code → /gate fast" "${claude_md}" 2>/dev/null; then
        chain_status="DRIFT"
    else
        chain_status="CLEAN"
    fi

    # Check 3: taxonomy drift in tasks/ spec files.
    local taxonomy_status
    if [[ -f "${TAXONOMY_CHECK}" ]]; then
        if (cd "${abs_path}" && bash "${TAXONOMY_CHECK}" >/dev/null 2>&1); then
            taxonomy_status="CLEAN"
        else
            taxonomy_status="DRIFT"
        fi
    else
        taxonomy_status="SKIP"
    fi

    jq -n \
        --arg name "${name}" \
        --arg has_claude_md "${has_claude_md}" \
        --arg chain "${chain_status}" \
        --arg taxonomy "${taxonomy_status}" \
        '{name: $name, has_claude_md: $has_claude_md, chain: $chain, taxonomy: $taxonomy}'
}

# Run audit for each project.
results="[]"
while IFS= read -r entry; do
    name="$(echo "${entry}" | jq -r '.name')"
    path="$(echo "${entry}" | jq -r '.path')"
    row="$(audit_project "${name}" "${path}")"
    results="$(echo "${results}" | jq --argjson row "${row}" '. + [$row]')"
done < <(echo "${projects}" | jq -c '.[]')

# Output.
if [[ ${JSON_OUT} -eq 1 ]]; then
    echo "${results}" | jq '.'
    exit 0
fi

# Markdown table output.
echo "# Project Drift Audit — ${today}"
echo ""
echo "| Project | CLAUDE.md | Chain | Taxonomy |"
echo "| ------- | --------- | ----- | -------- |"

drift_count=0
while IFS= read -r row; do
    name="$(echo "${row}" | jq -r '.name')"
    has="$(echo "${row}" | jq -r '.has_claude_md')"
    chain="$(echo "${row}" | jq -r '.chain')"
    taxonomy="$(echo "${row}" | jq -r '.taxonomy')"
    echo "| ${name} | ${has} | ${chain} | ${taxonomy} |"
    if [[ "${chain}" == "DRIFT" || "${taxonomy}" == "DRIFT" || "${has}" == "NO" ]]; then
        (( drift_count++ )) || true
    fi
done < <(echo "${results}" | jq -c '.[]')

echo ""
if [[ ${drift_count} -eq 0 ]]; then
    echo "All projects clean."
else
    echo "Drift found in ${drift_count} project(s)."
    echo "  Chain drift: run \`./scripts/migrate-workflow-chain.sh --project <name> --apply\` to fix."
fi
