# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** none — R4a Project Scaffolding shipped 2026-05-10
- **Active Roadmap Phase:** R1 + R1.5 + R4a done; **R3 Testing is next** (promoted ahead of R2 today — every future spec needs gate coverage to ship safely)

## Recently shipped

Hashes intentionally omitted — `git log` is the authoritative record; this section is the human-readable summary. (Convention adopted 2026-05-09 after the R1 + R1.5 self-reference paradox surfaced — see commands/docs.md and tasks/lessons.md.)

- R4a Project Scaffolding (2026-05-10): three starter templates (`go-service`, `python-agent`, `next-frontend`) + `scripts/new-project.sh` orchestrator + `docs/NEW-PROJECT.md` Q&A pattern + Scope-rule scaffolding carve-out. Assistant runs the scaffold; user describes the project.
- /docs skill rewrite (2026-05-09): no longer self-references the not-yet-landed commit; staging-only (per project bundling rule)
- R1.5 Global Claude + Hooks Coverage (2026-05-09): tracks `~/.claude/CLAUDE.md` as `dev/settings/claude-global.md`, ships first hook script (`hooks/post-tool-heartbeat.sh`) + settings.json hooks block, live cutover executed (13 symlinks healthy)

## In flight

- *(none)* — between specs. R3 Testing is the next pickup. R3 will consolidate the conversation-derived gate-fast checks (taxonomy, syntax, JSON validity, install round-trip, scaffold smoke, etc.) into `scripts/gate_fast.sh` plus fixture-based smoke tests for slash commands and hook payloads.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when R3 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
