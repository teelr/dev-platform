# dev-platform

Source-of-truth repo for Rich's developer environment: rules, slash commands, skills, hooks, settings, install/uninstall scripts. The `~/.claude/` directory on each machine is a *deployment* of this repo.

## Quick start

```bash
git clone git@github.com:teelr/dev-platform.git ~/dev
cd ~/dev
./scripts/install.sh
# restart Claude Code
```

The install script symlinks tracked files from this repo into `~/.claude/`. Edits to files in this repo land directly on the deployed copy — no rebuild step.

## Repo structure

| Directory | Purpose |
| --------- | ------- |
| `commands/` | Slash command definitions (`/plan`, `/code`, `/test`, etc.) |
| `skills/` | User-defined skills + `WORKFLOW_MANUAL.md` taxonomy reference |
| `settings/` | Global Claude Code config (`settings.json`) |
| `hooks/` | Shell scripts invoked by Claude Code hook events |
| `extensions/` | IDE config (VSCode, statusline) — populated by future spec |
| `scaffolding/` | New-project starter templates — populated by future spec |
| `monitoring/` | Workflow telemetry — JSON Schema for events (`schemas/event-v1.json`), aggregator (`aggregator.py`), metrics catalog (`metrics.md`). CLI entry: `scripts/report.sh`. |
| `shell/` | Shell helpers, git-hook templates |
| `scripts/` | Install / uninstall / verify scripts; spec-taxonomy checker |
| `tasks/` | Spec files (output of `/plan`) |
| `docs/` | Long-form architecture and how-to docs |

Each directory has a `README.md` documenting its contract — read that before adding files.

## Editing artifacts

The tracked file is the source of truth. Edit it in this repo, run `./scripts/install.sh` (or `./scripts/install.sh <category>` for a single category), restart Claude Code. Editing under `~/.claude/` directly is overwritten on next install — don't edit there.

`./scripts/install.sh` accepts: `commands`, `skills`, `settings`, `hooks`, or `all` (default).

## Verifying deployment

```bash
./scripts/verify.sh
```

Reports drift between tracked and deployed state — flags missing symlinks, real files where a symlink should be, and orphan symlinks pointing at stale paths. Exits non-zero on any drift.

## Uninstall

```bash
./scripts/uninstall.sh
```

Removes all repo-owned symlinks from `~/.claude/`. Non-destructive: leaves user-generated state in `~/.claude/projects/` (memory, transcripts) untouched. Re-run `install.sh` to restore.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the spec sequence. Roadmap Phase headers use semver (`v<MAJOR>.<MINOR>: <Title>`) and map 1:1 to GitHub Milestones. v0.1 (Foundation) shipped 2026-05-08, v0.2 (Global Claude + Hooks) shipped 2026-05-09, v0.3 (Project Scaffolding) + v0.4 (Testing) shipped 2026-05-10, v0.5 (Monitoring) shipped 2026-05-11. Every `/gate fast` against dev-platform runs `./scripts/gate_fast.sh` mechanically (52 checks, < 2s). Run `./scripts/report.sh` for a daily/weekly/all metrics report (gate pass rate, /code retry counts, /review count, tool-execution-time average) across one or all projects. **v0.6 VSCode Coverage is next** — VSCode user-profile config, keybindings, snippets, statusline, tracked extensions list.

## Conventions

Detailed development standards — workflow, taxonomy, language matrix, port registry, project structure — live in [CLAUDE.md](CLAUDE.md). That file is auto-loaded into every Claude Code session under `/home/rich/dev/`.
