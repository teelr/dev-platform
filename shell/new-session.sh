#!/usr/bin/env bash
# shell/new-session.sh — one command to start a concurrent Claude Code CLI
# session on its own git worktree + named tmux window, so two sessions on
# the same project never share a working tree or a tab name.
#
# Usage: new-session.sh <project-dir> <branch-name> [window-name]
#   project-dir   path to the project's repo (or any worktree of it)
#   branch-name   branch to create/checkout for the new worktree
#   window-name   tmux window label (default: last path segment of branch-name)

set -uo pipefail

PROJECT_DIR="${1:?usage: new-session.sh <project-dir> <branch-name> [window-name]}"
BRANCH="${2:?usage: new-session.sh <project-dir> <branch-name> [window-name]}"
WINDOW_NAME="${3:-${BRANCH##*/}}"

REPO_ROOT="$(git -C "${PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "[new-session] not a git repo: ${PROJECT_DIR}" >&2; exit 1; }

SLUG="${BRANCH//\//-}"
WT_DIR="${REPO_ROOT}-${SLUG}"
SESSION="$(basename "${REPO_ROOT}")"

if [[ -d "${WT_DIR}" ]]; then
    echo "[new-session] worktree already exists, reusing: ${WT_DIR}"
elif git -C "${REPO_ROOT}" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git -C "${REPO_ROOT}" worktree add "${WT_DIR}" "${BRANCH}"
else
    git -C "${REPO_ROOT}" worktree add "${WT_DIR}" -b "${BRANCH}"
fi

if ! tmux has-session -t "${SESSION}" 2>/dev/null; then
    tmux new-session -d -s "${SESSION}" -n "${WINDOW_NAME}" -c "${WT_DIR}"
else
    tmux new-window -t "${SESSION}" -n "${WINDOW_NAME}" -c "${WT_DIR}"
fi

tmux send-keys -t "${SESSION}:${WINDOW_NAME}" "claude" Enter

echo "[new-session] worktree: ${WT_DIR}"
echo "[new-session] tmux window: ${SESSION}:${WINDOW_NAME}"

if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "${SESSION}:${WINDOW_NAME}"
else
    tmux attach -t "${SESSION}:${WINDOW_NAME}"
fi
