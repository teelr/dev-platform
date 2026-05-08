# commands/

Claude Code slash command definitions. Each `*.md` file defines one slash command: filename `foo.md` becomes `/foo`. The markdown body is the prompt template the command uses.

**What goes here:** workflow commands (`plan.md`, `code.md`, `test.md`, `review.md`, `gate.md`, `docs.md`, `dev.md`, `smoke_test.md`), and any other globally-useful slash commands.

**What does NOT go here:** project-specific commands (those live in the project's own `.claude/commands/`); skills (those go in `skills/`); hook scripts (those go in `hooks/`).

**Deployment:** `scripts/install.sh` symlinks each `*.md` here into `~/.claude/commands/`. Edit the file in this directory; the deployed symlink reads through to it on every Claude Code session.
