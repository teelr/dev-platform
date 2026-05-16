#!/usr/bin/env bash
# scripts/verify-remotes.sh — verify each owned project's git origin and
# per-repo identity against monitoring/remotes.json.
#
# Exit code:
#   0 — all reachable projects match expected config
#   1 — at least one mismatch detected
#
# Usage: ./scripts/verify-remotes.sh [--project <name>] [--registry <path>]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO}/monitoring/remotes.json"
FILTER=""
ERRORS=0

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            echo "Usage: verify-remotes.sh [--project <name>] [--registry <path>]"
            echo "Verifies git origin and identity for every owned project in monitoring/remotes.json."
            exit 0
            ;;
        --project) FILTER="$2"; shift 2 ;;
        --registry) REGISTRY="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# Parse registry and iterate. Python3 inline emits TSV: name\tpath\tremote_url\tlocal_email_or_NONE
while IFS=$'\t' read -r name rel_path remote_url local_email; do
    # Filter to single project if requested
    [[ -n "${FILTER}" && "${name}" != "${FILTER}" ]] && continue

    # Resolve path: absolute paths pass through; relative paths anchor to $REPO
    if [[ "${rel_path}" == "." ]]; then
        abs_path="${REPO}"
    elif [[ "${rel_path}" == /* ]]; then
        abs_path="${rel_path}"
    else
        abs_path="${REPO}/${rel_path}"
    fi

    # SKIP if path does not exist
    if [[ ! -d "${abs_path}" ]]; then
        echo "  SKIP  ${name}: path not found (${abs_path})"
        continue
    fi

    # SKIP if not a git repo
    if ! git -C "${abs_path}" rev-parse --git-dir >/dev/null 2>&1; then
        echo "  SKIP  ${name}: not a git repository"
        continue
    fi

    ok=1

    # Check 1: origin URL
    actual_url="$(git -C "${abs_path}" remote get-url origin 2>/dev/null || echo "")"
    if [[ "${actual_url}" != "${remote_url}" ]]; then
        echo "  X     ${name}: origin mismatch"
        echo "          expected: ${remote_url}"
        echo "          got:      ${actual_url}"
        ERRORS=$((ERRORS + 1))
        ok=0
    fi

    # Check 2: per-repo identity
    actual_email="$(git -C "${abs_path}" config --local user.email 2>/dev/null || echo "")"
    if [[ "${local_email}" == "NONE" ]]; then
        # Expect no per-repo override
        if [[ -n "${actual_email}" ]]; then
            echo "  X     ${name}: unexpected per-repo user.email (${actual_email}); should inherit global"
            ERRORS=$((ERRORS + 1))
            ok=0
        fi
    else
        # Expect a specific per-repo override
        if [[ "${actual_email}" != "${local_email}" ]]; then
            echo "  X     ${name}: user.email mismatch"
            echo "          expected: ${local_email}"
            echo "          got:      ${actual_email:-'(not set)'}"
            ERRORS=$((ERRORS + 1))
            ok=0
        fi
    fi

    [[ ${ok} -eq 1 ]] && echo "  OK    ${name}"

done < <(python3 - "${REGISTRY}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for p in data:
    local_email = p.get("local_email") or "NONE"
    print(p["name"], p["path"], p["remote_url"], local_email, sep="\t")
PY
)

echo ""
if [[ ${ERRORS} -gt 0 ]]; then
    echo "Remote verification FAILED: ${ERRORS} issue(s)."
    exit 1
fi
echo "All remotes verified."
