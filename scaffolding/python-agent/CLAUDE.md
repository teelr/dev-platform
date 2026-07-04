<!-- PROJECT CLAUDE.md
     Per /home/rich/dev/CLAUDE.md Project CLAUDE.md Standard:
     - Max 200 lines. API docs, UI design, troubleshooting → docs/.
     - Do NOT duplicate rules from /home/rich/dev/CLAUDE.md — they apply automatically. -->

# {{PROJECT_NAME}}

{1-2 sentence description. What this agent does and why it exists.}

## Architecture

```text
Trigger (HTTP / queue / scheduled) → {{PROJECT_NAME}} agent → kermit-harness runtime → LLM/tools → result
```

## Tech Stack

| Component | Language | Framework |
| --------- | -------- | --------- |
| Agent runtime | Python 3.11+ | `kermit-harness>=2.39.1,<3.0.0` |
| Models | Pydantic v2 | type-safe inputs/outputs |
| HTTP client | `httpx` | async-friendly |
| Config | `python-dotenv` | `.env` loading |

Per `/home/rich/dev/CLAUDE.md` Language Architecture Decision Matrix: Python was chosen because this is an AI-intensive component (LLM integration, agent logic, RAG, document processing).

## Build & Run

```bash
# Prerequisites
python3.11 --version
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

# Development
bash scripts/start_dev.sh

# Tests
pytest -m fast
```

## Configuration

Environment variables via `.env` (copy from `.env.example`):

```text
KERMIT_API_KEY=
LOG_LEVEL=info
```

## Ports

This template ships as a CLI/agent (no HTTP surface). If your agent grows an HTTP API, register a port in `/home/rich/dev/CLAUDE.md` Port Allocation Registry first.

## File Structure

```text
{{PROJECT_NAME}}/
├── backend/         # Python package source
│   ├── __init__.py
│   └── agent.py     # Agent logic
├── docs/            # Architecture, API docs, guides
├── scripts/         # start_dev.sh, gate_fast.sh
├── tasks/           # Spec files (output of /plan), lessons.md
├── tests/           # pytest tests
├── main.py          # Entry point
├── pyproject.toml
├── Dockerfile.backend
├── docker-compose.yml
└── .env.example
```

## Rules

{Project-specific rules. Patterns unique to this project. Architectural triage decisions.
Do NOT repeat rules from /home/rich/dev/CLAUDE.md — those apply automatically.}

## Patterns

{Project-specific patterns. Architectural decisions.
Do NOT repeat patterns from /home/rich/dev/CLAUDE.md.}

## Development Workflow

`/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge`

Run `./scripts/gate_fast.sh` before every commit.

## Spec Files

All `tasks/*-spec.md` files MUST use the Phase + Change taxonomy from `/home/rich/dev/CLAUDE.md`:

- Section headers: `## Phase N: <title>`
- Atomic steps: `### Change N: <title>` — N continuous across the whole spec
- One Change → one commit
- Never use killed terms (Section, Task, Step, Item, Sprint, Stage, Iteration, Milestone, Group, Epic)

`scripts/gate_fast.sh` calls `/home/rich/dev/scripts/check_spec_taxonomy.sh` to enforce automatically.
