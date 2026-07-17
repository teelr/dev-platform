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
#   ./scripts/install.sh vscode
#   ./scripts/install.sh managed    # v1.11 — machine-wide auth pin (sudo)
#   ./scripts/install.sh git-hooks  # v1.2 — opt-in pre-commit hook
#   ./scripts/install.sh worktree   # v1.4 — worktree isolation tooling
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

# Deploy a runtime-writable settings file as a REAL local file, not a symlink
# (v1.6 Local Settings Isolation). Claude Code writes "always allow" grants into
# these files at runtime; a symlink into the repo would push those grants into
# the tracked repo. If the target is currently a symlink (pre-v1.6 cutover),
# capture its resolved content first so no grants are lost, then replace it with
# a real file.
materialize_if_symlink() {
    local target="$1"
    if [[ -L "${target}" ]]; then
        local content
        content="$(cat "${target}" 2>/dev/null || echo "")"
        rm -f "${target}"
        printf '%s' "${content}" > "${target}"
    fi
}

install_settings() {
    require_safe_target "${HOME_CLAUDE}"
    mkdir -p "${HOME_CLAUDE}"

    # claude-global.md + keybindings.json are NOT runtime-writable — keep symlinked.
    link_file "${REPO}/settings/claude-global.md" "${HOME_CLAUDE}/CLAUDE.md"
    local linked="claude-global.md (symlink)"
    if [[ -f "${REPO}/settings/keybindings.json" ]]; then
        link_file "${REPO}/settings/keybindings.json" "${HOME_CLAUDE}/keybindings.json"
        linked="${linked}, keybindings.json (symlink)"
    fi

    # settings.json — merge-deploy as a real file. Cutover any pre-v1.6 symlink to
    # a real file first (preserving its grants), then union the repo baseline in.
    materialize_if_symlink "${HOME_CLAUDE}/settings.json"
    python3 "${REPO}/scripts/merge_settings.py" \
        "${REPO}/settings/settings.json" "${HOME_CLAUDE}/settings.json"
    linked="${linked}, settings.json (merged real file)"

    # settings.local.json — seed once from the tracked .example, then never touch.
    # Cutover any pre-v1.6 symlink to a real file (preserving its local entries).
    materialize_if_symlink "${HOME_CLAUDE}/settings.local.json"
    if [[ ! -e "${HOME_CLAUDE}/settings.local.json" ]]; then
        cp "${REPO}/settings/settings.local.json.example" \
            "${HOME_CLAUDE}/settings.local.json"
        linked="${linked}, settings.local.json (seeded local file)"
    else
        linked="${linked}, settings.local.json (local file, left as-is)"
    fi

    echo "  settings: ${linked}"
}

