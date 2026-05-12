<!-- PROJECT CLAUDE.md TEMPLATE
     Copy this to your project root as CLAUDE.md and fill in the sections.
     Keep under 200 lines. Move API docs, UI design, troubleshooting to docs/.
     Do NOT duplicate rules from /home/rich/dev/CLAUDE.md — they apply automatically. -->

# {Project Name}

{1-2 sentence description. What it does and why it exists.}

**Production:** https://X.richteel.com | **Dev:** http://192.168.1.101:{port}

## Architecture

```text
Browser → Frontend (:XXXX) → Backend (:YYYY) → Database/Storage
```

## Tech Stack

| Component | Language | Framework |
| --------- | -------- | --------- |
| Backend | Go/Python/Rust | chi/FastAPI/actix |
| Frontend | TypeScript | Next.js + React + TailwindCSS |
| Database | SQL/NoSQL | PostgreSQL/MongoDB |

## Build & Run

```bash
# Prerequisites
{any setup needed}

# Development
{exact commands to start dev environment}

# Production
{exact commands for production deployment}
```

## Configuration

Environment variables via `.env`:

```text
{LIST_ALL_ENV_VARS=with_descriptions}
```

## Ports

| Port | Service | Protocol |
| ---- | ------- | -------- |
| XXXX | Backend | TCP |
| YYYY | Frontend | TCP (dev only) |

## API Endpoints

| Method | Path | Description |
| ------ | ---- | ----------- |
| GET | /api/health | Health check |

## File Structure

```text
project-name/
├── backend/         # {language} backend
├── frontend/        # Next.js frontend
├── config/          # Configuration files
├── docs/            # Documentation (API docs, architecture, guides)
├── scripts/         # Dev/deploy scripts
├── tasks/           # Spec files, lessons.md
├── tests/           # Test files
└── logs/            # Application logs
```

## Rules

**CRITICAL — Cross-project boundary:** NEVER write code in or modify files belonging to another project from this session. If a task requires a change in a different project, STOP — communicate the need via a handoff note, GitHub issue, or explicit user instruction to switch sessions. Let the other project's session make the change under its own gate and review discipline. Cross-project writes bypass that project's gate, leave no commit context, and are invisible to its team.

{Project-specific rules. Things that have gone wrong before. Things unique to this project.
Do NOT repeat rules from /home/rich/dev/CLAUDE.md — those apply automatically.}

## Patterns

{Established patterns to follow in this project. Architectural decisions.
Do NOT repeat patterns from /home/rich/dev/CLAUDE.md.}

## Spec Files

All `tasks/*-spec.md` files MUST use the locked Phase + Change taxonomy from
`/home/rich/dev/CLAUDE.md`:

- Section headers: `## Phase N: <title>`
- Atomic step headers: `### Change N: <title>` — N is continuous across the whole spec
- One Change → one commit
- NEVER use the killed terms: Section, Task, Step, Item, Sprint, Stage, Iteration, Milestone, Group, Epic

Wire `/home/rich/dev/scripts/check_spec_taxonomy.sh` into your project's gate
(e.g. `gate fast`) to enforce automatically. It exits 1 if any spec uses old vocabulary.
