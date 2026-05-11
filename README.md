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
| `extensions/` | IDE config. `vscode/server-extensions.json` is the tracked extension list; `scripts/install.sh vscode` reinstalls them all; `scripts/sync-vscode.sh` captures/deploys/diffs. Client-side coverage deferred to v0.6b. |
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

See [ROADMAP.md](ROADMAP.md) for the spec sequence. Roadmap Phase headers use semver (`v<MAJOR>.<MINOR>: <Title>`) and map 1:1 to GitHub Milestones. **v0.1 – v0.7 all shipped 2026-05-08 – 2026-05-11** (v0.7 Team Enablement closes with the `v0.7` release tag, the live Pages docs site at [teelr.github.io/dev-platform](https://teelr.github.io/dev-platform/), GitHub Actions CI required on every PR, and `scripts/sync-milestones.sh` keeping Milestones in sync with `ROADMAP.md`). Every `/gate fast` against dev-platform runs `./scripts/gate_fast.sh` mechanically (100 checks, < 30s) — locally AND in CI on every PR. Run `./scripts/report.sh` for a daily/weekly/all metrics report; `./scripts/sync-vscode.sh` for VSCode extension capture/deploy/diff; `./scripts/sync-milestones.sh` for ROADMAP→Milestones drift detection; `./scripts/fleet-gate.sh` (v0.8) to sweep gates across every active project in `monitoring/projects.json`; `./scripts/fleet-status.sh` (v0.8) for the per-project state dashboard (branch, last-commit recency, uncommitted count, taxonomy compliance, consumer-template adoption flag). Slash commands `/pr` and `/merge` (v0.8 follow-up chore) mechanically enforce the workflow's post-`push` discipline — `/merge` refuses on red CI with no override flag. **v0.8 Cross-project orchestration in flight** — Phase 1 (registry + fleet-gate) shipped at PR #12 `85ebd38`; Phase 2 (fleet dashboard) implemented on branch `v0.8/phase-2-fleet-dashboard`, awaiting PR merge; Phases 3–4 (Drift Correction, Pin Tracking) queued. v0.8 release tag cuts at Phase 4 completion.

## Conventions

Detailed development standards — workflow, taxonomy, language matrix, port registry, project structure — live in [CLAUDE.md](CLAUDE.md). That file is auto-loaded into every Claude Code session under `/home/rich/dev/`.
