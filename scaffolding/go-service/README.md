# {{PROJECT_NAME}}

{One-line purpose — what this service does and why it exists.}

## Quick Start

```bash
# Install Go (1.22+) if not already installed.
cp .env.example .env
bash scripts/start_dev.sh
# Server listens on :{{PORT}}
curl http://127.0.0.1:{{PORT}}/healthz
```

## Architecture

Go HTTP service. Routes via chi (or stdlib `net/http` — see `main.go`).
Listens on port `{{PORT}}` (configured via `PORT` env var).

See [CLAUDE.md](CLAUDE.md) for tech stack, ports, and rules.

## Configuration

All config via `.env` (copy from `.env.example`). Production deployment uses
the same env vars but loads them from the orchestration layer (Docker
Compose / Kubernetes secrets / etc.) rather than a `.env` file.

## Development

```bash
bash scripts/start_dev.sh         # run dev server
bash scripts/gate_fast.sh         # constitutional + lint + build + taxonomy
go test ./...                     # tests
```

Workflow: `/plan → /code → /review → /gate fast → commit → push → /pr → CI → /merge → post-merge` (see `/home/rich/dev/CLAUDE.md`).
