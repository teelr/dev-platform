# dev-platform Planning Snapshot

Current state of the repo. Refreshed at every spec-completion by `/docs`.

## Current state

- **Name:** `dev-platform` (GitHub: `teelr/dev-platform`, mounted at `/home/rich/dev/`)
- **Active spec:** none — R1 Foundation complete (2026-05-08), awaiting commit
- **Active Roadmap Phase:** R1 done; R2 (Monitoring) is the next planned spec — see `ROADMAP.md`

## Recently shipped

- `957e030` — R1 Foundation Spec: repo restructure, 8 new top-level dirs with READMEs, install/uninstall/verify scripts, Phase 2 artifact migration from `~/.claude/`, live cutover executed and verified
- `2de6114` — consolidate L23/L31/L36 family into 'Verify Against Source of Truth' rule
- `5e18b7e` — register port 8021 for Kermit Harness trigger webhook

## In flight

- *(none)* — between specs. R2 Monitoring Spec is the next likely pickup; no spec drafted yet.

## Pointer

Canonical state lives in `tasks/` (specs) and the future `CHANGELOG.md` (created when R2 starts). `ROADMAP.md` lists the Roadmap Phase sequence; this file is the day-to-day what's-happening view.