install_hooks() {
    mkdir -p "${HOME_CLAUDE}/hooks"
    local count=0
    # Hook scripts: shell entry points Claude Code invokes per event.
    for f in "${REPO}/hooks"/*.sh; do
        [[ -e "${f}" ]] || continue
        link_file "${f}" "${HOME_CLAUDE}/hooks/$(basename "${f}")"
        count=$((count + 1))
    done
    # Hook helper modules: Python emitter shared by the .sh wrappers.
    # Added in v0.5 Phase 2 to centralize project_for() + per-event-type logic.
    for f in "${REPO}/hooks"/*.py; do
        [[ -e "${f}" ]] || continue
        link_file "${f}" "${HOME_CLAUDE}/hooks/$(basename "${f}")"
        count=$((count + 1))
    done
    echo "  hooks: ${count} files linked"
}

install_vscode() {
    # VSCode server-side extensions (v0.6). Unlike commands/skills/settings/hooks,
    # this category doesn't symlink files — extensions are installed-package state,
    # not files. install_vscode reads the tracked JSON list and runs
    # `code --install-extension --force` per entry. Idempotent.
    #
    # Error-handling philosophy: PERMISSIVE BY DESIGN. Individual install
    # failures (marketplace network blip, extension renamed/removed, etc.) emit
    # a WARN and the loop continues. Returns 0 even on partial failures so that
    # `install.sh all` doesn't abort because one extension out of 40+ had a
    # transient error. Returns 1 ONLY if EVERY install fails (catastrophic —
    # signals the `code` CLI itself is broken).
    #
    # This differs from `link_file`'s safety-check posture (exit 1 on
    # collision). Different category: link_file protects against data loss;
    # install_vscode handles operational transients. Both philosophies are
    # correct for their domain.
    local file="${REPO}/extensions/vscode/server-extensions.json"
    if [[ ! -f "${file}" ]]; then
        echo "  vscode: no tracked list at ${file#${REPO}/} — skipping"
        return 0
    fi
    if ! command -v code >/dev/null 2>&1; then
        echo "  vscode: 'code' CLI not on PATH — skipping (not a VSCode server-side env)"
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "  vscode: 'jq' not on PATH — skipping (install jq to deploy extensions)"
        return 0
    fi
    local count
    count="$(jq length "${file}")"
    echo "  vscode: installing/verifying ${count} extensions..."

    # Use process substitution (not a pipe) so the failure counter persists
    # outside the read loop — pipe-fed loops run in a subshell that drops vars.
    local attempted=0
    local failed=0
    while read -r ext; do
        [[ -z "${ext}" ]] && continue
        attempted=$((attempted + 1))
        if ! code --install-extension "${ext}" --force >/dev/null 2>&1; then
            failed=$((failed + 1))
            echo "    WARN failed to install ${ext}" >&2
        fi
    done < <(jq -r '.[]' "${file}")

    if [[ ${attempted} -gt 0 && ${failed} -eq ${attempted} ]]; then
        echo "  vscode: ALL ${attempted} extensions failed — likely 'code' CLI broken" >&2
        return 1
    fi
    if [[ ${failed} -gt 0 ]]; then
        echo "  vscode: ${count} extensions processed; ${failed} failed (see WARNs above)"
    else
        echo "  vscode: ${count} extensions installed/verified"
    fi
    return 0
}

install_managed() {
    # v1.11 — machine-wide Claude Code auth pin (forceLoginMethod: "claudeai").
    # Deployed to a system path (/etc/claude-code/), not ~/.claude/, because
    # managed settings must sit outside the user's own unprivileged write
    # access to take precedence over ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN/
    # apiKeyHelper (see settings.md: managed settings "can't be overridden by
    # anything"). Copy-deployed (not symlinked) and root-owned by design;
    # requires sudo. Permissive on failure (no TTY / no sudo access) — same
    # philosophy as install_vscode: this category is orthogonal to the rest,
    # a WARN shouldn't abort `install.sh all`.
    local target_dir="/etc/claude-code"
    local target="${target_dir}/managed-settings.json"
    local source="${REPO}/settings/managed-settings.json"
    if [[ ! -f "${source}" ]]; then
        echo "  managed: no tracked file at ${source#${REPO}/} — skipping"
        return 0
    fi
    if [[ -f "${target}" ]] && cmp -s "${source}" "${target}"; then
        echo "  managed: ${target} already up to date"
        return 0
    fi
    if sudo mkdir -p "${target_dir}" && sudo cp "${source}" "${target}" && sudo chmod 644 "${target}"; then
        echo "  managed: ${target} deployed"
    else
        echo "  managed: WARN failed to deploy ${target} (no sudo/TTY?) — run manually:" >&2
        echo "    sudo mkdir -p ${target_dir} && sudo cp ${source} ${target} && sudo chmod 644 ${target}" >&2
    fi
    return 0
}

install_git_hooks() {
    # v1.2 — universal pre-commit hook (and future git hooks). Symlinks each
    # tracked file under shell/git-hooks/ into ~/.claude/git-hooks/. Opt-in:
    # users activate per-repo via `git config core.hooksPath ~/.claude/git-hooks`.
    # README.md under shell/git-hooks/ is directory documentation, not a hook,
    # so we skip it (same pattern as install_commands / install_skills).
    mkdir -p "${HOME_CLAUDE}/git-hooks"
    local count=0
    for f in "${REPO}/shell/git-hooks"/*; do
        [[ -f "${f}" ]] || continue
        local name; name="$(basename "${f}")"
        [[ "${name}" == "README.md" ]] && continue
        link_file "${f}" "${HOME_CLAUDE}/git-hooks/${name}"
        count=$((count + 1))
    done
    echo "  git-hooks: ${count} files linked to ${HOME_CLAUDE}/git-hooks/"
    echo "             Activate per-repo with:"
    echo "             git config core.hooksPath ${HOME_CLAUDE}/git-hooks"
}

install_worktree() {
    # v1.4 — worktree isolation tooling. Symlinks each tracked file under
    # shell/worktree/ into ~/.claude/worktree/ so /code and project gate
    # scripts can reference them by absolute path. README.md is directory
    # documentation, not a deployable, so we skip it (same pattern as
    # install_commands / install_git_hooks).
    mkdir -p "${HOME_CLAUDE}/worktree"
    local count=0
    for f in "${REPO}/shell/worktree"/*; do
        [[ -f "${f}" ]] || continue
        local name; name="$(basename "${f}")"
        [[ "${name}" == "README.md" ]] && continue
        link_file "${f}" "${HOME_CLAUDE}/worktree/${name}"
        count=$((count + 1))
    done
    echo "  worktree: ${count} files linked to ${HOME_CLAUDE}/worktree/"
}

case "${CATEGORY}" in
    commands)   install_commands ;;
    skills)     install_skills ;;
    settings)   install_settings ;;
    hooks)      install_hooks ;;
    vscode)     install_vscode ;;
    managed)    install_managed ;;
    git-hooks)  install_git_hooks ;;
    worktree)   install_worktree ;;
    all)        install_commands; install_skills; install_settings; install_hooks; install_vscode; install_managed; install_git_hooks; install_worktree ;;
    *)          echo "Unknown category: ${CATEGORY}" >&2
                echo "Usage: $0 [commands|skills|settings|hooks|vscode|managed|git-hooks|worktree|all]" >&2
                exit 1 ;;
esac

echo "Install complete. Restart Claude Code for changes to take effect."
