# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** none — v0.5: Monitoring is complete (Phase 4 implemented on branch `v0.5/phase-4-tests-acceptance`, awaiting PR merge to close out the Milestone)
- **Active Roadmap Phase:** v0.1 + v0.2 + v0.3 + v0.4 done; **v0.5 Monitoring is shipping** — all 4 Phases implemented via 4 PRs (1, 2, 3 merged; Phase 4 awaiting merge). After Phase 4 merges, v0.5 closes and the next Roadmap Phase is **v0.6: VSCode Coverage**.

## Recently shipped

Hashes intentionally omitted — `git log` is the authoritative record; this section is the human-readable summary. (Convention adopted 2026-05-09 after the v0.1 + v0.2 self-reference paradox surfaced — see commands/docs.md and tasks/lessons.md.)

- v0.5 Phase 3 — Aggregation + Reporting (2026-05-11, PR #3 squash-merged as commit `7ca89f1`): `monitoring/aggregator.py` (parses both legacy text + JSONL, 5 metric functions, CLI with `--period`/`--project`/`--json`/`--log`), `scripts/report.sh` CLI wrapper, `monitoring/metrics.md` catalog with Definition/Source/Limitations per metric. Post-/review polish: aligned `code.count` field naming with other metrics; extracted `metric_events_per_project()` as a helper; replaced brittle `sed` in `report.sh --help` with heredoc.
- v0.5 Phase 2 — Collectors (2026-05-11, PR #2 squash-merged as commit `c0a2563`): 3 new hooks (SessionStart, UserPromptSubmit, PreToolUse) + gate_fast.sh self-instrumentation + settings.json wires all 4 events. Plus post-/review refactor: extracted `hooks/_emit_event.py` as centralized emitter eliminating `project_for()` duplication across 5 places; added defensive isinstance check for non-string prompt payloads; documented deliberate fallback-emission asymmetry in `monitoring/README.md`.
- v0.5 Phase 1 — Schema + Storage Layer (2026-05-11, PR #1 squash-merged as commit `e4d9a39`): event-v1 JSON schema + examples.jsonl, JSONL migration of `hooks/post-tool-heartbeat.sh` (from `<ts> tool=X` text), gitignore allow-list for `monitoring/**/*.{py,json,jsonl}`.
- Taxonomy migration (2026-05-11, `eda0b45` + `0f33ea1`): Roadmap Phase headers renamed `R<N>` → `v<MAJOR>.<MINOR>` org-wide; v0.7 spec extended to include `docs/GLOSSARY.md`; GitHub Milestones + Releases seeded; branch protection enabled on `main`; repo made public.
- v0.4 Testing (2026-05-10): `scripts/gate_fast.sh` orchestrator + 5 auto-discovered test suites under `tests/` (hooks fixtures, command frontmatter validator, taxonomy self-test, install round-trip, scaffold smoke). 42 checks aggregate to a single PASS/FAIL in < 1s. Replaces conversation-derived gate-fast with a runnable script. Scope-rule + Repo Structure updated in `dev/CLAUDE.md`.
- v0.3 Project Scaffolding (2026-05-10): three starter templates (`go-service`, `python-agent`, `next-frontend`) + `scripts/new-project.sh` orchestrator + `docs/NEW-PROJECT.md` Q&A pattern + Scope-rule scaffolding carve-out. Assistant runs the scaffold; user describes the project.
- /docs skill rewrite (2026-05-09): no longer self-references the not-yet-landed commit; staging-only (per project bundling rule)

## In flight

- **v0.5 Monitoring — Phase 4/4 implemented** on branch `v0.5/phase-4-tests-acceptance`:
  - Change 12: `tests/monitoring/` fixture suite — 6 fixtures (empty, legacy-only, mixed-window, two-projects, code-retry, plus malformed-mixed + degraded-events added during /review fixes) + named-function assertion harness (`asserts.py`) + runner. Auto-discovered by `gate_fast.sh`. 10 assertions covering: empty log, legacy parsing, gate pass rate, tool pairing, /code retry heuristic, project filter, malformed-line skipping, degraded-event exclusion.
  - Change 13: Live cutover acceptance — all 4 new event types confirmed firing from real Claude Code sessions (68 session_start + 4 user_prompt + 143 tool_use_start + 991 tool_use_end across 62 distinct UUID sessions in 4 projects: atlas, dev-platform, kermit, kermit-pa). No Claude Code restart needed — sibling-project sessions picked up the new settings.json automatically after PR #2 merged.
  - Change 14: Doc sweep marking v0.5 COMPLETE — this very update.
  - **Post-/review refactor** (resolved /review's 3 quality items + 1 bonus catch): refactored runner from inline shell-embedded Python heredoc to `tests/monitoring/asserts.py` with named functions — eliminates shell-expansion footgun, surfaces Python's AssertionError messages on failure. Added 3 new fixtures + 3 new assertions for coverage gaps (project filter, malformed lines, degraded events). Bonus catch: `.gitignore` had no allow-list for `tests/**/*.py` or `tests/**/*.jsonl` — same consumer-audit pattern as Phase 2's `hooks/*.py`. Extended gitignore.
  - Gate green (52 PASS / 0 FAIL). /test, /review, /gate fast all clean.
- **Once Phase 4 PR merges, v0.5: Monitoring is complete**: workflow telemetry (4 hooks + gate_fast self-instrumentation) → JSONL event log → Python aggregator → 5 metrics → markdown/JSON report via `./scripts/report.sh`. Backward-compatible with v0.2's legacy text format. 4 PRs total (per-Spec-Phase strategy), GitHub Milestone closes on Phase 4 merge, Release `v0.5` cuts after.
- **Next Roadmap Phase: v0.6 VSCode Coverage** (planned) — VSCode user-profile config, keybindings, snippets, statusline, tracked extensions list.
- Spec filename keeps legacy `r2` prefix; cleanup deferred to v0.9 migration tooling.

## Taxonomy migration note (2026-05-11)

Roadmap Phase headers migrated from the custom `R<N>: <Title>` prefix to the GitHub-native `v<MAJOR>.<MINOR>: <Title>` (semver). Mapping: R1→v0.1, R1.5→v0.2, R4a→v0.3, R3→v0.4, R2→v0.5, R4b→v0.6, R7→v0.7, R6→v0.8, R5→v0.9. Each Roadmap Phase now maps to a GitHub Milestone with the same title. Spec filenames with the legacy `r<N>-` prefix stay as-is until v0.9 cleans them up. The canonical rule lives in `dev/CLAUDE.md`; the enforcement check ships in v0.7.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when v0.5 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
