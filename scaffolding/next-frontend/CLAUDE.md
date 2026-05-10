<!-- PROJECT CLAUDE.md
     Per /home/rich/dev/CLAUDE.md Project CLAUDE.md Standard:
     - Max 200 lines. API docs, UI design, troubleshooting → docs/.
     - Do NOT duplicate rules from /home/rich/dev/CLAUDE.md — they apply automatically. -->

# {{PROJECT_NAME}}

{1-2 sentence description. What this frontend does and why it exists.}

**Production:** https://{{PROJECT_NAME}}.richteel.com | **Dev:** http://192.168.1.101:{{PORT}}

## Architecture

```text
Browser → {{PROJECT_NAME}} (Next.js :{{PORT}}) → Backend API
```

## Tech Stack

| Component | Language | Framework |
| --------- | -------- | --------- |
| Framework | TypeScript | Next.js 16 (App Router) |
| Styling | CSS | Tailwind CSS 4 |
| UI patterns | TS/React | shadcn/ui style — copy components, don't import a UI kit |
| Icons | TS | `lucide-react` |
| Linting | TS | ESLint (`eslint-config-next`) + Prettier |

Per `/home/rich/dev/CLAUDE.md` Language Architecture Decision Matrix: TypeScript was chosen because this is a UI/frontend component.

## Build & Run

```bash
# Prerequisites
node --version  # expect 20+
npm --version

# Development
npm install
npm run dev

# Production
npm run build
npm start
```

## Configuration

Environment variables via `.env.local` (copy from `.env.example`). Vars
prefixed `NEXT_PUBLIC_` are exposed to the browser; everything else is
server-only.

```text
NEXT_PUBLIC_API_URL=http://192.168.1.101:{{PORT}}
```

## Ports

| Port | Service | Protocol |
| ---- | ------- | -------- |
| {{PORT}} | {{PROJECT_NAME}} dev server | HTTP |

Register this port in `/home/rich/dev/CLAUDE.md` Port Allocation Registry — separate commit in dev-platform repo.

## File Structure

```text
{{PROJECT_NAME}}/
├── src/
│   ├── app/         # Next.js App Router pages
│   ├── components/  # Reusable React components
│   └── lib/         # Utilities, hooks, API clients
├── public/          # Static assets
├── docs/            # Architecture, UI design, guides
├── scripts/         # start_dev.sh, gate_fast.sh
├── tasks/           # Spec files (output of /plan), lessons.md
├── tests/           # Tests (framework choice deferred to project-time)
├── package.json
├── tsconfig.json
├── next.config.mjs
├── tailwind.config.ts
└── .env.example
```

## Rules

{Project-specific rules. Patterns unique to this project.
Do NOT repeat rules from /home/rich/dev/CLAUDE.md — those apply automatically.}

## Patterns

{Project-specific patterns. Architectural decisions.
Do NOT repeat patterns from /home/rich/dev/CLAUDE.md.}

## Spec Files

All `tasks/*-spec.md` files MUST use the Phase + Change taxonomy from `/home/rich/dev/CLAUDE.md`:

- Section headers: `## Phase N: <title>`
- Atomic steps: `### Change N: <title>` — N continuous across the whole spec
- One Change → one commit
- Never use killed terms (Section, Task, Step, Item, Sprint, Stage, Iteration, Milestone, Group, Epic)

`scripts/gate_fast.sh` calls `/home/rich/dev/scripts/check_spec_taxonomy.sh` to enforce automatically.
