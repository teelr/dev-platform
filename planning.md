# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** none — R1.5 Global Claude + Hooks Coverage complete (2026-05-09), awaiting commit
- **Active Roadmap Phase:** R1 + R1.5 done; R2 (Monitoring) is next — the heartbeat hook shipped in R1.5 is its data foundation

## Recently shipped

- *(pending)* — R1.5 Global Claude + Hooks Coverage: tracks `~/.claude/CLAUDE.md` as `dev/settings/claude-global.md`, ships first hook script (`hooks/post-tool-heartbeat.sh`) + settings.json hooks block, live cutover executed (13 symlinks healthy)
- `8b52a41` — Scope + Consistency CRITICAL rules; name VSCode + Claude Code as primary gateway
- `770e397` — post-R1 cleanup; ~3 GB reclaimed, dead .gitignore entries pruned
- `957e030` — R1 Foundation Spec: repo restructure, 8 new top-level dirs with READMEs, install/uninstall/verify scripts, Phase 2 artifact migration from `~/.claude/`, live cutover executed and verified

## In flight

- *(none)* — between specs. R2 Monitoring is the next likely pickup; the heartbeat hook is already writing to `~/.claude/dev-platform-telemetry.log` as the data source R2 will consume.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when R2 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
