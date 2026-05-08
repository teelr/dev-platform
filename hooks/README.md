# hooks/

Shell scripts invoked by Claude Code hooks (PreToolUse, PostToolUse, UserPromptSubmit, Stop, etc.). Each hook is a portable shell script — no language complexity, no per-machine paths.

**What goes here:** `*.sh` hook scripts named for the event they handle (e.g., `pre-tool-use-bash.sh`, `user-prompt-submit-redaction.sh`), plus per-hook `*.md` documentation explaining the hook's contract (input event shape, exit codes, side effects).

**What does NOT go here:** hook *configuration* (which event maps to which script) — that lives in `settings/settings.json` under the `hooks` key. Project-specific hooks (those go in the project's own `.claude/settings.json`).

**Deployment:** hooks are referenced by absolute path from `settings/settings.json`. `scripts/install.sh` rewrites those paths on deploy so they point at the symlinked location under `~/.claude/`. Hooks should be `chmod +x` before commit.
