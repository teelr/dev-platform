# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** none — R3 Testing shipped 2026-05-10
- **Active Roadmap Phase:** R1 + R1.5 + R4a + R3 done; **R2 Monitoring is next** — the heartbeat hook from R1.5 has been collecting data, and R3's `scripts/gate_fast.sh` is now the gate every spec runs through

## Recently shipped

Hashes intentionally omitted — `git log` is the authoritative record; this section is the human-readable summary. (Convention adopted 2026-05-09 after the R1 + R1.5 self-reference paradox surfaced — see commands/docs.md and tasks/lessons.md.)

- R3 Testing (2026-05-10): `scripts/gate_fast.sh` orchestrator + 5 auto-discovered test suites under `tests/` (hooks fixtures, command frontmatter validator, taxonomy self-test, install round-trip, scaffold smoke). 42 checks aggregate to a single PASS/FAIL in < 1s. Replaces conversation-derived gate-fast with a runnable script. Scope-rule + Repo Structure updated in `dev/CLAUDE.md`.
- R4a Project Scaffolding (2026-05-10): three starter templates (`go-service`, `python-agent`, `next-frontend`) + `scripts/new-project.sh` orchestrator + `docs/NEW-PROJECT.md` Q&A pattern + Scope-rule scaffolding carve-out. Assistant runs the scaffold; user describes the project.
- /docs skill rewrite (2026-05-09): no longer self-references the not-yet-landed commit; staging-only (per project bundling rule)

## In flight

- *(none)* — between specs. R2 Monitoring is the next pickup. The R1.5 heartbeat hook is already writing to `~/.claude/dev-platform-telemetry.log`; R2 builds the aggregation + reporting layer on top.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when R2 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
