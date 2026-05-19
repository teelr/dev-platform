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
check_symlink "${REPO}/settings/claude-global.md" "${HOME_CLAUDE}/CLAUDE.md"
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
# Hook helper modules (v0.5 Phase 2: _emit_event.py centralizes project_for()
# and per-event-type emission logic shared by the .sh wrappers).
for f in "${REPO}/hooks"/*.py; do
    [[ -e "${f}" ]] || continue
    check_symlink "${f}" "${HOME_CLAUDE}/hooks/$(basename "${f}")"
done

echo "Verifying git-hooks..."
for f in "${REPO}/shell/git-hooks"/*; do
    [[ -f "${f}" ]] || continue
    name="$(basename "${f}")"
    [[ "${name}" == "README.md" ]] && continue
    check_symlink "${f}" "${HOME_CLAUDE}/git-hooks/${name}"
done

echo "Verifying remotes..."
if [[ "${CI:-}" == "true" ]]; then
    echo "  SKIP  remote verify (CI runner)"
else
    _remote_out="$(bash "${REPO}/scripts/verify-remotes.sh" 2>&1)"
    _remote_exit=$?
    echo "${_remote_out}" | sed 's/^/  /'
    if [[ ${_remote_exit} -ne 0 ]]; then
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""
if [[ ${ERRORS} -gt 0 ]]; then
    echo "Verification FAILED: ${ERRORS} issue(s)."
    exit 1
fi
echo "All tracked files deployed correctly."
