#!/usr/bin/env bash
# scripts/check-dep-install-needed.sh — after a merge, say when the shared
# node_modules is now out of date.
#
# In a worktree-mode project every worktree symlinks its node_modules back to the
# MAIN checkout (shell/worktree/link-deps.sh, driven by .claude/worktree-deps).
# So a dependency change that merges to main is installed nowhere until someone
# runs the install in the main checkout, and nothing in the workflow says so.
# On kermit-v3 that went unnoticed for a week; the install that finally ran
# replaced Next.js on disk under a running dev server, and every page returned
# 500 until the server was restarted (dev-platform issue #151).
#
# This prints a notice when the commit it is given (default HEAD, the squash
# commit /merge just synced) changed a dependency file beside a dependency
# directory the project links. Prints nothing otherwise.
#
# A dependency directory is a .claude/worktree-deps entry whose last path
# segment is `node_modules`; the dependency files are the ones beside it:
# package.json, package-lock.json, npm-shrinkwrap.json, yarn.lock,
# pnpm-lock.yaml. Nothing is hard-coded per project.
#
# NOTICE ONLY. It never installs, never restarts a server, never writes a file
# and never signals a process. The incident's damage came from an install
# running under a live server, and a restart command is per-project and appears
# in no manifest.
#
# SCOPE: this commit only. Dependency changes that reached main through other
# merges, or through a `git pull` that brought in several commits, are not
# scanned. Detecting a lock file newer than node_modules belongs in each
# project's own gate, not here. Only JavaScript dependency files are detected.
#
# Not wired into gate_fast.sh: it is a report, not a gate check (same call as
# check-concurrent-sessions.sh). Only its test suite, tests/dep-install-notice/,
# is gate-discovered. Called from commands/merge.md Step 6.
#
# The manifest parsing below is a deliberate inline copy of
# shell/worktree/link-deps.sh (strip from `#`, trim, strip trailing `/`, skip
# blanks). The slash stripping matters: `frontend/node_modules/` links as
# `frontend/node_modules` (v1.49, issue #154), so it must be named here too. The
# two stay separate copies because link-deps.sh runs from the deployed
# ~/.claude/worktree/ path, where scripts/lib/ does not exist, so it cannot
# share. link-deps.sh is the source of truth, and tests/dep-install-notice/
# runs both over one manifest so they cannot drift.
# The main-checkout derivation is NOT copied: it comes from
# scripts/lib/main_checkout.sh.
#
# Usage:
#   bash /home/rich/dev/scripts/check-dep-install-needed.sh [commit]
#   bash /home/rich/dev/scripts/check-dep-install-needed.sh --help
#
# Exit codes:
#   0  always, except a usage error. A notice must never fail a merge.
#   2  usage error (unknown option, or more than one argument)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'USAGE'
check-dep-install-needed.sh — did this merge leave the shared node_modules stale?

  check-dep-install-needed.sh [commit]   commit defaults to HEAD
  --help                                 this text

Run from the project's checkout. Prints a notice when the commit changed a
dependency file beside a node_modules the project links in .claude/worktree-deps,
and nothing otherwise. Never installs or restarts anything; always exits 0.
USAGE
}

commit="HEAD"
case $# in
    0) ;;
    1) case "$1" in
           --help|-h) usage; exit 0 ;;
           -*) printf 'check-dep-install-needed: unknown option: %s\n' "$1" >&2
               usage >&2; exit 2 ;;
           *) commit="$1" ;;
       esac ;;
    *) printf 'check-dep-install-needed: expected at most one argument, got %s\n' "$#" >&2
       usage >&2; exit 2 ;;
esac

toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
manifest="${toplevel}/.claude/worktree-deps"
[[ -f "${manifest}" ]] || exit 0

# shellcheck source=lib/main_checkout.sh
if ! source "${SCRIPT_DIR}/lib/main_checkout.sh"; then
    echo "check-dep-install-needed: missing ${SCRIPT_DIR}/lib/main_checkout.sh" >&2
    exit 0
