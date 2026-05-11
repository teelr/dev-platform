#!/usr/bin/env bash
# scripts/sync-vscode.sh — bidirectional sync between the tracked VSCode
# extensions list and the live VSCode server-side state (~/.vscode-server/).
#
# Modes:
#   capture   Read current `code --list-extensions` and overwrite the tracked
#             file. Run after installing a new extension via VSCode UI.
#   deploy    Read the tracked file and install every extension via
#             `code --install-extension --force`. Idempotent — already-
#             installed extensions are no-ops.
#   diff      Show drift between tracked and currently-installed. Lines
#             prefixed `<` are in tracked-not-installed; `>` are
#             installed-not-tracked. Exit 0 if no drift, 1 if drift.
#
# Usage:
#   ./scripts/sync-vscode.sh                  # default: diff
#   ./scripts/sync-vscode.sh capture
#   ./scripts/sync-vscode.sh deploy
#   ./scripts/sync-vscode.sh diff
#   ./scripts/sync-vscode.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${REPO}/extensions/vscode/server-extensions.json"

# Parse args. Supports a positional mode (capture/deploy/diff) plus an
# optional `--file <path>` override (used by tests/vscode/ to redirect away
# from the live tracked file).
MODE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            shift
            FILE="$1"
            ;;
        --help|-h)
            MODE="--help"
            ;;
        capture|deploy|diff)
            MODE="$1"
            ;;
        *)
            echo "Unknown arg: $1" >&2
            echo "Usage: $0 [capture|deploy|diff] [--file <path>]" >&2
            exit 1
            ;;
    esac
    shift
done
MODE="${MODE:-diff}"

if ! command -v code >/dev/null 2>&1; then
    echo "ERROR: 'code' CLI not on PATH. Run from a VSCode server-side environment." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: 'jq' not on PATH. Install jq to use this script." >&2
    exit 1
fi

# Emit currently-installed extensions, one per line, stripping VSCode's
# "Extensions installed on SSH: <hostname>:" header line. Sorted for stable
# diffs across CLI versions — `code --list-extensions` order is undocumented
# and could change.
current() {
    code --list-extensions 2>&1 | grep -v "^Extensions installed" | sort
}

case "${MODE}" in
    capture)
        mkdir -p "$(dirname "${FILE}")"
        current | jq -R . | jq -s . > "${FILE}"
        n="$(jq length "${FILE}")"
        echo "captured ${n} extensions to ${FILE}"
        ;;
    deploy)
        if [[ ! -f "${FILE}" ]]; then
            echo "ERROR: no tracked list at ${FILE}" >&2
            exit 1
        fi
        n="$(jq length "${FILE}")"
        echo "installing ${n} extensions from ${FILE}..."
        jq -r '.[]' "${FILE}" | while read -r ext; do
            [[ -z "${ext}" ]] && continue
            if ! code --install-extension "${ext}" --force >/dev/null 2>&1; then
                echo "  WARN failed to install ${ext}" >&2
            fi
        done
        echo "deploy complete"
        ;;
    diff)
        if [[ ! -f "${FILE}" ]]; then
            echo "ERROR: no tracked list at ${FILE}" >&2
            exit 1
        fi
        # diff returns non-zero when files differ — capture that as drift
        if diff <(jq -r '.[]' "${FILE}" | sort) <(current | sort); then
            echo "no drift — tracked matches installed"
        else
            echo "" >&2
            echo "DRIFT detected. Use 'capture' to record current state or 'deploy' to install tracked." >&2
            exit 1
        fi
        ;;
    --help|-h)
        cat <<'HELP'
scripts/sync-vscode.sh — bidirectional sync helper for VSCode server-side extensions.

Modes:
  capture   Read current `code --list-extensions` and overwrite the tracked file.
            Run after installing a new extension via VSCode UI.
  deploy    Read the tracked file and install every extension via
            `code --install-extension --force`. Idempotent.
  diff      Show drift between tracked and currently-installed.
            Lines prefixed `<` are tracked-not-installed; `>` are installed-not-tracked.
            Exit 0 if no drift, 1 if drift.

Tracked file: extensions/vscode/server-extensions.json (JSON array of extension IDs)
Override with --file <path> for testability.

Usage:
  ./scripts/sync-vscode.sh                            # default: diff
  ./scripts/sync-vscode.sh capture
  ./scripts/sync-vscode.sh deploy
  ./scripts/sync-vscode.sh diff
  ./scripts/sync-vscode.sh capture --file /tmp/x.json # override path
HELP
        ;;
esac
