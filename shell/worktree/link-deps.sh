#!/usr/bin/env bash
# shell/worktree/link-deps.sh — symlink a project's heavy git-ignored paths
# from the main checkout into a fresh worktree, per the project's
# .claude/worktree-deps manifest. Link, never copy. Missing source = warn.
#
# Usage: link-deps.sh <main-checkout-dir> <worktree-dir>
# Deployed to ~/.claude/worktree/link-deps.sh by scripts/install.sh worktree.

set -uo pipefail

MAIN="${1:?usage: link-deps.sh <main-checkout-dir> <worktree-dir>}"
WT="${2:?usage: link-deps.sh <main-checkout-dir> <worktree-dir>}"
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
