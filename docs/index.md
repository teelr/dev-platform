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

## Latest release

See [Releases](https://github.com/teelr/dev-platform/releases). v0.6 (VSCode Coverage Server-Side) is the most recent tag; v0.7 cuts at Phase 4 completion.

## Workflow

`/plan → /code → /test → /review → /gate fast → /docs → commit → push → PR → CI → merge → post-merge`

Each step is mechanical and reproducible. See [CLAUDE.md](../CLAUDE.md) for the full discipline.
