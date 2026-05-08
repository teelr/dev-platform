# shell/

Shell helpers, aliases, functions, and git-hook templates that support the dev-platform workflow outside Claude Code itself.

**What goes here:** `*.sh` files sourced from the user's `.bashrc` / `.zshrc` (e.g., `aliases.sh`, `git-helpers.sh`, `cd-into-dev.sh`), git hook templates (`git-hooks/pre-commit`, `git-hooks/commit-msg`) that projects can opt into, and any cross-shell utilities the workflow depends on.

**What does NOT go here:** Claude Code hook scripts (those go in `hooks/`); per-project shell helpers (those belong in the project's `scripts/` directory); secrets or machine-specific paths (use a sourced `*.local.sh` overlay instead, gitignored).

**Deployment:** `scripts/install.sh` symlinks shell helpers into `~/.shell-platform/` (or similar) and prints the line to add to `.bashrc` / `.zshrc` if it isn't already sourcing the directory. Git hook templates are opted into per-project via `git config core.hooksPath`.
