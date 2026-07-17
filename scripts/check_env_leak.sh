#!/usr/bin/env bash
# scripts/check_env_leak.sh — detect the "app API key leaks into Claude Code"
# footgun across every project.
#
# Incident: a project's .env holds ANTHROPIC_API_KEY for the APP's own
# Anthropic API usage (unrelated to Claude Code). VSCode's
# python.terminal.useEnvFile (or an explicit terminal.integrated.env.*
# mapping) injects that .env into every integrated terminal in the workspace,
# including the one Claude Code's native binary launches from. Claude Code
# then auto-detects ANTHROPIC_API_KEY in its process environment and, once
# approved, silently switches its OWN billing from the Claude subscription to
# pay-per-token API billing against the app's (often near-empty) key.
#
# /etc/claude-code/managed-settings.json (forceLoginMethod: "claudeai",
# deployed by `install.sh managed`) is the hard backstop that makes this
# harmless machine-wide. This script catches the leak itself so it gets fixed
# at the source per-project instead of relying solely on the backstop.
#
# Scope: read-only audit across projects/*. Does NOT modify any project file
# (per dev-platform's own rule — cross-project writes happen in that
# project's own session, not here).
#
# Exit code:
#   0 — no leak pattern found in any project
#   1 — at least one project has the leak pattern
#
# Usage:
#   ./scripts/check_env_leak.sh                # scan all projects
#   ./scripts/check_env_leak.sh <project-name>  # scan just one

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_DIR="${REPO}/projects"
FILTER="${1:-}"
ERRORS=0
CHECKED=0

# Anthropic env var names that must never end up in a shell terminal
# environment shared with Claude Code.
LEAK_VARS='ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN'

check_project() {
    local proj_dir="$1"
    local proj_name
    proj_name="$(basename "${proj_dir}")"
    local vscode_settings="${proj_dir}/.vscode/settings.json"
    [[ -f "${vscode_settings}" ]] || return 0
    CHECKED=$((CHECKED + 1))

    # Vector 1: python.terminal.useEnvFile injects an .env file into every
    # integrated terminal in the workspace.
    local use_env_file
    use_env_file="$(python3 -c "
import json, sys
try:
    d = json.load(open('${vscode_settings}'))
except Exception:
    sys.exit(0)
print(d.get('python.terminal.useEnvFile', ''))
" 2>/dev/null)"

    if [[ "${use_env_file}" == "True" ]]; then
        local env_file_setting
        env_file_setting="$(python3 -c "
import json
d = json.load(open('${vscode_settings}'))
print(d.get('python.envFile', '\${workspaceFolder}/.env'))
" 2>/dev/null)"
        local resolved_env_file="${env_file_setting/\$\{workspaceFolder\}/${proj_dir}}"
        if [[ -f "${resolved_env_file}" ]] && grep -qE "^\s*(export\s+)?(${LEAK_VARS})=" "${resolved_env_file}"; then
            echo "  X ${proj_name}: python.terminal.useEnvFile=true injects ${resolved_env_file#${proj_dir}/} (contains Anthropic key) into every terminal"
            ERRORS=$((ERRORS + 1))
            return 0
        fi
    fi

    # Vector 2: terminal.integrated.env.* directly sets an Anthropic var.
    if grep -qE "\"(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN)\"" "${vscode_settings}" 2>/dev/null \
        && grep -q "terminal.integrated.env" "${vscode_settings}" 2>/dev/null; then
        echo "  X ${proj_name}: terminal.integrated.env.* sets an Anthropic var directly"
        ERRORS=$((ERRORS + 1))
        return 0
    fi

    echo "  OK ${proj_name}"
}

echo "Checking for app-API-key -> Claude Code leak (python.terminal.useEnvFile / terminal.integrated.env)..."
if [[ -n "${FILTER}" ]]; then
    if [[ ! -d "${PROJECTS_DIR}/${FILTER}" ]]; then
        echo "  X no such project: ${FILTER}" >&2
        exit 1
    fi
    check_project "${PROJECTS_DIR}/${FILTER}"
else
    for d in "${PROJECTS_DIR}"/*/; do
        [[ -d "${d}" ]] || continue
        check_project "${d%/}"
    done
fi

echo ""
if [[ ${ERRORS} -gt 0 ]]; then
    echo "Found ${ERRORS} project(s) with the leak pattern (${CHECKED} project(s) have .vscode/settings.json)."
    echo "Fix in that project's own session: stop injecting the Anthropic key into the terminal env —"
    echo "move it to a secrets file the app loads directly, or set python.terminal.useEnvFile to false."
    echo "The machine-wide backstop (/etc/claude-code/managed-settings.json) still protects Claude Code"
    echo "billing either way, but the leak itself should be fixed at the source."
    exit 1
fi
echo "Clean — no project injects an Anthropic key into its terminal environment (${CHECKED} project(s) checked)."
