# skills/

User-defined Claude Code skill definitions and the cross-cutting workflow reference.

**What goes here:** `WORKFLOW_MANUAL.md` (the canonical reference for the Roadmap Phase → Spec → Spec Phase → Change → Commit taxonomy), and user-authored skills as subdirectories — each `<skill-name>/SKILL.md` plus any supporting files the skill loads at runtime.

**What does NOT go here:** the workflow slash commands (`/plan`, `/code`, `/test`, `/review`, `/gate`, `/docs`, etc.) — those live in `commands/` and Claude Code surfaces them as both `/foo` and as Skill-tool-invocable skills automatically. Plugin-distributed skills (`update-config`, `keybindings-help`, `simplify`, etc.) come from the Claude Code installation, not this repo.

**Deployment:** `scripts/install.sh` symlinks `WORKFLOW_MANUAL.md` and each user-skill subdirectory into `~/.claude/skills/`. A skill subdir without a `SKILL.md` is skipped during install.
