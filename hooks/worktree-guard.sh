#!/usr/bin/env bash
# SessionStart — warns once, at session start, when a session is sitting in a
# worktree-mode project's shared main checkout on a non-default branch instead
# of an isolated worktree. This is failure mode 1 from
# https://github.com/teelr/dev-platform/issues/120: a session's branch
# checkout, uncommitted files, or git reset/checkout in the shared checkout
# affects every other session sitting there too.
# scripts/check-concurrent-sessions.sh already detects this, but only when a
# human remembers to run /dev; this fires automatically for every session.
#
# Advisory only — never blocks. SessionStart cannot refuse a session anyway,
# and a hard block would also catch the legitimate case: CLAUDE.md's
# Trivial-Edit / Quick-fix carve-out commits straight to `main` in the shared
# checkout with no branch at all, and must never warn. Only "worktree mode is
# ON, this is NOT a worktree, and the branch is NOT the default branch"
# warrants a flag.
#
# Known gap, not silently unhandled: this only catches the state a session
# STARTS in. A session that starts on `main` and later runs `git checkout -b`
# by hand mid-session (bypassing /plan's worktree flow) is not re-checked —
# SessionStart fires exactly once. See tasks/cross-session-collision-guardrails-spec.md.
#
# Fleet-wide assumption, verified against monitoring/projects.json (no
# project in the registry declares a default branch at all, let alone a
# non-`main` one): "not main and not master" is treated as "not the default
# branch" fleet-wide, matching every other dev-platform script's assumption.

set -uo pipefail   # NOT -e — never let a git failure crash the hook

# Silent, not a warning: not a git repo, or git isn't on PATH.
REPO_ROOT="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Already isolated — EnterWorktree creates worktrees under
# <main-checkout>/.claude/worktrees/.
case "${REPO_ROOT}" in
    */.claude/worktrees/*) exit 0 ;;
esac

# Project hasn't opted into worktree mode — nothing to flag.
[ -f "${REPO_ROOT}/.claude/worktree-deps" ] || exit 0

BRANCH="$(git -C "${REPO_ROOT}" branch --show-current 2>/dev/null)" || exit 0
case "${BRANCH}" in
    main|master|"") exit 0 ;;   # empty = detached HEAD, not this hook's concern
esac

PROJECT="$(basename "${REPO_ROOT}")"
MSG="This session is in ${PROJECT}'s shared main checkout on branch '${BRANCH}', not an isolated worktree. ${PROJECT} is worktree-mode: other sessions here share this same working tree, so a git checkout/reset or uncommitted edit in this session affects them too. Run /plan (or EnterWorktree) to move this work into its own worktree, or confirm with the user that working directly in the shared checkout is intentional (e.g. a Trivial Edit)."

python3 -c 'import json,sys; print(json.dumps({"continue": True, "suppressOutput": False, "systemMessage": sys.argv[1]}))' "${MSG}"

exit 0
