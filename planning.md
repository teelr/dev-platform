# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** `tasks/dev-platform-team-enablement-spec.md` (ships as **v0.7: Team Enablement** across 4 Spec Phases via per-Spec-Phase branching)
- **Active Roadmap Phase:** v0.1 through v0.6 shipped (v0.6 closed via PR #6, Release v0.6 cut 2026-05-11). **v0.7 Phase 1 (taxonomy enforcement extended to roadmaps) implemented on branch `v0.7/phase-1-taxonomy-extension`**, awaiting PR merge. v0.7 Phases 2–4 still queued (GitHub Actions CI, GitHub Pages + GLOSSARY, Milestones automation).

## Recently shipped

Hashes intentionally omitted — `git log` is the authoritative record; this section is the human-readable summary. (Convention adopted 2026-05-09 after the v0.1 + v0.2 self-reference paradox surfaced — see commands/docs.md and tasks/lessons.md.)

- v0.6 VSCode Coverage (Server-Side) — (2026-05-11, PR #6 squash-merged as commit `3b8ff82`, closes v0.6 Milestone, Release v0.6 cut at tag `v0.6`): `extensions/vscode/{README.md,server-extensions.json}` tracking 43 captured extensions, `scripts/sync-vscode.sh` capture/deploy/diff with `--file <path>` override, `scripts/install.sh vscode` permissive-by-design (WARN on partial fail, exit 1 only on catastrophic all-failed; graceful skip when `code` CLI absent), `tests/vscode/` 10-assertion fixture suite using mock `code` binary at `fixtures/mock-bin/code`. Two Consumer Audit catches in one session: `!extensions/**/` subdir re-include and `!tests/**/mock-bin/*` (extension-less files). Single-PR strategy per the v0.6 spec's "small Roadmap Phase" carve-out.
- v0.5 Phase 4 — Tests + Acceptance (2026-05-11, PR #4 squash-merged as commit `b7c0196`, closes v0.5 Milestone, Release v0.5 cut at tag `v0.5`): 10-assertion `tests/monitoring/` fixture suite (auto-discovered by gate_fast.sh) + live cutover verified all 4 new event types firing from real Claude Code sessions across atlas/kermit/kermit-pa/dev-platform (62 distinct UUID sessions). Post-/review refactor extracted `tests/monitoring/asserts.py` named-function harness eliminating shell-expansion footgun. Bonus catch: `.gitignore` allow-list missing `!tests/**/*.py` + `!tests/**/*.jsonl` — same Consumer Audit pattern as Phase 2.
- Consumer Audit rule promoted to `dev/CLAUDE.md` (2026-05-11, PR #5 squash-merged as commit `24e062f`): 5-point checklist for new file types in glob-managed directories. Promoted from 2 recurring 2026-05-11 lessons.md entries (Phase 2 hooks/*.py + Phase 4 tests/**/*.{py,jsonl}). Both original lessons marked `→ Rule in dev/CLAUDE.md`.
- v0.5 Phase 3 — Aggregation + Reporting (2026-05-11, PR #3 squash-merged as commit `7ca89f1`): `monitoring/aggregator.py` (parses both legacy text + JSONL, 5 metric functions, CLI with `--period`/`--project`/`--json`/`--log`), `scripts/report.sh` CLI wrapper, `monitoring/metrics.md` catalog with Definition/Source/Limitations per metric. Post-/review polish: aligned `code.count` field naming with other metrics; extracted `metric_events_per_project()` as a helper; replaced brittle `sed` in `report.sh --help` with heredoc.
- v0.5 Phase 2 — Collectors (2026-05-11, PR #2 squash-merged as commit `c0a2563`): 3 new hooks (SessionStart, UserPromptSubmit, PreToolUse) + gate_fast.sh self-instrumentation + settings.json wires all 4 events. Plus post-/review refactor: extracted `hooks/_emit_event.py` as centralized emitter eliminating `project_for()` duplication across 5 places; added defensive isinstance check for non-string prompt payloads; documented deliberate fallback-emission asymmetry in `monitoring/README.md`.
- v0.5 Phase 1 — Schema + Storage Layer (2026-05-11, PR #1 squash-merged as commit `e4d9a39`): event-v1 JSON schema + examples.jsonl, JSONL migration of `hooks/post-tool-heartbeat.sh` (from `<ts> tool=X` text), gitignore allow-list for `monitoring/**/*.{py,json,jsonl}`.
- Taxonomy migration (2026-05-11, `eda0b45` + `0f33ea1`): Roadmap Phase headers renamed `R<N>` → `v<MAJOR>.<MINOR>` org-wide; v0.7 spec extended to include `docs/GLOSSARY.md`; GitHub Milestones + Releases seeded; branch protection enabled on `main`; repo made public.
- v0.4 Testing (2026-05-10): `scripts/gate_fast.sh` orchestrator + 5 auto-discovered test suites under `tests/` (hooks fixtures, command frontmatter validator, taxonomy self-test, install round-trip, scaffold smoke). 42 checks aggregate to a single PASS/FAIL in < 1s. Replaces conversation-derived gate-fast with a runnable script. Scope-rule + Repo Structure updated in `dev/CLAUDE.md`.
- v0.3 Project Scaffolding (2026-05-10): three starter templates (`go-service`, `python-agent`, `next-frontend`) + `scripts/new-project.sh` orchestrator + `docs/NEW-PROJECT.md` Q&A pattern + Scope-rule scaffolding carve-out. Assistant runs the scaffold; user describes the project.
- /docs skill rewrite (2026-05-09): no longer self-references the not-yet-landed commit; staging-only (per project bundling rule)

## In flight

- **v0.7 Phase 1 (Taxonomy enforcement extended) — implemented** on branch `v0.7/phase-1-taxonomy-extension`:
  - Change 1: `scripts/check_spec_taxonomy.sh` — second scan pass for `ROADMAP.md` + `planning.md` flagging non-conforming Roadmap Phase headers (`R<N>:`, `Sprint X:`, `Stage Y:`, `Q<N>-<YYYY>:`, `<YYYY>Q<N>:`). Existing spec-structural scan pass unchanged. Error-message path hardcoded to `/home/rich/dev/CLAUDE.md` (was `$(dirname ...)` derived, which evaluated wrong from temp-dir test harness — caught at /review).
  - Change 2: `tests/taxonomy/fixtures/{conformant-roadmap,bad-roadmap-sprint,bad-roadmap-rprefix,bad-roadmap-multi}.md` (4 new fixtures) + extended `tests/taxonomy/run.sh` with `run_roadmap_fixture` helper accepting an optional 4th `expected_match` arg that captures stderr and greps for the specific killed-prefix line. Multi-violation fixture exercises the accumulator loop.
  - **Post-/review fixes** (resolved /review's 3 quality items): hardcoded error-message path; strengthened assertions to grep stderr for specific killed-prefix substring (was exit-code-only); added `bad-roadmap-multi.md` exercising accumulator with both Sprint AND R-prefix violations.
  - Gate green (66 PASS / 0 FAIL — was 62, added 4 taxonomy assertions covering the new Roadmap scan pass).
- **v0.7 Phases 2–4 still queued**: Phase 2 (GitHub Actions CI workflows + reusable taxonomy-check + consumer template + branch protection + `docs/CI-INTEGRATION.md`), Phase 3 (GitHub Pages render + `docs/GLOSSARY.md`), Phase 4 (`scripts/sync-milestones.sh` + `tests/milestone-sync/`). Each ships as a separate PR per the per-Spec-Phase strategy.
- After v0.7 closes: **v0.8 Cross-project orchestration**, **v0.9 Migration tooling**, **v1.0 Feature-complete**. Optional **v0.6b: VSCode Client-Side Coverage** still on the backlog for laptop-side `settings.json`/keybindings/snippets/extensions.
- v0.5 spec filename keeps legacy `r2` prefix; v0.4 keeps `r3`, v0.3 keeps `r4a` — cleanup deferred to v0.9 migration tooling.

## Taxonomy migration note (2026-05-11)

Roadmap Phase headers migrated from the custom `R<N>: <Title>` prefix to the GitHub-native `v<MAJOR>.<MINOR>: <Title>` (semver). Mapping: R1→v0.1, R1.5→v0.2, R4a→v0.3, R3→v0.4, R2→v0.5, R4b→v0.6, R7→v0.7, R6→v0.8, R5→v0.9. Each Roadmap Phase now maps to a GitHub Milestone with the same title. Spec filenames with the legacy `r<N>-` prefix stay as-is until v0.9 cleans them up. The canonical rule lives in `dev/CLAUDE.md`; the enforcement check ships in v0.7.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when v0.5 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
