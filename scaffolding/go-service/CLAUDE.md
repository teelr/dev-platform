<!-- PROJECT CLAUDE.md
     Per /home/rich/dev/CLAUDE.md Project CLAUDE.md Standard:
     - Max 200 lines. API docs, UI design, troubleshooting → docs/.
     - Do NOT duplicate rules from /home/rich/dev/CLAUDE.md — they apply automatically. -->

# {{PROJECT_NAME}}

{1-2 sentence description. What it does and why it exists.}

**Production:** https://{{PROJECT_NAME}}.richteel.com | **Dev:** http://192.168.1.101:{{PORT}}

## Architecture

```text
Client → {{PROJECT_NAME}} (:{{PORT}}) → {downstream services / data stores}
```

## Tech Stack

| Component | Language | Framework |
| --------- | -------- | --------- |
| Backend | Go (latest stable) | chi router (or stdlib `net/http`) |
| Logging | Go | `log/slog` (structured JSON) |
| Config | Go | `os.Getenv` + `joho/godotenv` for `.env` loading |

Per `/home/rich/dev/CLAUDE.md` Language Architecture Decision Matrix: Go was chosen because this is a network-intensive component (HTTP routing / proxy / WebSocket / many concurrent connections).

## Build & Run

```bash
# Prerequisites
go version  # expect 1.22+ (Go modules required)

# Development
bash scripts/start_dev.sh     # runs `go run main.go` with .env loaded

# Production (via Docker)
docker compose up -d --build
```

## Configuration

Environment variables via `.env` (copy from `.env.example`):

```text
PORT={{PORT}}
LOG_LEVEL=info
```

## Ports

| Port | Service | Protocol |
| ---- | ------- | -------- |
| {{PORT}} | {{PROJECT_NAME}} backend | TCP/HTTP |

Register this port in `/home/rich/dev/CLAUDE.md` Port Allocation Registry — separate commit in dev-platform repo. Do NOT use a port outside the registry.

## API Endpoints

| Method | Path | Description |
| ------ | ---- | ----------- |
| GET | `/healthz` | Health check (200 OK if up) |
| GET | `/api/v1/ping` | JSON `{"pong": true}` |

## File Structure

```text
{{PROJECT_NAME}}/
├── backend/         # Go source — split main.go here as it grows
├── docs/            # Architecture, API docs, guides
├── scripts/         # start_dev.sh, gate_fast.sh
├── tasks/           # Spec files (output of /plan), lessons.md
├── tests/           # Go tests
├── main.go          # Entry point — minimal HTTP server
├── go.mod
├── Dockerfile.backend
├── docker-compose.yml
└── .env.example
```

## Rules

{Project-specific rules. Patterns unique to this project.
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
