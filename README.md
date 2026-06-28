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
| `scaffolding/` | New-project starter templates (`go-service`, `python-agent`, `next-frontend`). `scripts/new-project.sh` scaffolds from a template via conversational Q&A; see `docs/NEW-PROJECT.md`. |
| `monitoring/` | Workflow telemetry — JSON Schema for events (`schemas/event-v1.json`), aggregator (`aggregator.py`), metrics catalog (`metrics.md`). CLI entry: `scripts/report.sh`. |
| `shell/` | Shell helpers, git-hook templates, worktree-isolation tooling (`shell/worktree/`, v1.4) |
| `scripts/` | Install / uninstall / verify scripts; spec-taxonomy checker |
| `tasks/` | Spec files (output of `/plan`) |
| `docs/` | Long-form architecture and how-to docs |

Each directory has a `README.md` documenting its contract — read that before adding files.

## Editing artifacts

The tracked file is the source of truth. Edit it in this repo, run `./scripts/install.sh` (or `./scripts/install.sh <category>` for a single category), restart Claude Code. Editing under `~/.claude/` directly is overwritten on next install — don't edit there.

`./scripts/install.sh` accepts: `commands`, `skills`, `settings`, `hooks`, `vscode`, `git-hooks` (v1.2 — opt-in pre-commit hook), `worktree` (v1.4 — concurrent-dev isolation tooling), or `all` (default).

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

See [ROADMAP.md](ROADMAP.md) for the spec sequence. Roadmap Phase headers use semver (`v<MAJOR>.<MINOR>: <Title>`) and map 1:1 to GitHub Milestones. **v0.1 – v0.9 all shipped 2026-05-08 – 2026-05-12** (v0.7 Team Enablement closes with the `v0.7` release tag, the live Pages docs site at [teelr.github.io/dev-platform](https://teelr.github.io/dev-platform/), and GitHub Actions CI required on every PR; v0.8 Cross-project orchestration closes with the `v0.8` release tag and ships the full fleet-operations toolchain; v0.9 Migration tooling closes with the `v0.9` release tag and ships `scripts/migrate-workflow-chain.sh` + `scripts/audit-project-drift.sh` for cross-project drift detection and repair). Every `/gate fast` against dev-platform runs `./scripts/gate_fast.sh` mechanically (158 checks, < 30s) — locally AND in CI on every PR. Run `./scripts/report.sh` for a daily/weekly/all metrics report; `./scripts/sync-vscode.sh` for VSCode extension capture/deploy/diff; `./scripts/sync-milestones.sh` for ROADMAP→Milestones drift detection; `./scripts/fleet-gate.sh` (v0.8) to sweep gates across every active project in `monitoring/projects.json`; `./scripts/fleet-status.sh` (v0.8) for the per-project state dashboard; `./scripts/fleet-install-template.sh --project <name> [--apply]` (v0.8) for opt-in install of the dev-platform-gate consumer template (dry-run default; the only mutation v0.8 performs against `projects/`, governed by a narrow Scope-rule carve-out in [CLAUDE.md](CLAUDE.md)); `./scripts/fleet-pins.sh` (v0.8) for per-project pin tracking against the latest dev-platform release (6 staleness states: self / up-to-date / behind / floating / unparseable / not-adopted). Slash commands `/pr` and `/merge` mechanically enforce the workflow's post-`push` discipline — `/merge` refuses on red CI with no override flag. `./scripts/audit-project-drift.sh` for a read-only cross-project chain + taxonomy drift report; `./scripts/migrate-workflow-chain.sh --project <name> [--apply]` (v0.9) to rewrite old workflow chain references in a project's CLAUDE.md (dry-run default). `./scripts/verify-remotes.sh` (v1.1) to verify every owned project's git origin and per-repo identity against `monitoring/remotes.json`. `./scripts/check-comms-delivery.sh` (v1.5) to verify every post-migration ask-communique links a live upstream GitHub issue; `./scripts/setup-consumer-labels.sh --apply` (v1.5) to create the `consumer:*` triage labels on each upstream dependency repo from `monitoring/comms-consumers.json` (dry-run default) — paired with the Dependabot consumer template at `extensions/github-actions/dependabot-consumer-template.yml`, these finish the cross-repo comms migration (`docs/CROSS-REPO-COMMS.md`).

## Conventions

Detailed development standards — workflow, taxonomy, language matrix, port registry, project structure — live in [CLAUDE.md](CLAUDE.md). That file is auto-loaded into every Claude Code session under `/home/rich/dev/`.
