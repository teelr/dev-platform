#!/usr/bin/env bash
# scripts/install.sh — deploy dev-platform repo files into the user environment.
#
# Symlinks tracked files from this repo into ~/.claude/ so Claude Code reads
# through to the source of truth. Edits to files in this repo are visible to
# Claude Code immediately on next session start. Editing under ~/.claude/
# directly is overwritten on next install — don't do it.
#
# Usage:
#   ./scripts/install.sh            # install all categories
#   ./scripts/install.sh commands   # install just one category
#   ./scripts/install.sh skills
#   ./scripts/install.sh settings
#   ./scripts/install.sh hooks
#
# Idempotent — running twice produces the same state.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_CLAUDE="${HOME}/.claude"
CATEGORY="${1:-all}"

# Refuse to overwrite a real directory or file with a symlink. The user must
# back up and remove the existing target first; never silently destroy data.
require_safe_target() {
    local target="$1"
    if [[ -e "${target}" && ! -L "${target}" ]]; then
        if [[ -d "${target}" ]]; then
            # A real directory at the target path is fine if we're populating
            # files inside it (e.g., ~/.claude/commands/). The check tightens
            # at the per-file level inside each install_* function.
            return 0
        fi
        echo "ERROR: ${target} is a real file, not a symlink." >&2
        echo "       Back it up and remove it before running install.sh." >&2
        exit 1
    fi
}

# Symlink one file. Refuses if the existing target is a real file.
link_file() {
    local source="$1"
    local target="$2"
    if [[ -e "${target}" && ! -L "${target}" ]]; then
        echo "ERROR: ${target} is a real file (not a symlink)." >&2
        echo "       Back up and remove it, then re-run install.sh." >&2
        exit 1
    fi
    ln -sfn "${source}" "${target}"
}

install_commands() {
    mkdir -p "${HOME_CLAUDE}/commands"
    local count=0
    for f in "${REPO}/commands"/*.md; do
        [[ -e "${f}" ]] || continue
        local name; name="$(basename "${f}")"
        # Skip the directory-contract README — that's repo documentation, not
        # a slash command.
        [[ "${name}" == "README.md" ]] && continue
        link_file "${f}" "${HOME_CLAUDE}/commands/${name}"
        count=$((count + 1))
    done
    echo "  commands: ${count} files linked"
}

install_skills() {
    mkdir -p "${HOME_CLAUDE}/skills"
    local count=0
    # Top-level markdown files (e.g., WORKFLOW_MANUAL.md).
    for f in "${REPO}/skills"/*.md; do
        [[ -e "${f}" ]] || continue
        local name; name="$(basename "${f}")"
        [[ "${name}" == "README.md" ]] && continue
        link_file "${f}" "${HOME_CLAUDE}/skills/${name}"
        count=$((count + 1))
    done
    # User-skill subdirectories — each must contain SKILL.md to be deployed.
    for d in "${REPO}/skills"/*/; do
        [[ -d "${d}" ]] || continue
        local name; name="$(basename "${d}")"
        if [[ -f "${d}/SKILL.md" ]]; then
            link_file "${d%/}" "${HOME_CLAUDE}/skills/${name}"
            count=$((count + 1))
        fi
    done
    echo "  skills: ${count} entries linked"
}

install_settings() {
    require_safe_target "${HOME_CLAUDE}"
    mkdir -p "${HOME_CLAUDE}"
    local linked="settings.json"
    link_file "${REPO}/settings/settings.json" "${HOME_CLAUDE}/settings.json"
    link_file "${REPO}/settings/claude-global.md" "${HOME_CLAUDE}/CLAUDE.md"
    linked="${linked}, claude-global.md"
    if [[ -f "${REPO}/settings/keybindings.json" ]]; then
        link_file "${REPO}/settings/keybindings.json" "${HOME_CLAUDE}/keybindings.json"
        linked="${linked}, keybindings.json"
    fi
    if [[ -f "${REPO}/settings/settings.local.json" ]]; then
        link_file "${REPO}/settings/settings.local.json" "${HOME_CLAUDE}/settings.local.json"
        linked="${linked}, settings.local.json"
    fi
    echo "  settings: linked (${linked})"
}

install_hooks() {
    mkdir -p "${HOME_CLAUDE}/hooks"
    local count=0
    for f in "${REPO}/hooks"/*.sh; do
        [[ -e "${f}" ]] || continue
        link_file "${f}" "${HOME_CLAUDE}/hooks/$(basename "${f}")"
        count=$((count + 1))
    done
    echo "  hooks: ${count} files linked"
}

case "${CATEGORY}" in
    commands)  install_commands ;;
    skills)    install_skills ;;
    settings)  install_settings ;;
    hooks)     install_hooks ;;
    all)       install_commands; install_skills; install_settings; install_hooks ;;
    *)         echo "Unknown category: ${CATEGORY}" >&2
               echo "Usage: $0 [commands|skills|settings|hooks|all]" >&2
               exit 1 ;;
esac

echo "Install complete. Restart Claude Code for changes to take effect."
