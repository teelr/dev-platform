# dev-platform

Source of truth for Rich's developer environment: rules, slash commands, skills, hooks, settings, install scripts, telemetry, VSCode extensions, GitHub Actions CI.

## Documentation

- **[README](../README.md)** — what this repo is, quick start, repo structure
- **[ROADMAP](../ROADMAP.md)** — Roadmap Phases v0.1 → v1.0
- **[CLAUDE.md](../CLAUDE.md)** — full development standards (workflow, taxonomy, language matrix, port registry, project structure)
- **[Glossary](GLOSSARY.md)** — every project-specific term defined
- **[CI Integration](CI-INTEGRATION.md)** — how to plug your repo into dev-platform's taxonomy gate
- **[New Project](NEW-PROJECT.md)** — conversational Q&A for scaffolding new projects
- **[Project CLAUDE.md template](PROJECT_CLAUDE_TEMPLATE.md)** — what every project's CLAUDE.md should contain
- **[Cross-Repo Comms](CROSS-REPO-COMMS.md)** — how a consumer (PA/Keystone/ATLAS) files asks against a dependency (GitHub issues, not file-relay)

## Latest release

See [Releases](https://github.com/teelr/dev-platform/releases). `v0.9` (Migration tooling) is the current tag. `v1.0` (Feature-complete) is in progress.

## Workflow

`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`

Each step is mechanical and reproducible. See [CLAUDE.md](../CLAUDE.md) for the full discipline.
