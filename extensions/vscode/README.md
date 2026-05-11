# extensions/vscode/

Server-side VSCode configuration tracked by dev-platform. Shipped in v0.6 (2026-05-11).

## What goes here

- `server-extensions.json` — JSON array of extension IDs (publisher.name format) currently installed on the VSCode Remote-SSH server side. Read by `scripts/install.sh vscode` to reinstall; populated by `scripts/sync-vscode.sh capture`.

## What does NOT go here

- **Client-side VSCode config** (`settings.json`, `keybindings.json`, `snippets/`, theme) — those live on the laptop where the VSCode UI runs, not on this server. Deferred to a future spec (v0.6b or rolled into v0.7).
- **Per-project `.vscode/` extension recommendations** — those belong in each individual project's repo, not in dev-platform.
- **VSCode profile management** (multiple distinct profile sets) — v0.6 covers a single global profile only.
- **Custom statusline scripts** — no custom statusline files exist on the server today; aspirational v0.6b territory.

## Deployment

- `./scripts/install.sh vscode` — reads `server-extensions.json` and runs `code --install-extension <id> --force` for each entry. Idempotent; already-installed extensions are no-ops.
- `./scripts/install.sh all` — also calls `install_vscode` as part of the full deploy.
- Gracefully skips when the `code` CLI is not on PATH (e.g., running install.sh on a machine without VSCode server-side installed).

## Sync helper

`./scripts/sync-vscode.sh [capture|deploy|diff]`:

- `capture` — read current `code --list-extensions` and overwrite `server-extensions.json`. Run after installing a new extension via the VSCode UI.
- `deploy` — read `server-extensions.json` and install every extension via `code --install-extension --force`. Same effect as `install.sh vscode` but standalone (doesn't need full install round-trip).
- `diff` — compare tracked vs currently-installed and show drift. Useful before commit to catch un-captured changes.

## Format

`server-extensions.json` is a JSON array of strings:

```json
[
  "anthropic.claude-code",
  "bierner.markdown-mermaid",
  "ms-python.python",
  ...
]
```

Each entry matches the VSCode extension-ID convention `publisher.name` (lowercase, hyphens allowed).

## Why JSON, not text

A plain text file (one ID per line) would be simpler to read with `xargs`, but JSON keeps the existing `!extensions/**/*.json` gitignore allow-list valid without modification (per the Consumer Audit rule in `dev/CLAUDE.md`). `jq` is universally available; parse with `jq -r '.[]'`.

## Why not symlinked

Unlike `settings/settings.json` or `hooks/*.sh`, this file is **not** symlinked into a deployed location. VSCode doesn't read it at startup. It's read **in-place** by `install.sh` and `sync-vscode.sh` to drive `code --install-extension` calls. Symlinking would add no value and complicate the model.
