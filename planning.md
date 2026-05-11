# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** `tasks/dev-platform-r2-monitoring-spec.md` (ships as **v0.5: Monitoring**)
- **Active Roadmap Phase:** v0.1 + v0.2 + v0.3 + v0.4 done; **v0.5 Monitoring is in flight** — **Phase 3 of 4 (Aggregation + Reporting) implemented on branch `v0.5/phase-3-aggregation`**, awaiting bundled commit + PR merge. Phases 1 + 2 shipped via PR #1 and PR #2 (both squash-merged). Per-Spec-Phase branching strategy (4 PRs total for v0.5).

## Recently shipped

Hashes intentionally omitted — `git log` is the authoritative record; this section is the human-readable summary. (Convention adopted 2026-05-09 after the v0.1 + v0.2 self-reference paradox surfaced — see commands/docs.md and tasks/lessons.md.)

- v0.5 Phase 2 — Collectors (2026-05-11, PR #2 squash-merged as commit `c0a2563`): 3 new hooks (SessionStart, UserPromptSubmit, PreToolUse) + gate_fast.sh self-instrumentation + settings.json wires all 4 events. Plus post-/review refactor: extracted `hooks/_emit_event.py` as centralized emitter eliminating `project_for()` duplication across 5 places; added defensive isinstance check for non-string prompt payloads; documented deliberate fallback-emission asymmetry in `monitoring/README.md`.
- v0.5 Phase 1 — Schema + Storage Layer (2026-05-11, PR #1 squash-merged as commit `e4d9a39`): event-v1 JSON schema + examples.jsonl, JSONL migration of `hooks/post-tool-heartbeat.sh` (from `<ts> tool=X` text), gitignore allow-list for `monitoring/**/*.{py,json,jsonl}`.
- Taxonomy migration (2026-05-11, `eda0b45` + `0f33ea1`): Roadmap Phase headers renamed `R<N>` → `v<MAJOR>.<MINOR>` org-wide; v0.7 spec extended to include `docs/GLOSSARY.md`; GitHub Milestones + Releases seeded; branch protection enabled on `main`; repo made public.
- v0.4 Testing (2026-05-10): `scripts/gate_fast.sh` orchestrator + 5 auto-discovered test suites under `tests/` (hooks fixtures, command frontmatter validator, taxonomy self-test, install round-trip, scaffold smoke). 42 checks aggregate to a single PASS/FAIL in < 1s. Replaces conversation-derived gate-fast with a runnable script. Scope-rule + Repo Structure updated in `dev/CLAUDE.md`.
- v0.3 Project Scaffolding (2026-05-10): three starter templates (`go-service`, `python-agent`, `next-frontend`) + `scripts/new-project.sh` orchestrator + `docs/NEW-PROJECT.md` Q&A pattern + Scope-rule scaffolding carve-out. Assistant runs the scaffold; user describes the project.
- /docs skill rewrite (2026-05-09): no longer self-references the not-yet-landed commit; staging-only (per project bundling rule)

## In flight

- **v0.5 Monitoring — Phase 3/4 implemented** on branch `v0.5/phase-3-aggregation`:
  - Change 9: `monitoring/aggregator.py` (NEW, 348 lines) — log parser (JSONL + legacy text), 5 metric functions (gate_pass_rate, code_retries, review_count, tool_duration, events_per_project), CLI with `--period`/`--project`/`--json`/`--log` flags
  - Change 10: `scripts/report.sh` (NEW) — thin Bash wrapper delegating to aggregator.py; positional period + project + optional `--json` in any order
  - Change 11: `monitoring/metrics.md` (NEW) — metrics catalog with Definition / Source events / Computation / Known limitations per metric + an "Adding a new metric" contract for future contributors
  - **Post-/review polish** (resolved /review's 3 quality items): renamed `code_invocations` → `count` for cross-metric consistency; extracted `metric_events_per_project()` as a proper helper; replaced brittle `sed -n '2,20p'` with a heredoc in `report.sh --help`.
  - First end-to-end: `./scripts/report.sh daily` against real log emits a real report — gate pass rate 8/10 (80%), 91 paired tool calls, top tools Bash/TodoWrite/Read by avg ms. Backward-compat verified — the 1,124 legacy text-format lines from v0.2 still parse into the same metric pipeline.
  - Gate green (42 PASS / 0 FAIL). /test, /review, /gate fast all clean.
- **Next Phase 4 of 4 (Tests + Acceptance + Docs)** — Changes 12–14 in the spec: `tests/monitoring/` fixture suite (auto-discovered by `gate_fast.sh`), live cutover acceptance (full session lifecycle on a fresh Claude Code restart), doc sweep (README + planning + ROADMAP + lessons). Will land on branch `v0.5/phase-4-tests-acceptance`.
- Spec filename keeps legacy `r2` prefix; cleanup deferred to v0.9 migration tooling.

## Taxonomy migration note (2026-05-11)

Roadmap Phase headers migrated from the custom `R<N>: <Title>` prefix to the GitHub-native `v<MAJOR>.<MINOR>: <Title>` (semver). Mapping: R1→v0.1, R1.5→v0.2, R4a→v0.3, R3→v0.4, R2→v0.5, R4b→v0.6, R7→v0.7, R6→v0.8, R5→v0.9. Each Roadmap Phase now maps to a GitHub Milestone with the same title. Spec filenames with the legacy `r<N>-` prefix stay as-is until v0.9 cleans them up. The canonical rule lives in `dev/CLAUDE.md`; the enforcement check ships in v0.7.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when v0.5 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
