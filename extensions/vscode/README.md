# extensions/vscode/

Server-side VSCode configuration tracked by dev-platform. Shipped in v0.6 (2026-05-11).

## What goes here

- `server-extensions.json` — JSON array of extension IDs (publisher.name format) currently installed on the VSCode Remote-SSH server side. Read by `scripts/install.sh vscode` to reinstall; populated by `scripts/sync-vscode.sh capture`.
- `client-settings.json`, `client-keybindings.json` — the Windows VSCode client's `settings.json` / `keybindings.json` (v1.35). **Windows-only** — no Mac/Linux client support exists. Populated by `scripts/sync-vscode-client.sh capture`, run FROM the Windows client machine (not by `/code` — see that script's header for why). Read by `scripts/install.sh vscode-client` to deploy.

## What does NOT go here

- **Mac/Linux client config** — v1.35 shipped Windows-only, per an explicit scope decision (the confirmed client machine is Windows). A Mac (`~/Library/Application Support/Code/User/`) or Linux (`~/.config/Code/User/`) client would need its own detection branch in `scripts/sync-vscode-client.sh` — not built here.
- **Snippets, theme-only tracking, client-side extension list** — out of scope for v1.35; see the spec's "Out of Scope" section if revisiting.
- **Per-project `.vscode/` extension recommendations** — those belong in each individual project's repo, not in dev-platform.
- **VSCode profile management** (multiple distinct profile sets) — v0.6 covers a single global profile only.
- **Custom statusline scripts** — no custom statusline files exist on the server today; aspirational territory.

## Deployment

- `./scripts/install.sh vscode` — reads `server-extensions.json` and runs `code --install-extension <id> --force` for each entry. Idempotent; already-installed extensions are no-ops.
- `./scripts/install.sh all` — also calls `install_vscode` as part of the full deploy.
- Gracefully skips when the `code` CLI is not on PATH (e.g., running install.sh on a machine without VSCode server-side installed).

## Sync helper

`./scripts/sync-vscode.sh [capture|deploy|diff]`:

- `capture` — read current `code --list-extensions` and overwrite `server-extensions.json`. Run after installing a new extension via the VSCode UI.
- `deploy` — read `server-extensions.json` and install every extension via `code --install-extension --force`. Same effect as `install.sh vscode` but standalone (doesn't need full install round-trip).
- `diff` — compare tracked vs currently-installed and show drift. Useful before commit to catch un-captured changes.

## Client-side sync (v1.35, Windows only)

`./scripts/sync-vscode-client.sh [resolve|capture|deploy|diff]`, run from the Windows client machine:

- `resolve` — print the detected Windows VSCode `User/` directory and exit. Sanity-check detection before trusting `capture`/`deploy`.
- `capture` — copy the live `settings.json`/`keybindings.json` into `client-settings.json`/`client-keybindings.json`. Run after changing VSCode client settings.
- `deploy` — copy the tracked files onto the live path. Creates the `User/` directory if absent.
- `diff` — unified diff between tracked and live, per file.

Unlike `server-extensions.json`, these two files are treated as **opaque text** (plain `cp`/`diff -u`), never parsed as JSON — VSCode's config format is JSONC (comments allowed) and hand-edited.

**Detection is unverified against a real Windows machine as of v1.35** — built and unit-tested here against mocked `cmd.exe`/`wslpath`/`cygpath` on Linux, because no Windows machine exists in the dev-platform build environment. Run `resolve` on the real machine first; if it fails, the detection logic in `scripts/sync-vscode-client.sh` needs a follow-on fix, not a workaround.

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
