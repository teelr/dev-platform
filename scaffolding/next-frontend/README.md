# {{PROJECT_NAME}}

{One-line purpose — what this frontend does and why it exists.}

## Quick Start

```bash
npm install
cp .env.example .env.local
npm run dev
# Open http://localhost:{{PORT}}
```

## Architecture

Next.js 16 (App Router) + TypeScript + Tailwind 4. See [CLAUDE.md](CLAUDE.md)
for tech stack and rules.

## Configuration

All config via `.env.local` (copy from `.env.example`). Variables prefixed
`NEXT_PUBLIC_` are exposed to the browser; everything else is server-only.

## Development

```bash
npm run dev        # dev server on :{{PORT}}
npm run build      # production build
npm run typecheck  # tsc --noEmit
npm run lint       # ESLint
bash scripts/gate_fast.sh   # constitutional + lint + typecheck + taxonomy
```

Workflow: `/plan → /code → /test → /review → /gate fast → /docs → commit → push` (see `/home/rich/dev/CLAUDE.md`).
