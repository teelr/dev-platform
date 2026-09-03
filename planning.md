# dev-platform Planning Snapshot

Static orientation for this repo. Per-phase state lives in files that concurrent
sessions cannot collide on — nothing here is rewritten when a phase ships.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **What shipped, newest first:** `tasks/shipped/` — one file per Roadmap Phase and per chore (`ls -1 tasks/shipped/*.md | sort -r | head`). The newest file is the latest shipped phase.
- **Phase sequence and next version:** `ROADMAP.md`. Version numbers are claimed atomically by `/plan` (`scripts/claim_roadmap_version.py`), so the next number comes from the claim, never from reading this file.
- **In-flight work:** live feature branches, open PRs, and open milestones — sources that cannot go stale. This file deliberately carries no "in flight" section; the hand-maintained one sat six phases out of date before it was removed (v1.24).

## Taxonomy migration note (2026-05-11)

Roadmap Phase headers migrated from the custom `R<N>: <Title>` prefix to the GitHub-native `v<MAJOR>.<MINOR>: <Title>` (semver). Mapping: R1→v0.1, R1.5→v0.2, R4a→v0.3, R3→v0.4, R2→v0.5, R4b→v0.6, R7→v0.7, R6→v0.8, R5→v0.9. Each Roadmap Phase now maps to a GitHub Milestone with the same title. Spec filenames with the legacy `r<N>-` prefix cleaned up in v0.9 Phase 1. The canonical rule lives in `dev/CLAUDE.md`; the enforcement check ships in v0.7.

## Pointer

- `tasks/*-spec.md` — specs, the output of `/plan`
- `tasks/shipped/` — per-phase shipped record (see its README for conventions)
- `tasks/lessons/` — corrections and gotchas, one file per lesson
- `ROADMAP.md` — the Roadmap Phase sequence, one entry per phase
