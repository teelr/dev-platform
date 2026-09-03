#!/usr/bin/env bash
# scripts/verify.sh — report drift between tracked and deployed state.
#
# Walks every tracked file in commands/, skills/, settings/, hooks/,
# shell/git-hooks/, shell/worktree/, and shell/profile.d/ and verifies the
# corresponding ~/.claude/ path is a symlink pointing back into this repo.
#
# Exit code:
#   0 — all tracked files deployed correctly
#   1 — at least one missing, drifted, or orphan deployment

set -uo pipefail

# The live ~/.claude deployment always tracks the MAIN checkout, never a branch:
# install.sh symlinks repo paths, and a worktree path would dangle the moment
# /merge removes that worktree. So verify what main deployed, no matter where
# this script is invoked from. A worktree-derived REPO reports every symlink as
# an "orphan" against a deployment that is actually correct (21 false failures
# in dev-platform, and gate_fast.sh runs this check on every gate).
#
# Same git-common-dir derivation as scripts/check-concurrent-sessions.sh and
# shell/worktree/gate-lock.sh — the common dir is shared by a repo and all its
# worktrees, and may be returned relative, so resolve it before taking the
# parent. Falls back to the script's own location outside a git repo.
#
# Stays INLINE rather than sourcing scripts/lib/main_checkout.sh (v1.27) for the
# same reason install.sh does: tests/worktree-default copies this script into a
# fixture worktree on its own, so a sourced sibling would not be there.
_SELF_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${_SELF_REPO}"
if _common="$(cd "${_SELF_REPO}" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"; then
    if _common_abs="$(cd "${_SELF_REPO}" && cd "${_common}" 2>/dev/null && pwd -P)"; then
        REPO="$(dirname "${_common_abs}")"
    fi
fi

HOME_CLAUDE="${HOME}/.claude"
ERRORS=0

# Only surprising when it differs — say so rather than silently checking a
# different tree than the one the caller is standing in.
if [[ "${REPO}" != "${_SELF_REPO}" ]]; then
    echo "verify: invoked from a worktree — verifying the main checkout's deployment (${REPO})"
    echo ""
fi

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

# v1.6: settings.json is deployed as a REAL local file (runtime grants stay
# local), not a symlink. Verify it exists, is NOT a symlink into the repo (the
# exact regression this guards), and is a superset of the baseline's allow-list.
check_local_settings() {
    local baseline="$1"
    local deployed="$2"
    if [[ ! -e "${deployed}" ]]; then
        echo "  X NOT deployed: ${deployed} (run install.sh)"
        ERRORS=$((ERRORS + 1))
        return
    fi
    if [[ -L "${deployed}" ]]; then
        echo "  ! drift (symlink): ${deployed} must be a REAL local file, not a symlink (run install.sh)"
        ERRORS=$((ERRORS + 1))
        return
    fi
    if python3 -c "
import json, sys
base = json.load(open('${baseline}'))
live = json.load(open('${deployed}'))
b = set(base.get('permissions', {}).get('allow', []))
l = set(live.get('permissions', {}).get('allow', []))
sys.exit(0 if b.issubset(l) else 1)
" 2>/dev/null; then
        echo "  OK ${deployed} (real file, superset of baseline)"
    else
        echo "  ! drift: ${deployed} is missing baseline allow entries (run install.sh)"
        ERRORS=$((ERRORS + 1))
    fi
}

# v1.6: settings.local.json is a purely local file (seed-once). It must never be
# a symlink into the repo, but has no baseline to compare against.
check_local_only() {
    local deployed="$1"
    [[ -e "${deployed}" ]] || return  # absent is fine (seeded on next install)
    if [[ -L "${deployed}" ]]; then
        echo "  ! drift (symlink): ${deployed} must be a REAL local file, not a symlink"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK ${deployed} (local file)"
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
# settings.json is a real merge-deployed local file (v1.6), not a symlink.
check_local_settings "${REPO}/settings/settings.json" "${HOME_CLAUDE}/settings.json"
# claude-global.md + keybindings.json stay symlinked (not runtime-writable).
check_symlink "${REPO}/settings/claude-global.md" "${HOME_CLAUDE}/CLAUDE.md"
if [[ -f "${REPO}/settings/keybindings.json" ]]; then
    check_symlink "${REPO}/settings/keybindings.json" "${HOME_CLAUDE}/keybindings.json"
fi
# settings.local.json is a purely local seed-once file (v1.6).
check_local_only "${HOME_CLAUDE}/settings.local.json"

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

echo "Verifying managed settings..."
# v1.11: /etc/claude-code/managed-settings.json is a system path, copy-deployed
# (not symlinked, root-owned by design) — compare content, not symlink target.
_managed_target="/etc/claude-code/managed-settings.json"
_managed_source="${REPO}/settings/managed-settings.json"
if [[ -f "${_managed_source}" ]]; then
    if [[ ! -f "${_managed_target}" ]]; then
        echo "  X NOT deployed: ${_managed_target} (run: ./scripts/install.sh managed)"
        ERRORS=$((ERRORS + 1))
    elif ! cmp -s "${_managed_source}" "${_managed_target}"; then
        echo "  ! drift: ${_managed_target} does not match tracked baseline (run: ./scripts/install.sh managed)"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK ${_managed_target}"
    fi
fi

echo "Verifying git-hooks..."
for f in "${REPO}/shell/git-hooks"/*; do
    [[ -f "${f}" ]] || continue
    name="$(basename "${f}")"
    [[ "${name}" == "README.md" ]] && continue
    check_symlink "${f}" "${HOME_CLAUDE}/git-hooks/${name}"
done

echo "Verifying worktree..."
for f in "${REPO}/shell/worktree"/*; do
    [[ -f "${f}" ]] || continue
    name="$(basename "${f}")"
    [[ "${name}" == "README.md" ]] && continue
    check_symlink "${f}" "${HOME_CLAUDE}/worktree/${name}"
done

echo "Verifying shell..."
for f in "${REPO}/shell/profile.d"/*.sh; do
    [[ -f "${f}" ]] || continue
    name="$(basename "${f}")"
    check_symlink "${f}" "${HOME_CLAUDE}/profile.d/${name}"
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
