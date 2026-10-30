# shell/git-hooks/

Git hook templates that any teelr/dev-* repo can opt into. Universal: each hook script no-ops when its preconditions aren't met (e.g., the gate part of `pre-commit` does nothing when the repo has no `scripts/gate_fast.sh`), so the same files install harmlessly across every repo.

**What goes here:** Git hook scripts named per git's convention — `pre-commit`, `commit-msg`, `pre-push`, `post-commit`, etc. — with NO file extension. Files are executable bash.

**What does NOT go here:** Claude Code hook scripts (those live in `hooks/` and feed into `settings.json` event wiring); per-project bash helpers (those belong in `shell/*.sh` or each project's own `scripts/`); secrets or per-machine config.

**Deployment:** `scripts/install.sh git-hooks` symlinks every file under this directory (except `README.md`) into `~/.claude/git-hooks/`. The category is opt-in — running `install.sh` without arguments installs the symlinks but does NOT enable the hooks in any repo.

## Enabling the hook in a repo

Run this yourself, inside the repo:

```bash
ln -s ~/.claude/git-hooks/pre-commit .git/hooks/pre-commit
```

Do **not** use `git config core.hooksPath ~/.claude/git-hooks` for this. `core.hooksPath` replaces the repo's whole hooks directory, so every other hook the repo has (for example the `pre-push` hooks in `kermit` and `kermit-pa`) silently stops running. The symlink touches only `pre-commit`. If the repo already has its own `.git/hooks/pre-commit`, `ln` refuses to replace it; sort that out by hand.

dev-platform sessions do not write into `projects/`, so enabling the hook in a project is an action you take in that project. `scripts/check-secret-hook.sh` is a read-only report of which projects have it (`ENABLED`, `NOT-ENABLED`, or `OTHER-HOOK` for a project that already has its own `pre-commit`).

## What `pre-commit` does (in this order)

1. **Secret scan (v1.41).** Looks only at what the commit *adds*, in every repo, whether or not it has `scripts/gate_fast.sh`. A hit refuses the commit and prints the pattern name, the file, and the line number. It never prints the matched text.
   - Content patterns: `github-token`, `anthropic-key`, `openai-key`, `aws-access-key-id`, `google-api-key`, `slack-token`, `huggingface-token`, `private-key-block`.
   - Path patterns: `path-env-file` (`.env` and `.env.*`, except names ending `.example`, `.sample`, `.template`, `.dist`) and `path-key-file` (`*.pem`, `*.p12`, `*.pfx`, `id_rsa*`, `id_ed25519*`).
   - Skipped automatically: `venv/`, `*_env/`, `node_modules/`, `site-packages/`, `.git/`.
   - At most 20 findings are printed; the rest are counted.
2. **Gate.** Refuses the commit when `scripts/gate_fast.sh` fails; does nothing when the repo has none. In a repo that has a gate, enabling the hook means the gate runs on every commit.

## Bypasses and allowances

| What | How |
| ---- | --- |
| Skip the secret scan once | `SKIP_SECRET_SCAN=1 git commit ...` |
| Skip the gate once | `SKIP_GATE_FAST=1 git commit ...` (does **not** skip the secret scan) |
| Turn the gate part off for a repo | `git config devplatform.precommitGate false` (the secret scan still runs) |
| Allow a path | add a glob to `.secret-scan-allow` at the repo root, one per line, `#` for comments |
| Allow one line | put `secret-scan:allow` on the line |

An agent session must not set a bypass variable or use `git commit --no-verify` without the user saying so. `settings/settings.json` denies `--no-verify` and `-n` on `git commit` and `git push` for Claude sessions.

## Limits

- It catches provider-shaped tokens and `.env` / key files. It does not catch an arbitrary password, a custom key format, or a secret split across lines.
- It scans what a commit adds, not history. A secret committed earlier stays in history until the history is rewritten or the credential is revoked.
- It only protects a repo where it is enabled. Check with `scripts/check-secret-hook.sh`.
- `git commit --no-verify`, run directly in a terminal, skips every hook. It is a seat belt, not a lock.
