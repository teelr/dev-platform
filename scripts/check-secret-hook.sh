#!/usr/bin/env bash
# scripts/check-secret-hook.sh — report which local projects have the shared
# pre-commit hook (the v1.41 secret scan) enabled. READ-ONLY: it never writes to
# any project. It is a report, not a gate, and always exits 0.
#
# Usage:
#   scripts/check-secret-hook.sh [--projects-dir DIR]
#
# Environment:
#   DEVPLATFORM_HOOK  path of the dev-platform hook to compare against (default:
#                     what ~/.claude/git-hooks/pre-commit resolves to). Used by tests.

set -uo pipefail

PROJECTS_DIR="/home/rich/dev/projects"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --projects-dir) PROJECTS_DIR="${2:?--projects-dir needs a path}"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

DEV_HOOK="${DEVPLATFORM_HOOK:-$(readlink -f "${HOME}/.claude/git-hooks/pre-commit" 2>/dev/null)}"
if [[ -z "${DEV_HOOK}" || ! -e "${DEV_HOOK}" ]]; then
    echo "warning: dev-platform hook not found (run scripts/install.sh git-hooks)" >&2
fi

printf '%-24s %-12s %-10s %s\n' PROJECT STATUS GATE HOOKSPATH
enabled=0; total=0
for dir in "${PROJECTS_DIR}"/*/; do
    [[ -d "${dir}" ]] || continue
    name="$(basename "${dir}")"
    git -C "${dir}" rev-parse --git-dir >/dev/null 2>&1 || continue
    total=$(( total + 1 ))

    hook_path="$(git -C "${dir}" rev-parse --git-path hooks/pre-commit 2>/dev/null)"
    [[ "${hook_path}" != /* ]] && hook_path="${dir}${hook_path}"

    status="NOT-ENABLED"
    if [[ -e "${hook_path}" || -L "${hook_path}" ]]; then
        if [[ -n "${DEV_HOOK}" && "$(readlink -f "${hook_path}" 2>/dev/null)" == "${DEV_HOOK}" ]]; then
            status="ENABLED"; enabled=$(( enabled + 1 ))
        else
            status="OTHER-HOOK"
        fi
    fi

    gate="no"; [[ -x "${dir}scripts/gate_fast.sh" ]] && gate="yes"
    hooks_path="$(git -C "${dir}" config --get core.hooksPath 2>/dev/null)"
    printf '%-24s %-12s %-10s %s\n' "${name}" "${status}" "${gate}" "${hooks_path:--}"
done

echo ""
echo "${enabled} of ${total} projects have the secret scan enabled."
echo ""
echo "To enable it in one project, run this yourself inside that project:"
echo "  ln -s ~/.claude/git-hooks/pre-commit .git/hooks/pre-commit"
echo "(A project marked OTHER-HOOK already has its own pre-commit; the link would not replace it.)"
echo "Do not use core.hooksPath for this: it disables the project's other hooks, e.g. pre-push."
echo "Where GATE is 'yes' the hook also runs scripts/gate_fast.sh on every commit; turn that off with:"
echo "  git config devplatform.precommitGate false"
exit 0
