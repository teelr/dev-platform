# settings/

Claude Code global configuration. Tracked here, deployed by `scripts/install.sh` to `~/.claude/`.

## Files

- `settings.json` — global Claude Code settings (hooks, permissions, env vars)
- `claude-global.md` — global Claude Code behavior layer, deployed to `~/.claude/CLAUDE.md`. Loads into every Claude Code session, INCLUDING sessions outside `/home/rich/dev/`. Distinct from `/home/rich/dev/CLAUDE.md` which is the workspace dev-standards file (loads only when working under `/home/rich/dev/`). Two-tier model: `claude-global.md` for tool behavior, `dev/CLAUDE.md` for development standards.
- `keybindings.json` — global keybindings (NOT currently tracked: this machine has never customized keybindings, so the file does not exist in `~/.claude/`. Add it here and re-run install if you customize a key.)
- `*.local.json` — gitignored, machine-specific overlays (auth tokens, machine paths)

## Editing

Edit the file in this directory, then run `./scripts/install.sh` (or `./scripts/install.sh settings` to redeploy just this category). Edits to `~/.claude/settings.json` directly will be overwritten on next install — don't edit there.

Editing `claude-global.md` affects Claude Code's behavior in EVERY session. The change takes effect on next session start (Claude Code reads CLAUDE.md once at startup, doesn't re-read mid-session).

## Secrets and machine-local paths

Anything that varies per machine — auth tokens, DB passwords, absolute paths beyond `$HOME` — goes in `settings.local.json` rather than the tracked `settings.json`. Claude Code merges `settings.local.json` into `settings.json` automatically. The `settings/*.local.json` pattern is gitignored at the repo root.

**What goes in the local overlay:**

- DB-password-bearing permission patterns (`Bash(PGPASSWORD=...)` with a literal password)
- Personal API keys / auth tokens
- Permissions tied to a specific PID, port number, or one-off script that's machine-state-dependent

**What stays in tracked `settings.json`:**

- General permission patterns (`Bash(python *)`, `Bash(npm *)`, `Bash(PGPASSWORD=*)` — the wildcard form, not a literal password)
- `/home/rich/*` absolute paths — these are consistent across the user's machines because the repo is always mounted at `/home/rich/dev/`. Claude Code does not expand `$HOME` in permission patterns, so substituting wouldn't work. If a future machine uses a different layout, that machine's overrides go in `settings.local.json`.

**Concrete example (this repo's setup):**

```jsonc
// settings.json (tracked)
"Bash(PGPASSWORD=*)"             // wildcard form — generic shape

// settings.local.json (gitignored)
"Bash(PGPASSWORD=kermit_dev_password psql -U kermit_user ...)"  // literal
```

## Hygiene

Periodically prune `settings.json` of one-off prompt-acceptance entries that accumulate during sessions (`Bash(do echo "=== $hash ===")`, `Bash(done)`, `Bash(sudo kill 4011)` — auto-added permissions for ad-hoc commands that shouldn't have been baked into the allowlist). The `fewer-permission-prompts` skill helps automate this.

**Deployment:** `scripts/install.sh` symlinks `settings.json` (and `keybindings.json` if present) into `~/.claude/`. The `settings.local.json` overlay is symlinked separately when present.
