#!/usr/bin/env bash
# scripts/verify.sh — report drift between tracked and deployed state.
#
# Walks every tracked file in commands/, skills/, settings/, hooks/ and
# verifies the corresponding ~/.claude/ path is a symlink pointing back into
# this repo.
#
# Exit code:
#   0 — all tracked files deployed correctly
#   1 — at least one missing, drifted, or orphan deployment

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_CLAUDE="${HOME}/.claude"
ERRORS=0

check_symlink() {
    local tracked="$1"
    local deployed="$2"
    if [[ ! -e "${deployed}" && ! -L "${deployed}" ]]; then
        echo "  X NOT deployed: ${deployed}"
        ERRORS=$((ERRORS + 1))
    elif [[ ! -L "${deployed}" ]]; then
        echo "  ! drift (real file): ${deployed} (run install.sh to fix, but BACK UP first)"
        ERRORS=$((ERRORS + 1))
    elif [[ "$(readlink -f "${deployed}")" != "${tracked}" ]]; then
        echo "  ! orphan symlink: ${deployed} -> $(readlink "${deployed}")"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK ${deployed}"
    fi
}

echo "Verifying commands..."
for f in "${REPO}/commands"/*.md; do
    [[ -e "${f}" ]] || continue
    name="$(basename "${f}")"
    [[ "${name}" == "README.md" ]] && continue
    check_symlink "${f}" "${HOME_CLAUDE}/commands/${name}"
done

echo "Verifying skills..."
for f in "${REPO}/skills"/*.md; do
    [[ -e "${f}" ]] || continue
    name="$(basename "${f}")"
    [[ "${name}" == "README.md" ]] && continue
    check_symlink "${f}" "${HOME_CLAUDE}/skills/${name}"
done
for d in "${REPO}/skills"/*/; do
    [[ -d "${d}" ]] || continue
    [[ -f "${d}/SKILL.md" ]] || continue
    name="$(basename "${d}")"
    check_symlink "${d%/}" "${HOME_CLAUDE}/skills/${name}"
done

echo "Verifying settings..."
check_symlink "${REPO}/settings/settings.json" "${HOME_CLAUDE}/settings.json"
if [[ -f "${REPO}/settings/keybindings.json" ]]; then
    check_symlink "${REPO}/settings/keybindings.json" "${HOME_CLAUDE}/keybindings.json"
fi
if [[ -f "${REPO}/settings/settings.local.json" ]]; then
    check_symlink "${REPO}/settings/settings.local.json" "${HOME_CLAUDE}/settings.local.json"
fi

echo "Verifying hooks..."
for f in "${REPO}/hooks"/*.sh; do
    [[ -e "${f}" ]] || continue
    check_symlink "${f}" "${HOME_CLAUDE}/hooks/$(basename "${f}")"
done

echo ""
if [[ ${ERRORS} -gt 0 ]]; then
    echo "Verification FAILED: ${ERRORS} issue(s)."
    exit 1
fi
echo "All tracked files deployed correctly."
