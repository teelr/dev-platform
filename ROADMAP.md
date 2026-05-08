# dev-platform Roadmap

Spec sequence for the `teelr/dev-platform` repo. Each entry is a Roadmap Phase — its detailed Spec lives under `tasks/`.

- **R1: Foundation** *(complete — 2026-05-08, `tasks/dev-platform-foundation-spec.md`)* — repo restructure, top-level dir contracts, install / uninstall / verify scripts. Migrated `~/.claude/{commands,skills/WORKFLOW_MANUAL.md,settings.json}` into the repo as the source of truth; live cutover executed against `~/.claude/`.
- **R2: Monitoring** *(next — planned)* — telemetry on workflow effectiveness. Track gate pass rate, `/code` retry counts, `/review` catch rate, hook execution time per project. Schemas in `monitoring/`, collectors as hook scripts in `hooks/`.
- **R3: Testing** *(planned)* — regression coverage for slash commands and hooks. Smoke tests that exercise each command in a fixture and assert the expected artifact is produced. `make check` target wired into a project's pre-commit gate.
- **R4: Extensions** *(planned)* — VSCode user-profile config, statusline scripts, `scripts/new-project.sh <template>` helper backed by `scaffolding/<template>/` templates.
- **R5: Migration tooling** *(planned)* — auto-migrate older project layouts (legacy taxonomy, scattered config) onto the standard project structure described in `CLAUDE.md`.

Canonical roadmap detail (per-Roadmap-Phase exit criteria, dependencies, demo definition) lives in `tasks/dev-platform-roadmap.md` — created when R2 starts.
