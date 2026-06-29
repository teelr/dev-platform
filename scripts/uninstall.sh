#!/usr/bin/env bash
# scripts/uninstall.sh — remove all dev-platform-owned symlinks from the user
# environment. Non-destructive: only removes symlinks pointing into ${REPO};
# real files (user data) and unrelated symlinks are left alone.
#
# After uninstall:
#   - ~/.claude/projects/ (memory, transcripts, session state) untouched
#   - ~/.claude/{commands,skills,CLAUDE.md,keybindings.json} symlinks no longer
#     reference this repo
#   - ~/.claude/settings.json and settings.local.json are REAL local files
#     (v1.6 Local Settings Isolation) holding per-machine grants + secrets — they
#     are NOT symlinks into the repo, so remove_repo_symlinks leaves them in place
#     by design. Deleting them would lose your local "always allow" grants.
#   - User can re-run install.sh to restore (idempotent)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_CLAUDE="${HOME}/.claude"

remove_repo_symlinks() {
    local target_dir="$1"
    [[ -d "${target_dir}" ]] || return 0
    local removed=0
    while IFS= read -r -d '' link; do
        local resolved
        resolved="$(readlink -f "${link}" 2>/dev/null || true)"
        if [[ -n "${resolved}" && "${resolved}" == "${REPO}"* ]]; then
            rm "${link}"
            echo "  removed: ${link}"
            removed=$((removed + 1))
        fi
    done < <(find "${target_dir}" -maxdepth 2 -type l -print0)
    echo "  ${removed} symlink(s) removed under ${target_dir}"
}

remove_repo_symlinks "${HOME_CLAUDE}"
echo "Uninstall complete. ~/.claude/ no longer references ${REPO}."
echo "User-generated state in ${HOME_CLAUDE}/projects/ was not touched."
