# settings/

Claude Code global configuration. Tracked here, deployed by `scripts/install.sh` to `~/.claude/`.

## Files

- `settings.json` — global Claude Code settings (hooks, permissions, env vars). The **tracked baseline**. Deployed as a real local file via merge (see Deployment model below), NOT a symlink — because Claude Code writes "always allow" grants into the live file at runtime and a symlink would push those grants into this repo.
- `claude-global.md` — global Claude Code behavior layer, deployed to `~/.claude/CLAUDE.md`. Loads into every Claude Code session, INCLUDING sessions outside `/home/rich/dev/`. Distinct from `/home/rich/dev/CLAUDE.md` which is the workspace dev-standards file (loads only when working under `/home/rich/dev/`). Two-tier model: `claude-global.md` for tool behavior, `dev/CLAUDE.md` for development standards. **Symlinked** (not runtime-writable).
- `keybindings.json` — global keybindings (NOT currently tracked: this machine has never customized keybindings, so the file does not exist in `~/.claude/`. Add it here and re-run install if you customize a key.) **Symlinked** when present.
- `settings.local.json.example` — secret-free seed for the machine-local `~/.claude/settings.local.json`. `install.sh` copies it ONCE if the live file is absent, then never touches it.
- `*.local.json` — gitignored, machine-specific overlays (auth tokens, machine paths). The live `settings/settings.local.json` is local-only; only the `.example` seed is tracked.
- `managed-settings.json` — v1.11: machine-wide Claude Code auth pin (`forceLoginMethod: "claudeai"`). Deployed to `/etc/claude-code/managed-settings.json` (Linux managed-settings path), NOT `~/.claude/` — managed settings sit outside the user's own write access so they take precedence over `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`/`apiKeyHelper`, closing the leak where a project's `.env` (meant for the app's own Anthropic API usage) gets inherited into a terminal and silently switches Claude Code's own billing off the subscription. Copy-deployed (root-owned, requires `sudo`) via `./scripts/install.sh managed`, not symlinked.

## Editing

Edit the baseline in this directory, then run `./scripts/install.sh` (or `./scripts/install.sh settings` to redeploy just this category). For `settings.json`, install **merges** the baseline into the live `~/.claude/settings.json` (it does NOT overwrite — see the Deployment model). The live file's runtime "always allow" grants are preserved; the baseline's curated entries are added.

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

Runtime "always allow" grants now accumulate in the **live** `~/.claude/settings.json` (a real local file), NOT in this tracked baseline — so the repo no longer collects one-off prompt-acceptance junk on its own. Prune the *live* file periodically (`Bash(done)`, `Bash(sudo kill 4011)`, etc.); the `fewer-permission-prompts` skill helps. The tracked baseline only changes when you edit it here on purpose.

## Deployment model (v1.6 Local Settings Isolation)

`scripts/install.sh` deploys this category two ways, by whether Claude Code writes to the file at runtime:

- **Symlinked** (live edits, repo is source of truth): `claude-global.md` → `~/.claude/CLAUDE.md`, and `keybindings.json` when present. Editing `~/.claude/` directly is overwritten on next install — edit here instead.
- **Merge-deployed as a real local file**: `settings.json`. `scripts/merge_settings.py` unions the baseline's `permissions.allow/deny/ask` into the live `~/.claude/settings.json` and overwrites config keys (`hooks`, `model`, …); runtime grants in the live file are preserved. The live file is NOT a symlink, so "always allow" grants never reach this repo. **Limitation:** a union-merge can ADD but not REMOVE a permission — to retract one, edit the live file or add a `deny` rule.
- **Seeded once as a real local file**: `settings.local.json`. Copied from `settings.local.json.example` only if `~/.claude/settings.local.json` is absent; never clobbered (it holds per-machine grants + secrets).

Why settings.json isn't symlinked: Claude Code persists "always allow" grants into the user settings file at runtime. When that file was a symlink into this repo, every grant polluted the tracked repo (the recurring `settings/settings.json` drift). Making it a real local file is the fix. Precedent: `install.sh vscode` already copy-deploys rather than symlinking.
