#!/usr/bin/env bash
# scripts/sync-vscode-client.sh — sync helper for client-side VSCode config
# (settings.json, keybindings.json) on the Windows VSCode client machine.
#
# Unlike scripts/sync-vscode.sh (server-side extensions — a JSON array
# dev-platform fully controls), these two files are VSCode's own JSONC
# format (comments allowed) and hand-edited by the user — treated here as
# OPAQUE TEXT (cp / diff -u), never parsed or validated as JSON.
#
# Modes:
#   resolve   Print the detected Windows VSCode User directory and exit.
#             Sanity-check detection before trusting capture/deploy.
#   capture   Copy the live settings.json/keybindings.json into the tracked
#             files. Run after changing VSCode client settings.
#   deploy    Copy the tracked files onto the live path. Creates the User/
#             directory if absent.
#   diff      Unified diff between tracked and live, per file.
#             Exit 0 if no drift, 1 if drift in either file.
#
# Windows detection, in order (see resolve_vscode_user_dir below):
#   1. WSL        — $WSL_DISTRO_NAME set, or /proc/version mentions
#                    "microsoft". Bridges via `cmd.exe /c "echo %APPDATA%"`
#                    + `wslpath -u`.
#   2. Git-Bash /  — $APPDATA set directly (Windows env vars are inherited).
#      MSYS/Cygwin   Uses `cygpath -u` if present, else a naive backslash
#                    substitution fallback (Git-Bash's own coreutils
#                    generally accept a forward-slash drive-letter path
#                    like "C:/Users/..." directly, even without cygpath).
#   3. Neither     — not a Windows client. Exit 1 with a clear message.
#
# UNVERIFIED AGAINST A REAL WINDOWS MACHINE: unit-tested here (tests/vscode-client/)
# against mocked cmd.exe/wslpath/cygpath on Linux, because no Windows machine
# exists in this build environment. Run `resolve` on the real client machine
# after merge before trusting `capture`.
#
# Usage:
#   ./scripts/sync-vscode-client.sh [resolve|capture|deploy|diff] [--dir <path>]
#   ./scripts/sync-vscode-client.sh --help

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_TRACKED="${REPO}/extensions/vscode/client-settings.json"
KEYBINDINGS_TRACKED="${REPO}/extensions/vscode/client-keybindings.json"

DIR_OVERRIDE=""
MODE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            shift
            DIR_OVERRIDE="$1"
            ;;
        --help|-h)
            MODE="--help"
            ;;
        resolve|capture|deploy|diff)
            MODE="$1"
            ;;
        *)
            echo "Unknown arg: $1" >&2
            echo "Usage: $0 [resolve|capture|deploy|diff] [--dir <path>]" >&2
            exit 1
            ;;
    esac
    shift
done
MODE="${MODE:-resolve}"

# Detect the Windows VSCode User config directory. Prints the resolved path
# to stdout and returns 0, or prints nothing and returns 1 if this isn't a
# Windows client environment. --dir short-circuits detection entirely (tests).
resolve_vscode_user_dir() {
    if [[ -n "${DIR_OVERRIDE}" ]]; then
        echo "${DIR_OVERRIDE}"
        return 0
    fi

    # 1. WSL
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        if command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
            local appdata_win
            # `|| true` on both substitutions below: under `set -e`, a bare
            # assignment whose command substitution exits non-zero (e.g.
            # cmd.exe failing, pipefail propagating that through `tr`) would
            # otherwise abort the whole script instead of falling through to
            # the graceful "not a Windows client" return 1 below.
            appdata_win="$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r\n')" || true
            if [[ -n "${appdata_win}" && "${appdata_win}" != "%APPDATA%" ]]; then
                local posix_root
                posix_root="$(wslpath -u "${appdata_win}" 2>/dev/null)" || true
                # Only trust a non-empty translation — a failed/empty wslpath
                # must not fall through to echoing a bare "/Code/User" (a
                # real, if unintended, filesystem-root path).
                if [[ -n "${posix_root}" ]]; then
                    echo "${posix_root}/Code/User"
                    return 0
                fi
            fi
        fi
        return 1
    fi

    # 2. Git-Bash / MSYS / Cygwin
    if [[ -n "${APPDATA:-}" ]]; then
        local posix_root=""
        if command -v cygpath >/dev/null 2>&1; then
            posix_root="$(cygpath -u "${APPDATA}" 2>/dev/null)" || true
        fi
        if [[ -n "${posix_root}" ]]; then
            echo "${posix_root}/Code/User"
        else
            echo "${APPDATA//\\//}/Code/User"
        fi
        return 0
    fi

    return 1
}

