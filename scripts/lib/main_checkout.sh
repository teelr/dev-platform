#!/usr/bin/env bash
# scripts/lib/main_checkout.sh — resolve the MAIN checkout's root, from
# anywhere in the repo including a worktree.
#
# Two different roots matter in a worktree-mode repo, and conflating them is
# what this helper exists to stop:
#
#   the script's own repo   — where this script and its sibling files live.
#                             In a worktree that IS the worktree, and that is
#                             correct: those are the files being edited.
#   the main checkout       — where git-ignored, never-copied directories live.
#                             `projects/` is the one that bites: it is ignored
#                             (.gitignore) so it exists ONLY in the main
#                             checkout, and every registry entry's relative
#                             `path` is written against it.
#
# Five fleet scripts derived the first and used it as the second, so from a
# worktree they resolved `projects/<name>` to a path that does not exist and
# reported "not adopted" for every consumer instead of failing (v1.27).
# install.sh and verify.sh hit the same bug in v1.25 and grew this resolution
# inline; per the Derivation Sweep rule in CLAUDE.md the rule now lives here
# once and they source it, rather than one definition plus a helper.
#
# The rule: `git rev-parse --git-common-dir` resolves to `<main>/.git` from a
# worktree and from the main checkout alike, so the main checkout is its
# parent. On any failure — not a git repo, no `git` on PATH — the input is
# returned unchanged, so a tarball checkout keeps working.
#
# Usage (source it, then call):
#     source "${REPO}/scripts/lib/main_checkout.sh"
#     FLEET_ROOT="$(resolve_main_checkout "${REPO}")"
#
# Pass a repo ROOT — a script's own REPO, or a worktree's root. A subdirectory
# is not supported: git may report --git-common-dir as the bare relative `.git`,
# which is resolved against the argument, so only a root resolves correctly.
#
# Source it AFTER any required-tools gate the caller has. REPO is usually built
# with `dirname`, an external command, so under a tools-gate test's emptied PATH
# it comes out empty — and sourcing from an empty path fails first, masking the
# error that gate exists to report. Cost one gate failure in v1.27.
#
# Never exits, never prints to stderr — callers decide what to say.
#
# Four copies of this rule deliberately stay inline rather than sourcing this
# file. Do not "finish the sweep" by pointing them here — each one would break:
#
#   shell/worktree/gate-lock.sh, scripts/check-concurrent-sessions.sh
#       Run from the DEPLOYED ~/.claude/worktree/ path, where scripts/lib/ does
#       not exist.
#   scripts/install.sh, scripts/verify.sh
#       Bootstrap scripts that must run standalone, and tests/worktree-default
#       copies them (with uninstall.sh) into a fixture worktree by themselves to
#       test the working-tree versions. Sourcing a sibling breaks that suite —
#       tried in v1.27, five failures, reverted.
#
# So this file is the single definition for everything that CAN share it: the
# fleet scripts, which all resolve `projects/` and all had the same bug.

# shellcheck shell=bash

resolve_main_checkout() {
    local candidate="$1"
    local common common_abs

    if ! common="$(cd "${candidate}" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"; then
        echo "${candidate}"
        return 0
    fi
    if [[ -z "${common}" ]]; then
        echo "${candidate}"
        return 0
    fi
    # --git-common-dir is relative to the candidate when it prints a bare
    # ".git", absolute from a worktree. Resolving it by cd-ing from the
    # candidate handles both without branching on the shape of the string.
    if ! common_abs="$(cd "${candidate}" && cd "${common}" 2>/dev/null && pwd -P)"; then
        echo "${candidate}"
        return 0
    fi
    dirname "${common_abs}"
}
