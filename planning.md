# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** `tasks/dev-platform-vscode-coverage-spec.md` (ships as **v0.6: VSCode Coverage — Server-Side**); Phase 4 of v0.5 also queued behind it
- **Active Roadmap Phase:** v0.1 through v0.5 shipped (v0.5 closed via PR #4, Release v0.5 cut 2026-05-11). **v0.6 VSCode Coverage (Server-Side) implemented on branch `v0.6/server-side-extensions`**, awaiting PR merge. Server-side scope only (Option C — laptop-side coverage deferred to a future v0.6b spec). After v0.6 merges, the next Roadmap Phase is **v0.7: Team Enablement**.

## Recently shipped

Hashes intentionally omitted — `git log` is the authoritative record; this section is the human-readable summary. (Convention adopted 2026-05-09 after the v0.1 + v0.2 self-reference paradox surfaced — see commands/docs.md and tasks/lessons.md.)

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

- **v0.6 VSCode Coverage (Server-Side) — implemented** on branch `v0.6/server-side-extensions`:
  - Change 1: `extensions/vscode/{README.md,server-extensions.json}` (NEW) — directory contract + 43-extension tracked list (real captured state from this server)
  - Change 2: `scripts/sync-vscode.sh` (NEW) — capture/deploy/diff modes + `--file <path>` override for testability + `--help` heredoc
  - Change 3: Captured live state into `server-extensions.json` (43 entries, all match `publisher.name`, md5 matches `code --list-extensions` output)
  - Change 4: `scripts/install.sh` — `install_vscode()` function + `vscode` case-statement entry. Permissive-by-design: partial install failures emit WARN; only catastrophic all-failed case returns 1. Documented inline.
  - Change 5: `tests/vscode/` (NEW) — 10-assertion fixture suite + mock `code` binary at `fixtures/mock-bin/code` enables capture/deploy round-trip testing without touching live state. Auto-discovered by `gate_fast.sh`.
  - Change 6: Doc sweep marking v0.6 COMPLETE — this very update.
  - **Post-/review fixes** (resolved /review's 3 quality items): sorted `current()` output for stable diffs across CLI versions; added `--file <path>` flag to sync-vscode.sh for testability; refactored `install_vscode()` to use process substitution + failure counter (returns non-zero only on catastrophic all-failed). Plus closed the coverage gap with 4 new mock-based round-trip assertions.
  - **Bonus catches (Consumer Audit rule fired twice in v0.6 alone)**: `.gitignore` needed `!extensions/**/` subdir re-include (same pattern as scaffolding/monitoring/tests) AND `!tests/**/mock-bin/*` for the extension-less mock binary. Both caught at /code time via `git check-ignore -v` per the Consumer Audit checklist.
  - Gate green (62 PASS / 0 FAIL — was 52, added 10 vscode assertions). /test, /review, /gate fast all clean.
- **Once v0.6 PR merges, the next Roadmap Phase is v0.7: Team Enablement** (CI workflow template, taxonomy enforcement on PRs, PR bot for taxonomy violations, GitHub Pages docs site + `docs/GLOSSARY.md`, GitHub Milestones automation). Also queued: a future **v0.6b: VSCode Client-Side Coverage** spec for laptop-side `settings.json`/keybindings/snippets/extensions when there's appetite — explicitly out of v0.6 scope per the Option C decision.
- v0.5 spec filename keeps legacy `r2` prefix; cleanup deferred to v0.9 migration tooling.

## Taxonomy migration note (2026-05-11)

Roadmap Phase headers migrated from the custom `R<N>: <Title>` prefix to the GitHub-native `v<MAJOR>.<MINOR>: <Title>` (semver). Mapping: R1→v0.1, R1.5→v0.2, R4a→v0.3, R3→v0.4, R2→v0.5, R4b→v0.6, R7→v0.7, R6→v0.8, R5→v0.9. Each Roadmap Phase now maps to a GitHub Milestone with the same title. Spec filenames with the legacy `r<N>-` prefix stay as-is until v0.9 cleans them up. The canonical rule lives in `dev/CLAUDE.md`; the enforcement check ships in v0.7.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when v0.5 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
