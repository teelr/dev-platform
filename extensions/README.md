# extensions/

IDE and shell-environment configuration that supports the dev-platform workflow but lives outside `~/.claude/`.

**What goes here:** `vscode/settings.json` and `vscode/keybindings.json` for the global VSCode user profile, statusline scripts (`statusline/*.sh` returning the JSON Claude Code expects), and any other editor-tool config that the workflow depends on.

**What does NOT go here:** per-project `.vscode/` settings (those belong in each project's repo); shell rc files (those live in `shell/`).

**Deployment:** future spec (`dev-platform-extensions-spec.md`, R4 on the roadmap). For now this directory exists as a contract — readers know where editor config will go when it's tracked. `scripts/install.sh` will be extended at that point to deploy `extensions/vscode/*` into the user's VSCode profile dir.
