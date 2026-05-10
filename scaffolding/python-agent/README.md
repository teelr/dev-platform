# {{PROJECT_NAME}}

{One-line purpose — what this agent does and why it exists.}

## Quick Start

```bash
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
# Fill in KERMIT_API_KEY in .env
bash scripts/start_dev.sh
```

## Architecture

Python agent built on `kermit-harness`. The agent reads inputs, calls the
harness runtime (LLM + tools), and produces outputs. See [CLAUDE.md](CLAUDE.md)
for tech stack and rules.

## Configuration

All config via `.env` (copy from `.env.example`). The harness reads
`KERMIT_API_KEY` for LLM auth.

## Development

```bash
bash scripts/start_dev.sh         # run agent loop
bash scripts/gate_fast.sh         # constitutional + lint + typecheck + tests + taxonomy
pytest -m fast                    # offline unit tests
```

Workflow: `/plan → /code → /test → /review → /gate fast → /docs → commit → push` (see `/home/rich/dev/CLAUDE.md`).
