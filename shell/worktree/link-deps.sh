#!/usr/bin/env bash
# shell/worktree/link-deps.sh — symlink a project's heavy git-ignored paths
# from the main checkout into a fresh worktree, per the project's
# .claude/worktree-deps manifest. Link, never copy. Missing source = warn.
#
# Usage:
#   link-deps.sh                                    # from inside the worktree
#   link-deps.sh <main-checkout-dir> <worktree-dir> # explicit (tests, fixtures)
#
# THE NO-ARGUMENT FORM IS THE ONE /plan AND /code USE, and it exists for a
# specific reason: a worktree-isolated session's command guard analyses commands
# statically and refuses anything it cannot verify stays inside the worktree.
# Every dynamic element trips it — `"${HOME}"`, `"${MAIN}"`, `"$(pwd)"`,
# `"${PWD}"` alike. So the prescribed invocation
#
#     bash ~/.claude/worktree/link-deps.sh "${MAIN}" "$(pwd)"
#
# was refused outright and the linking step silently never ran. Only a fully
# literal command is accepted, which means the script must derive its own paths.
# Do not "simplify" the commands back to passing arguments — that reintroduces
# the bug, and its symptom is a worktree that looks fine until the app cannot
# start.
#
# Derivation matches the rest of the worktree tooling (scripts/install.sh,
# scripts/verify.sh, check-concurrent-sessions.sh): the worktree is the current
# toplevel, and the main checkout is the parent of the shared git common dir.
#
# Deployed to ~/.claude/worktree/link-deps.sh by scripts/install.sh worktree.

set -uo pipefail

usage() {
    cat <<'USAGE'
link-deps.sh — symlink a project's heavy git-ignored paths into a worktree

  link-deps.sh                                    run from inside the worktree;
                                                  derives both paths itself
  link-deps.sh <main-checkout-dir> <worktree-dir> explicit paths (tests)
  link-deps.sh --help                             this text

Reads <main>/.claude/worktree-deps. Links, never copies. A listed path that does
not exist yet is a warning, not an error.

Exit: 0 linked (or nothing to link), 2 usage/derivation error
USAGE
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac

if [[ $# -eq 2 ]]; then
    MAIN="$1"
    WT="$2"
elif [[ $# -eq 0 ]]; then
    # Derive. Both must come from git, so a non-repo invocation fails loudly
    # rather than linking into some arbitrary directory.
    if ! WT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        echo "[link-deps] not inside a git repository — run from the worktree, or pass both paths explicitly" >&2
        exit 2
    fi
    if ! _common="$(git rev-parse --git-common-dir 2>/dev/null)"; then
        echo "[link-deps] cannot resolve the git common dir — pass both paths explicitly" >&2
        exit 2
    fi
    # The common dir may be returned relative to the current directory.
    if ! _common_abs="$(cd "${_common}" 2>/dev/null && pwd -P)"; then
        echo "[link-deps] cannot resolve ${_common} — pass both paths explicitly" >&2
        exit 2
    fi
    MAIN="$(dirname "${_common_abs}")"
else
    echo "[link-deps] expected 0 or 2 arguments, got $#" >&2
    usage >&2
    exit 2
fi

# Refuse to link a checkout to itself. Without this, running the no-argument
# form from the MAIN checkout (where toplevel and common-dir parent are the same
# path) would do `ln -sfn "${MAIN}/.env" "${MAIN}/.env"` — replacing a real file
# with a symlink to itself. Destructive, and silent until the app cannot read
# its own config.
_main_r="$(cd "${MAIN}" 2>/dev/null && pwd -P || echo "${MAIN}")"
_wt_r="$(cd "${WT}" 2>/dev/null && pwd -P || echo "${WT}")"
if [[ "${_main_r}" == "${_wt_r}" ]]; then
    echo "[link-deps] main checkout and worktree are the same directory (${_main_r})" >&2
    echo "[link-deps] nothing to link — deps only need linking INTO a worktree" >&2
    exit 2
fi

MANIFEST="${MAIN}/.claude/worktree-deps"

[[ -f "${MANIFEST}" ]] || { echo "[link-deps] no manifest at ${MANIFEST} — nothing to link"; exit 0; }

linked=0
missing=0
while IFS= read -r raw || [[ -n "${raw}" ]]; do
    line="${raw%%#*}"                          # strip trailing comment
    line="${line#"${line%%[![:space:]]*}"}"    # trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"    # trim trailing whitespace
    [[ -z "${line}" ]] && continue
    src="${MAIN}/${line}"
    dst="${WT}/${line}"
    if [[ ! -e "${src}" ]]; then
        echo "[link-deps] WARN source missing, skipped: ${line}" >&2
        missing=$((missing + 1))
        continue
    fi
    mkdir -p "$(dirname "${dst}")"
    ln -sfn "${src}" "${dst}"
    echo "[link-deps] linked ${line}"
    linked=$((linked + 1))
done < "${MANIFEST}"

echo "[link-deps] ${linked} linked, ${missing} missing"
exit 0
