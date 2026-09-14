#!/usr/bin/env bash
# tests/worktree-guard/run.sh — regression suite for hooks/worktree-guard.sh.
#
# Sourced contract: uses record_pass/record_fail from tests/helpers/assert.sh;
# never exit-s (the orchestrator owns the exit code). Entirely offline — real
# git fixture repos, no live Claude Code session or hook dispatch involved.
# The hook is invoked directly as a subprocess with PWD set to the fixture,
# mirroring how hooks/pre-tool-use.sh already relies on $PWD rather than
# parsing the hook's stdin JSON.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
HOOK="${REPO}/hooks/worktree-guard.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

TMP="$(mktemp -d /tmp/r3-wtg.XXX)"
trap 'rm -rf "${TMP}"' EXIT

# mkrepo <dir> <branch> — a real git repo with one commit, on <branch>.
mkrepo() {
    local dir="$1" branch="$2"
    mkdir -p "${dir}"
    git -C "${dir}" init -q 2>/dev/null
    git -C "${dir}" config user.email t@t
    git -C "${dir}" config user.name t
    : > "${dir}/README.md"
    git -C "${dir}" add -A >/dev/null 2>&1
    git -C "${dir}" commit -qm init >/dev/null 2>&1
    git -C "${dir}" checkout -qb "${branch}" 2>/dev/null \
        || git -C "${dir}" checkout -q "${branch}" 2>/dev/null
}

run_hook() { ( cd "$1" && bash "${HOOK}" 2>&1 ); }

# case 1: not a git repo -> silent
NOTGIT="${TMP}/notgit"; mkdir -p "${NOTGIT}"
out="$(run_hook "${NOTGIT}")"
[[ -z "${out}" ]] && record_pass "non-git directory: silent" \
    || record_fail "non-git directory: expected silence, got: ${out}"

# case 2: worktree mode OFF, feature branch -> silent
OFF="${TMP}/off"; mkrepo "${OFF}" "v1.0/phase-1-x"
out="$(run_hook "${OFF}")"
[[ -z "${out}" ]] && record_pass "worktree mode off: silent even on a feature branch" \
    || record_fail "worktree mode off: expected silence, got: ${out}"

# case 3: worktree mode ON, on main -> silent
ONMAIN="${TMP}/onmain"; mkrepo "${ONMAIN}" "main"
mkdir -p "${ONMAIN}/.claude"; : > "${ONMAIN}/.claude/worktree-deps"
out="$(run_hook "${ONMAIN}")"
[[ -z "${out}" ]] && record_pass "worktree mode on, on main: silent" \
    || record_fail "worktree mode on, on main: expected silence, got: ${out}"

# case 4: worktree mode ON, feature branch, shared main checkout -> flags
FLAG="${TMP}/flag"; mkrepo "${FLAG}" "v1.9/phase-1-collision"
mkdir -p "${FLAG}/.claude"; : > "${FLAG}/.claude/worktree-deps"
out="$(run_hook "${FLAG}")"
if [[ "${out}" == *"systemMessage"* && "${out}" == *"v1.9/phase-1-collision"* ]]; then
    record_pass "worktree mode on, feature branch, shared checkout: flags with branch name"
else
    record_fail "worktree mode on, feature branch, shared checkout: expected a flag, got: ${out}"
fi
echo "${out}" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
    && record_pass "flag output is valid JSON" \
    || record_fail "flag output is not valid JSON: ${out}"

# case 5: worktree mode ON, feature branch, but INSIDE .claude/worktrees/ -> silent
NESTED="${TMP}/main-checkout/.claude/worktrees/v1.9+phase-1-collision"
mkrepo "${NESTED}" "v1.9/phase-1-collision"
mkdir -p "${NESTED}/.claude"; : > "${NESTED}/.claude/worktree-deps"
out="$(run_hook "${NESTED}")"
[[ -z "${out}" ]] && record_pass "already inside .claude/worktrees/: silent regardless of branch" \
    || record_fail "already inside .claude/worktrees/: expected silence, got: ${out}"

# case 6: worktree mode ON, detached HEAD -> silent
DETACHED="${TMP}/detached"; mkrepo "${DETACHED}" "main"
mkdir -p "${DETACHED}/.claude"; : > "${DETACHED}/.claude/worktree-deps"
COMMIT="$(git -C "${DETACHED}" rev-parse HEAD)"
git -C "${DETACHED}" checkout -q "${COMMIT}" 2>/dev/null
out="$(run_hook "${DETACHED}")"
[[ -z "${out}" ]] && record_pass "detached HEAD: silent" \
    || record_fail "detached HEAD: expected silence, got: ${out}"