not_windows_error() {
    echo "ERROR: could not detect a Windows VSCode client environment (no WSL, no APPDATA)." >&2
    echo "       This script targets the Windows VSCode client machine only." >&2
}

case "${MODE}" in
    resolve)
        if dir="$(resolve_vscode_user_dir)"; then
            echo "${dir}"
        else
            not_windows_error
            exit 1
        fi
        ;;
    capture)
        dir="$(resolve_vscode_user_dir)" || { not_windows_error; exit 1; }
        mkdir -p "$(dirname "${SETTINGS_TRACKED}")"
        captured=0
        if [[ -f "${dir}/settings.json" ]]; then
            cp "${dir}/settings.json" "${SETTINGS_TRACKED}"
            captured=$((captured + 1))
        else
            echo "  WARN ${dir}/settings.json not found — skipping" >&2
        fi
        if [[ -f "${dir}/keybindings.json" ]]; then
            cp "${dir}/keybindings.json" "${KEYBINDINGS_TRACKED}"
            captured=$((captured + 1))
        else
            echo "  WARN ${dir}/keybindings.json not found — skipping" >&2
        fi
        echo "captured ${captured}/2 files from ${dir}"
        ;;
    deploy)
        dir="$(resolve_vscode_user_dir)" || { not_windows_error; exit 1; }
        if [[ ! -f "${SETTINGS_TRACKED}" && ! -f "${KEYBINDINGS_TRACKED}" ]]; then
            echo "ERROR: no tracked client config at ${SETTINGS_TRACKED#${REPO}/} or ${KEYBINDINGS_TRACKED#${REPO}/}" >&2
            echo "       Run '$0 capture' on the client machine first." >&2
            exit 1
        fi
        mkdir -p "${dir}"
        deployed=0
        if [[ -f "${SETTINGS_TRACKED}" ]]; then
            cp "${SETTINGS_TRACKED}" "${dir}/settings.json"
            deployed=$((deployed + 1))
        fi
        if [[ -f "${KEYBINDINGS_TRACKED}" ]]; then
            cp "${KEYBINDINGS_TRACKED}" "${dir}/keybindings.json"
            deployed=$((deployed + 1))
        fi
        echo "deployed ${deployed} file(s) to ${dir}"
        ;;
    diff)
        dir="$(resolve_vscode_user_dir)" || { not_windows_error; exit 1; }
        drift=0
        for pair in "settings.json:${SETTINGS_TRACKED}" "keybindings.json:${KEYBINDINGS_TRACKED}"; do
            name="${pair%%:*}"
            tracked="${pair#*:}"
            live="${dir}/${name}"
            if [[ ! -f "${tracked}" ]]; then
                echo "  ${name}: no tracked file — run '$0 capture' first" >&2
                drift=1
                continue
            fi
            if [[ ! -f "${live}" ]]; then
                echo "  ${name}: no live file at ${live}" >&2
                drift=1
                continue
            fi
            if ! diff -u "${live}" "${tracked}"; then
                drift=1
            fi
        done
        [[ ${drift} -eq 0 ]] && echo "no drift — tracked matches live"
        exit ${drift}
        ;;
    --help|-h)
        cat <<'HELP'
scripts/sync-vscode-client.sh — sync helper for client-side VSCode config
(settings.json, keybindings.json) on the Windows VSCode client machine.

Modes:
  resolve   Print the detected Windows VSCode User directory and exit.
  capture   Copy live settings.json/keybindings.json into the tracked files.
  deploy    Copy the tracked files onto the live path.
  diff      Show drift (unified diff) between tracked and live.

Tracked files:
  extensions/vscode/client-settings.json
  extensions/vscode/client-keybindings.json

Override the detected directory with --dir <path> (used by tests/vscode-client/).

Usage:
  ./scripts/sync-vscode-client.sh resolve
  ./scripts/sync-vscode-client.sh capture
  ./scripts/sync-vscode-client.sh deploy
  ./scripts/sync-vscode-client.sh diff
  ./scripts/sync-vscode-client.sh capture --dir /tmp/fake/Code/User
HELP
        ;;
esac