fi
main="$(resolve_main_checkout "${toplevel}")"

# --- dependency directories, from the manifest --------------------------------
dirs=()
while IFS= read -r raw || [[ -n "${raw}" ]]; do
    line="${raw%%#*}"                          # strip trailing comment
    line="${line#"${line%%[![:space:]]*}"}"    # trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"    # trim trailing whitespace
    while [[ "${line}" == */ ]]; do line="${line%/}"; done   # as link-deps.sh does
    [[ -z "${line}" ]] && continue
    case "${line}" in
        node_modules)   dir="." ;;
        */node_modules) dir="${line%/node_modules}" ;;
        *)              continue ;;
    esac
    already=0
    for seen in ${dirs[@]+"${dirs[@]}"}; do
        [[ "${seen}" == "${dir}" ]] && already=1
    done
    [[ "${already}" -eq 1 ]] || dirs+=("${dir}")
done < "${manifest}"
[[ "${#dirs[@]}" -gt 0 ]] || exit 0

# --- files this commit changed -------------------------------------------------
changed=()
while IFS= read -r f; do
    [[ -n "${f}" ]] && changed+=("${f}")
done < <(git diff-tree --no-commit-id --name-only -r --root "${commit}" 2>/dev/null)
[[ "${#changed[@]}" -gt 0 ]] || exit 0

was_changed() {
    local want="$1" f
    for f in "${changed[@]}"; do
        [[ "${f}" == "${want}" ]] && return 0
    done
    return 1
}

dep_files=(package.json package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml)
hit_dirs=()
hit_lines=()
for dir in "${dirs[@]}"; do
    hits=""
    for f in "${dep_files[@]}"; do
        if [[ "${dir}" == "." ]]; then path="${f}"; else path="${dir}/${f}"; fi
        if was_changed "${path}"; then
            hits="${hits:+${hits}, }${f}"
        fi
    done
    [[ -n "${hits}" ]] || continue
    hit_dirs+=("${dir}")
    if [[ "${dir}" == "." ]]; then
        hit_lines+=("  (repo root): ${hits}")
    else
        hit_lines+=("  ${dir}/: ${hits}")
    fi
done
[[ "${#hit_dirs[@]}" -gt 0 ]] || exit 0

# --- the notice ------------------------------------------------------------------
# Lock-file order picks the package manager: npm if package-lock.json or
# npm-shrinkwrap.json exists, else pnpm, else yarn, else npm. (SQRL/server has
# both package-lock.json and yarn.lock; npm wins by this order.)
install_cmd() {
    local target="$1"
    if [[ -e "${target}/package-lock.json" || -e "${target}/npm-shrinkwrap.json" ]]; then
        printf 'npm --prefix %s install' "${target}"
    elif [[ -e "${target}/pnpm-lock.yaml" ]]; then
        printf 'pnpm --dir %s install' "${target}"
    elif [[ -e "${target}/yarn.lock" ]]; then
        printf 'yarn --cwd %s install' "${target}"
    else
        printf 'npm --prefix %s install' "${target}"
    fi
}

p='[dep-notice]'
echo "${p} This merge changed dependency files beside a linked node_modules:"
for l in "${hit_lines[@]}"; do
    echo "${p}${l}"
done
echo "${p} Worktrees share the main checkout's node_modules, so nothing is installed until you run, in the main checkout:"
for dir in "${hit_dirs[@]}"; do
    if [[ "${dir}" == "." ]]; then target="${main}"; else target="${main}/${dir}"; fi
    echo "${p}   $(install_cmd "${target}")"
done
echo "${p} Then restart the dev server. Installing under a running server swaps packages beneath it (kermit-v3, 2026-11-01: Next.js was replaced on disk while the server ran and every page returned 500 until restart)."
exit 0
