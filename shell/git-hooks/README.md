# shell/git-hooks/

Git hook templates that any teelr/dev-* repo can opt into. Universal: each hook script no-ops when its preconditions aren't met (e.g., `pre-commit` no-ops when the repo has no `scripts/gate_fast.sh`), so the same files install harmlessly across every repo.

**What goes here:** Git hook scripts named per git's convention — `pre-commit`, `commit-msg`, `pre-push`, `post-commit`, etc. — with NO file extension. Files are executable bash.

**What does NOT go here:** Claude Code hook scripts (those live in `hooks/` and feed into `settings.json` event wiring); per-project bash helpers (those belong in `shell/*.sh` or each project's own `scripts/`); secrets or per-machine config.

**Deployment:** `scripts/install.sh git-hooks` symlinks every file under this directory (except `README.md`) into `~/.claude/git-hooks/`. The category is opt-in — running `install.sh` without arguments installs the symlinks but does NOT auto-activate the hooks in any repo. **Activate per-repo** by running:

```bash
git config core.hooksPath ~/.claude/git-hooks
```

inside the target repo. This is opt-in by design — auto-writing `core.hooksPath` everywhere would surprise users and break workflows.

**Bypass:** Each hook honors a `SKIP_<HOOK>=1` env var override for the rare case where the user genuinely needs to commit broken state (WIP commits on private branches). The override is documented in the hook script header.
