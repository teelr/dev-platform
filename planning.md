# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** none — R1.5 Global Claude + Hooks Coverage shipped 2026-05-09
- **Active Roadmap Phase:** R1 + R1.5 done; R2 (Monitoring) is next — the heartbeat hook shipped in R1.5 is its data foundation

## Recently shipped

Hashes intentionally omitted — `git log` is the authoritative record; this section is the human-readable summary. (Convention adopted 2026-05-09 after the R1 + R1.5 self-reference paradox surfaced — see commands/docs.md and tasks/lessons.md.)

- R1.5 Global Claude + Hooks Coverage (2026-05-09): tracks `~/.claude/CLAUDE.md` as `dev/settings/claude-global.md`, ships first hook script (`hooks/post-tool-heartbeat.sh`) + settings.json hooks block, live cutover executed (13 symlinks healthy)
- Scope + Consistency CRITICAL rules + Primary Gateway clarification (2026-05-09): dev-platform drives every layer below it
- post-R1 cleanup (2026-05-08): ~3 GB reclaimed, dead .gitignore entries pruned

## In flight

- *(none)* — between specs. R2 Monitoring is the next likely pickup; the heartbeat hook is already writing to `~/.claude/dev-platform-telemetry.log` as the data source R2 will consume.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when R2 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
