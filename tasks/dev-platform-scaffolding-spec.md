# R4a — Project Scaffolding

## Coding Specification for Implementation

## Design Philosophy

R4a is the project-scaffolding half of the original R4 Extensions Roadmap Phase. Its purpose is to take "the consistent project skeleton" — currently described prose-only in `dev/CLAUDE.md` (`Standard Project Structure` section) and the `docs/PROJECT_CLAUDE_TEMPLATE.md` template — and turn it into a runnable scaffold that produces a new project from one of three vetted starter templates. After R4a ships, asking the assistant to "create a new Python agent called X" results in a `projects/X/` skeleton that's pre-conformed to every dev-platform standard: workflow rules, language matrix, project structure, taxonomy, gate-fast wiring, project-local Claude/VSCode config.

The scaffold is invoked by the **assistant**, not directly by the user. The flow is conversational: the user describes what they want ("a service that proxies WebSocket traffic to the kermit harness"); the assistant applies the Language Architecture Decision Matrix to pick the template (network-intensive → Go), confirms the choice and handful of inputs (project name, port, optional GitHub repo) with the user, then runs `scripts/new-project.sh <template> <project-name> [--gh-repo public|private]`. The script's job is mechanical: copy template, substitute `{{PROJECT_NAME}}` placeholders, init git, optionally create GitHub repo. The assistant is the design layer; the script is the deterministic deploy layer.

R4a deliberately ships a small fixed template set (3 — go-service, python-agent, next-frontend) and defers Rust CLI, Python service, and additional templates to later cycles. The Language Matrix's three biggest quadrants are covered (network/AI/frontend); the compute quadrant (Rust) waits until you have an actual compute-heavy project that justifies the template. The other quadrants will accrete the same way: when a real need surfaces, add the template; never speculatively before. This is the same "no over-engineering" rule that's pulled into every other dev-platform decision.

R4a also formalizes a Scope-rule carve-out: scaffolding is a SETUP action, distinct from project work. dev-platform's normal Scope rule says *"if a request would require modifying a file under `projects/`, STOP and ask the user to switch to that project's working directory."* That rule has to flex to allow `new-project.sh` to write the initial tree under `projects/<new-name>/` — but only as part of bootstrap, not as a back door for general project work. The carve-out is added inline to the Scope rule so the exception lives WITH the rule it modifies.

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| `scripts/new-project.sh` | Bash | Orchestrator for filesystem + git + gh operations. Shell is the right tool — no concurrency, no parsing complexity, just sequenced commands. Matches the existing `install.sh`/`uninstall.sh`/`verify.sh` pattern. |
| `scaffolding/go-service/*` | Go (template content) | The template ships a runnable Go service skeleton (chi-style HTTP router on a placeholder port). Per the Matrix, network-intensive components are Go. |
| `scaffolding/python-agent/*` | Python (template content) | Template ships a kermit-harness-using agent skeleton. Per the Matrix, AI-intensive components are Python. |
| `scaffolding/next-frontend/*` | TypeScript + React/Next.js (template content) | Template ships a Next.js 16 + Tailwind starter. Per the Matrix, frontend components are TypeScript. |
| `docs/NEW-PROJECT.md` | Markdown | Documentation describing the conversational Q&A pattern the assistant follows before running the script. Read by both humans and assistants; format must be human-friendly. |
| `{{PROJECT_NAME}}` substitution | `sed` | Zero-dependency placeholder replacement. No jinja2/mustache runtime needed; transparent and easy to debug. Pattern matches the rest of dev-platform's "shell-portable, no dependencies" stance. |

## Overview

1. **Phase 1:** Ship the three starter templates under `scaffolding/<name>/` (Changes 1–3)
2. **Phase 2:** Ship the orchestrator script + Q&A pattern docs + Scope-rule carve-out (Changes 4–6)
3. **Phase 3:** Smoke-test the scaffold against a throwaway project name and clean up (Change 7)

**Demo:** the assistant runs `./scripts/new-project.sh python-agent r4a-smoke-test` from `/home/rich/dev/`. The script produces `/home/rich/dev/projects/r4a-smoke-test/` containing a complete Python-agent skeleton with `{{PROJECT_NAME}}` substituted to `r4a-smoke-test` everywhere, an initialized local git repo with one initial commit, no GitHub repo (no `--gh-repo` flag passed), and `cd projects/r4a-smoke-test && bash scripts/start_dev.sh` runs without crashing on first try. The smoke test then `rm -rf`'s the project as part of cleanup so the demo leaves no trace.

---

## Phase 1: Starter Templates

Each template lives under `scaffolding/<template-name>/`. The directory structure mirrors the `Standard Project Structure` section of `dev/CLAUDE.md`. All template files use `{{PROJECT_NAME}}` as the placeholder string for the project's own name; `scripts/new-project.sh` substitutes it via `sed`.

### Change 1: `scaffolding/go-service/` template

**Problem:** When the assistant determines a new project should be a Go service (per the Language Matrix's network-intensive bucket), there's currently no canonical skeleton to copy from. Each new Go service is hand-built or copied from an existing project — drift inevitable.

**File:** `scaffolding/go-service/` (new directory tree)

**Implementation:**

Ship these files inside `scaffolding/go-service/`:

- `CLAUDE.md` — project-specific rules. Start from `docs/PROJECT_CLAUDE_TEMPLATE.md`, fill the Tech Stack section with Go specifics (chi or stdlib for HTTP routing, slog for structured logging, godotenv for env vars), mark the language as Go.
- `.markdownlint.json` — `{"default": false}` (project standard from `dev/CLAUDE.md`).
- `.gitignore` — Go-specific (`*.exe`, `vendor/`, `coverage.out`, `.env`, `bin/`, plus the `tasks/lessons.md` allow-list pattern from existing project gitignores).
- `README.md` — placeholder ~30 lines covering: project name `{{PROJECT_NAME}}`, one-line purpose, Quick Start (`scripts/start_dev.sh`), Architecture, Configuration.
- `go.mod` — `module github.com/teelr/{{PROJECT_NAME}}` + Go version pin (latest stable).
- `main.go` — minimal-but-runnable HTTP server (~40 lines): chi router, `/healthz` endpoint, `/api/v1/ping` endpoint returning JSON, listens on `0.0.0.0:{{PORT}}` (port substituted at scaffold time — see Notes for Implementation).
- `Dockerfile.backend` — multi-stage Go build (golang:alpine builder + distroless runtime).
- `docker-compose.yml` — single-service compose for dev, with `restart: unless-stopped`, joins `traefik-global` network (project-specific Traefik routing — see `dev/CLAUDE.md` Production Deployment Pattern).
- `backend/` — empty subdir with a `.gitkeep` (the project moves `main.go` here as it grows).
- `tests/` — empty subdir with a `.gitkeep`.
- `tasks/` — contains `lessons.md` stub matching the format in `dev/tasks/lessons.md` (header + table with two columns: Date, Lesson, plus | dev-platform | active | rows for project-specific entries).
- `docs/` — empty subdir with a `.gitkeep`.
- `scripts/start_dev.sh` — runs `go run main.go`. Handles common setup (loads `.env` if present, prints listening port).
- `scripts/gate_fast.sh` — runs `go vet ./...`, `go build ./...`, `gofmt -l .` (fails on diff), then calls `bash /home/rich/dev/scripts/check_spec_taxonomy.sh` for taxonomy enforcement.
- `.claude/settings.json` — project-local Claude Code overlay (additive permissions specific to this project, e.g., `Bash(go build *)`, `Bash(go test *)`, `Bash(go run *)`).
- `.vscode/settings.json` — Go-specific IDE settings: `"go.formatTool": "goimports"`, `"go.lintTool": "golangci-lint"`, `"editor.formatOnSave": true` for `*.go`.
- `.env.example` — `PORT={{PORT}}`, plus placeholder for any other env vars.
- `.markdownlint.json` (already listed above).

The Dockerfile, docker-compose.yml, and `.env.example` mirror the existing `kermit-pa` and `RICH_NVR` patterns where applicable — the `/dev/CLAUDE.md` Standard Project Structure section is the contract.

**Acceptance Test:** After scaffold runs against this template, `cd projects/<name> && go build ./... && go vet ./...` exit 0. `bash scripts/start_dev.sh &` starts an HTTP server; `curl http://127.0.0.1:<PORT>/healthz` returns 200; kill the server.

### Change 2: `scaffolding/python-agent/` template

**Problem:** Same as Change 1 but for Python agents (AI-intensive bucket). When the assistant determines a project should consume `kermit-harness` and run agent logic, there's no canonical skeleton.

**File:** `scaffolding/python-agent/` (new directory tree)

**Implementation:**

Ship these files inside `scaffolding/python-agent/`:

- `CLAUDE.md` — Python-agent specific. Reference Standard Project Structure. Tech Stack: Python 3.11+, kermit-harness>=2.39.1, optional FastAPI for HTTP surface, pydantic for models.
- `.markdownlint.json` — `{"default": false}`.
- `.gitignore` — Python-specific (`__pycache__/`, `*.pyc`, `.venv/`, `*.egg-info/`, `.pytest_cache/`, `.mypy_cache/`, `dist/`, `build/`, `.env`).
- `README.md` — ~30 lines: project name `{{PROJECT_NAME}}`, one-line purpose, Quick Start, Architecture, Configuration.
- `pyproject.toml` — package name `{{PROJECT_NAME}}`, depends on `kermit-harness>=2.39.1,<3.0.0` (mandatory per the Architectural Triage rule — formal manifest pin), plus `pydantic`, `httpx`, `python-dotenv`. Build system: `setuptools>=68`. Dev dependencies under `[project.optional-dependencies.dev]`: `pytest`, `pytest-asyncio`, `mypy`, `ruff`, `black`.
- `main.py` — minimal-but-runnable agent loop (~30 lines): loads env, instantiates `KermitRuntime`, runs a one-shot agent call, prints output, exits.
- `backend/__init__.py` — empty.
- `backend/agent.py` — placeholder for the agent's actual logic; ships with one no-op function and a TODO comment.
- `Dockerfile.backend` — multi-stage Python build (python:3.11-slim builder + slim runtime).
- `docker-compose.yml` — same shape as the Go template.
- `tests/__init__.py` — empty.
- `tests/conftest.py` — minimal pytest fixtures (~10 lines).
- `tests/test_smoke.py` — one passing test that imports the package.
- `tasks/lessons.md` — same stub format as the Go template.
- `docs/` — empty subdir with `.gitkeep`.
- `scripts/start_dev.sh` — activates `.venv`, runs `python main.py`. Handles `.env` loading.
- `scripts/gate_fast.sh` — runs `ruff check .`, `mypy backend/`, `pytest -m fast`, then `bash /home/rich/dev/scripts/check_spec_taxonomy.sh`.
- `.claude/settings.json` — project-local overlay: `Bash(python *)`, `Bash(pytest *)`, `Bash(ruff *)`, `Bash(mypy *)`.
- `.vscode/settings.json` — Python-specific: `"python.linting.ruffEnabled": true`, `"python.formatting.provider": "black"`, `"editor.formatOnSave": true` for `*.py`.
- `.env.example` — `KERMIT_API_KEY=`, plus placeholders for any agent-specific config.

**Acceptance Test:** After scaffold runs, `cd projects/<name> && python -m venv .venv && source .venv/bin/activate && pip install -e ".[dev]"` succeeds. `pytest -m fast` exits 0 (one smoke test passes). `python main.py` runs without crashing (it'll print an error if `KERMIT_API_KEY` isn't set; that's acceptable — the import worked).

### Change 3: `scaffolding/next-frontend/` template

**Problem:** Same shape — when the assistant determines a project should be a Next.js frontend, there's no canonical skeleton.

**File:** `scaffolding/next-frontend/` (new directory tree)

**Implementation:**

Ship these files inside `scaffolding/next-frontend/`:

- `CLAUDE.md` — Frontend-specific. Tech Stack: Next.js 16 (App Router), TypeScript strict, Tailwind CSS 4, shadcn/ui patterns.
- `.markdownlint.json` — `{"default": false}`.
- `.gitignore` — Node-specific (`node_modules/`, `.next/`, `out/`, `*.log`, `.env*.local`, `coverage/`).
- `README.md` — ~30 lines.
- `package.json` — name `{{PROJECT_NAME}}`, scripts: `dev`, `build`, `start`, `lint`, `typecheck`. Dependencies: Next.js 16, React 19, Tailwind 4, lucide-react. Dev: `@types/*`, `eslint`, `eslint-config-next`, `prettier`.
- `tsconfig.json` — `"strict": true`, `paths` aliasing for `@/*` to `src/*`, Next.js plugin.
- `next.config.mjs` — minimal Next.js 16 config.
- `tailwind.config.ts` — Tailwind 4 with `@source` directives covering `src/**/*.{ts,tsx,mdx}`.
- `postcss.config.mjs` — Tailwind PostCSS plugin.
- `src/app/layout.tsx` — root layout with `<html>` + `<body>`.
- `src/app/page.tsx` — landing page with the project name `{{PROJECT_NAME}}` displayed.
- `src/app/globals.css` — Tailwind directives + minimal base styles.
- `src/lib/.gitkeep` — empty.
- `src/components/.gitkeep` — empty.
- `public/.gitkeep` — empty.
- `tests/` — empty subdir with `.gitkeep` (test framework choice deferred to project-time; spec doesn't pre-pick vitest vs jest).
- `tasks/lessons.md` — same stub format.
- `docs/` — empty subdir with `.gitkeep`.
- `scripts/start_dev.sh` — runs `npm run dev`.
- `scripts/gate_fast.sh` — runs `npm run lint`, `npm run typecheck`, then `bash /home/rich/dev/scripts/check_spec_taxonomy.sh`.
- `.claude/settings.json` — project-local overlay: `Bash(npm *)`, `Bash(npx *)`, `Bash(node *)`.
- `.vscode/settings.json` — TS/Tailwind-specific: `"editor.defaultFormatter": "esbenp.prettier-vscode"`, `"editor.formatOnSave": true`, `"tailwindCSS.experimental.classRegex"` for clsx.
- `.env.example` — `NEXT_PUBLIC_API_URL=`, port placeholder.

**Acceptance Test:** After scaffold runs, `cd projects/<name> && npm install` succeeds. `npm run typecheck` exits 0. `npm run build` produces a `.next/` directory. `npm run dev &` starts a server; `curl http://127.0.0.1:3000/` returns HTML containing the project name; kill the server.

---

## Phase 2: Orchestrator + Docs + Scope-rule Carve-out

### Change 4: `scripts/new-project.sh`

**Problem:** Without an orchestrator, the templates in `scaffolding/` are static directories — there's no way to instantiate one into a working project. The script is the bridge: it takes a template name and a project name, copies the template, substitutes placeholders, initializes git, optionally creates a GitHub repo.

**File:** `scripts/new-project.sh` (new, executable — `chmod +x`)

**Implementation:**

Bash script following the existing `scripts/install.sh` patterns: `set -euo pipefail`, `REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`, helper functions for sub-steps.

Functional outline:

```bash
#!/usr/bin/env bash
# scripts/new-project.sh — scaffold a new project under projects/<name>/
# from one of the templates in scaffolding/.
#
# Usage:
#   ./scripts/new-project.sh <template> <project-name> [--gh-repo public|private]
#
# Templates (R4a): go-service | python-agent | next-frontend
# Adds future templates by adding a directory under scaffolding/.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${1:-}"
PROJECT_NAME="${2:-}"
GH_REPO_FLAG="${3:-}"     # --gh-repo
GH_REPO_VISIBILITY="${4:-}"  # public | private

# Validate args
[[ -z "${TEMPLATE}" || -z "${PROJECT_NAME}" ]] && { ...usage; exit 1; }
[[ ! -d "${REPO}/scaffolding/${TEMPLATE}" ]] && { ...err; exit 1; }
[[ -d "${REPO}/projects/${PROJECT_NAME}" ]] && { ...err project exists; exit 1; }

# Validate project name (alphanumeric + dash + underscore; no slashes)
[[ ! "${PROJECT_NAME}" =~ ^[a-zA-Z0-9_-]+$ ]] && { ...err invalid name; exit 1; }

# Optional --gh-repo flag
if [[ "${GH_REPO_FLAG}" == "--gh-repo" ]]; then
    [[ "${GH_REPO_VISIBILITY}" != "public" && "${GH_REPO_VISIBILITY}" != "private" ]] && { ...err; exit 1; }
fi

# Copy template
cp -a "${REPO}/scaffolding/${TEMPLATE}/." "${REPO}/projects/${PROJECT_NAME}/"

# Substitute placeholders
find "${REPO}/projects/${PROJECT_NAME}" -type f \( -name "*.md" -o -name "*.json" -o -name "*.toml" -o -name "*.mod" -o -name "*.sh" -o -name "*.go" -o -name "*.py" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mjs" -o -name "*.example" -o -name "Dockerfile*" -o -name "docker-compose*" \) -print0 | xargs -0 sed -i "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g"

# Initialize git
cd "${REPO}/projects/${PROJECT_NAME}"
git init
git add .
git commit -m "feat: initial scaffold from ${TEMPLATE} template

Scaffolded by /home/rich/dev/scripts/new-project.sh from the
${TEMPLATE} template under scaffolding/. Pre-configured for the
dev-platform standard project structure.

Co-Authored-By: dev-platform <noreply@dev-platform>
"

# Optional GitHub repo
if [[ "${GH_REPO_FLAG}" == "--gh-repo" ]]; then
    gh repo create "teelr/${PROJECT_NAME}" --"${GH_REPO_VISIBILITY}" --source=. --push
    echo "  GitHub repo: github.com/teelr/${PROJECT_NAME}"
fi

# Print next-steps checklist
cat <<EOF
Project scaffolded at /home/rich/dev/projects/${PROJECT_NAME}/

Next steps (per docs/NEW-PROJECT.md):
  1. Pick a port from /home/rich/dev/CLAUDE.md Port Allocation Registry
     and substitute it for the {{PORT}} placeholder in:
       - .env.example
       - main.go / main.py / next.config.mjs (depending on template)
       - docker-compose.yml
  2. Register the port in dev/CLAUDE.md Port Allocation Registry
     (separate commit in the dev-platform repo).
  3. Run scripts/gate_fast.sh in the new project to confirm baseline.
  4. /plan the project's first spec.
EOF
```

**Refuse-to-clobber pattern**: same as `install.sh`'s `link_file` — if `projects/<name>/` already exists, error and exit 1, never silently overwrite.

**Sed file-extension list**: comprehensive enough to catch all template content but narrow enough not to mangle binaries. The list above covers the three templates' content. Future templates may need additions.

**Acceptance Test:** Round-trip on a throwaway project name (Phase 3, Change 7).

### Change 5: `docs/NEW-PROJECT.md`

**Problem:** The conversational Q&A pattern that the assistant follows before running `new-project.sh` needs documentation. Without it, the pattern lives only in conversation memory; future sessions (or future-Rich auditing the workflow) have nothing to read.

**File:** `docs/NEW-PROJECT.md` (new)

**Implementation:**

~80 lines covering:

1. **Purpose** — short paragraph: "When you ask the assistant to create a new project, this is what the assistant does and asks before running `scripts/new-project.sh`."
2. **The four questions the assistant asks** before running:
   - **Project name** — derived from your description, but confirmed. Validation: alphanumeric + dash + underscore only; no slashes; not already taken under `projects/`.
   - **Description (one sentence)** — drives template choice via the Language Architecture Decision Matrix. The assistant proposes a template and explains why; pushback expected if the proposal doesn't match your intent.
   - **Port (if a service)** — picked from the Port Allocation Registry in `dev/CLAUDE.md`. The assistant proposes the next available series; you confirm or override.
   - **GitHub repo public or private (or skip)** — opt-in. Default is local-only.
3. **Template selection logic** — table mapping signal patterns to templates:
   - "API gateway / WebSocket / proxy / 1000+ connections" → `go-service`
   - "LLM / RAG / agent / document processing" → `python-agent`
   - "UI / dashboard / browser app / web frontend" → `next-frontend`
4. **The post-scaffold checklist** the assistant prints + walks you through:
   - Substitute the port placeholder (`{{PORT}}`) in template files
   - Register the port in `dev/CLAUDE.md` Port Allocation Registry (a separate commit in dev-platform)
   - Run `scripts/gate_fast.sh` in the new project to confirm baseline
   - `/plan` the project's first spec
5. **What the assistant won't do** — the carve-out's flip side:
   - Won't continue working in the new project from this dev-platform session (Scope rule applies after scaffold)
   - Won't pre-write project-specific code beyond the template
   - Won't decide port assignment unilaterally if the registry is contentious

The doc should reference `scaffolding/<template>/README.md` for per-template specifics (each template's README documents what's in it and how to extend it).

**Acceptance Test:** Read the doc; the four questions, the template selection table, and the post-scaffold checklist are all present in plain language. A new contributor (or future-Rich) can read it and understand what happens when they ask for a new project.

### Change 6: dev/CLAUDE.md Scope-rule carve-out

**Problem:** The current Scope rule in `dev/CLAUDE.md` says the assistant must NOT modify files under `projects/` from a dev-platform session. `scripts/new-project.sh` literally writes new files under `projects/<new-name>/` — so the rule has to flex. The carve-out documents the exception inline so the rule reader sees it without having to follow a pointer.

**File:** `dev/CLAUDE.md` (existing — modify the Scope rule's "Behavioral rule for the assistant" paragraph)

**Implementation:**

Read the current Scope rule's "Behavioral rule for the assistant" paragraph — it contains text like *"If a request would require modifying a file under `projects/`, **STOP and ask the user to switch to that project's working directory** — never silently reach into `projects/` from this session."*

Insert a new sentence (or short paragraph) immediately after that one:

> **Exception — scaffolding:** `scripts/new-project.sh` IS allowed to create the initial tree under `projects/<new-name>/` from a dev-platform session. Scaffolding is a SETUP action via dev-platform tools, distinct from project work. Once the project exists, the normal Scope rule resumes — future edits to that project happen in its own session. Bootstrap-only; not a back door for general project work.

Keep the addition tight (3–4 sentences) so the Scope rule stays readable.

**Acceptance Test:** Read the updated Scope rule; the carve-out is visible inline, doesn't require a separate doc, and clearly distinguishes "bootstrap" from "back door."

---

## Phase 3: Smoke Test + Cleanup

### Change 7: Round-trip smoke test

**Problem:** Before R4a is considered shipped, the orchestrator must successfully scaffold a real project from each of the three templates and verify the basic structure + git init. The smoke test exercises every code path the spec defines.

**File:** none (procedural)

**Implementation:**

```bash
# For each template, scaffold + verify + tear down

for TEMPLATE in go-service python-agent next-frontend; do
    PROJECT="r4a-smoke-${TEMPLATE}"

    # Scaffold (no GitHub repo)
    bash /home/rich/dev/scripts/new-project.sh "${TEMPLATE}" "${PROJECT}"

    # Verify directory structure
    ls /home/rich/dev/projects/"${PROJECT}"/CLAUDE.md
    ls /home/rich/dev/projects/"${PROJECT}"/.gitignore
    ls /home/rich/dev/projects/"${PROJECT}"/README.md
    ls /home/rich/dev/projects/"${PROJECT}"/scripts/start_dev.sh
    ls /home/rich/dev/projects/"${PROJECT}"/scripts/gate_fast.sh

    # Verify {{PROJECT_NAME}} substitution
    ! grep -r "{{PROJECT_NAME}}" /home/rich/dev/projects/"${PROJECT}"/    # expect zero matches
    grep -q "${PROJECT}" /home/rich/dev/projects/"${PROJECT}"/CLAUDE.md   # expect at least one match

    # Verify git init worked
    git -C /home/rich/dev/projects/"${PROJECT}" log --oneline -1          # one commit, "feat: initial scaffold..."

    # Tear down
    rm -rf /home/rich/dev/projects/"${PROJECT}"

    # Verify no residue
    [[ ! -d /home/rich/dev/projects/"${PROJECT}" ]] && echo "  ${TEMPLATE}: clean"
done

# Refuse-to-clobber test
mkdir -p /home/rich/dev/projects/r4a-smoke-clobber
echo "real" > /home/rich/dev/projects/r4a-smoke-clobber/sentinel.txt
bash /home/rich/dev/scripts/new-project.sh python-agent r4a-smoke-clobber 2>&1   # expect non-zero exit, sentinel preserved
[[ -f /home/rich/dev/projects/r4a-smoke-clobber/sentinel.txt ]] && echo "  refuse-to-clobber OK"
rm -rf /home/rich/dev/projects/r4a-smoke-clobber

# Invalid args test
bash /home/rich/dev/scripts/new-project.sh nonexistent-template foo 2>&1   # expect non-zero exit
bash /home/rich/dev/scripts/new-project.sh python-agent "with/slashes" 2>&1   # expect non-zero exit
```

**Acceptance Test:** All three template scaffolds complete, all sub-checks pass, all teardowns leave no residue, refuse-to-clobber preserves the sentinel file, invalid-args cases exit non-zero with clear errors.

---

## Acceptance Criteria

- [ ] `scaffolding/go-service/` exists with the file list specified in Change 1; runnable as a Go HTTP server after scaffold + port substitution.
- [ ] `scaffolding/python-agent/` exists per Change 2; importable Python package after scaffold + `pip install -e .[dev]`.
- [ ] `scaffolding/next-frontend/` exists per Change 3; `npm install && npm run build` succeeds after scaffold.
- [ ] `scripts/new-project.sh` exists, executable, follows the validation + copy + substitute + git init + optional gh-repo flow per Change 4.
- [ ] `docs/NEW-PROJECT.md` exists per Change 5 — covers Q&A pattern, template selection logic, post-scaffold checklist.
- [ ] `dev/CLAUDE.md` Scope rule has the inline scaffolding carve-out per Change 6.
- [ ] Smoke test (Change 7) succeeds: 3 templates × scaffold-verify-teardown + refuse-to-clobber + invalid-args. Zero residue under `projects/` after smoke test.
- [ ] No file under `projects/` exists post-smoke-test that wasn't there before R4a started.
- [ ] `bash -n` passes on `new-project.sh` and all scaffolded `start_dev.sh` / `gate_fast.sh` scripts.
- [ ] `python3 -c "import json; ..."` validates all `*.json` files in templates and the scaffolded outputs.
- [ ] No literal absolute paths leak outside `/home/rich/` (scaffolded `gate_fast.sh` references `/home/rich/dev/scripts/check_spec_taxonomy.sh` deliberately — this matches the existing dev-platform convention).
- [ ] Spec changes bundled with implementation in one atomic commit per project bundling rule.

## Out of Scope (Future Specs)

- **R4b — VSCode user-profile + extensions list.** The other half of the original R4 — `extensions/vscode/settings.json`, `keybindings.json`, `snippets/`, plus `extensions.json` tracking which VSCode extensions are installed and a sync script. Deferred because the remote-SSH client/server split deserves its own design pass.
- **Additional templates.** Rust CLI, Python service, MCP server, terraform module — added when a real project surfaces the need, never speculatively.
- **Auto port assignment.** Currently the assistant + user pick a port from the registry; the script doesn't try to allocate one. Auto-assignment is fragile because the registry is hand-maintained and conflicts are project-context-specific.
- **Template version pinning.** Templates currently track Go/Python/Node versions in their respective manifests; if a template needs an upgrade, edit the file directly. A "template version + migration" system is beyond R4a.
- **GitHub repo settings beyond create.** No branch protection, no required reviews, no Actions setup. Those are post-scaffold per-project decisions.
- **R5 Migration tooling.** Auto-migrating older project layouts to match these templates is R5; R4a only handles greenfield.

## What NOT to Do

- **Do not scaffold into `projects/<name>/` if the directory exists.** Always refuse-to-clobber. Never silently overwrite.
- **Do not write actual project logic in the templates.** Templates ship the SHAPE (directory structure, config files, gate scripts). The first feature spec for the new project writes the actual code via `/plan` and `/code` in that project's own session.
- **Do not invent template-variable substitution beyond `{{PROJECT_NAME}}` and `{{PORT}}`.** Two placeholders are enough for R4a. Adding `{{AUTHOR}}`, `{{LICENSE}}`, `{{DESCRIPTION}}` etc. balloons the substitution logic without proven need.
- **Do not auto-register the port** in `dev/CLAUDE.md` Port Allocation Registry. The registry edit is a separate commit in dev-platform after the scaffold lands. Keeping these two operations separate prevents the script from accidentally polluting the dev-platform repo's git history with project-specific entries.
- **Do not deploy templates via `scripts/install.sh`.** Templates are content for the scaffolder, not symlink targets for `~/.claude/`. They ride in the dev-platform repo but don't get deployed anywhere.
- **Do not add dependencies the templates don't already use.** Each template has a vetted dependency list (chi for Go, kermit-harness for Python, Next.js for TS). Adding more is a per-project decision, not a template-time choice.
- **Do not pre-create all the project's directories.** A `tasks/` subdir with a `lessons.md` stub is enough; don't pre-create `tasks/<feature>-spec.md` placeholders. Specs come via `/plan`.
- **Do not bundle R4b VSCode work.** R4a is scoped narrowly. Resist the temptation to also add `extensions/vscode/...` files because they "naturally fit." That's R4b's spec.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `scaffolding/go-service/*` | New tree | Go service starter (~15 files) |
| `scaffolding/python-agent/*` | New tree | Python agent starter (~17 files) |
| `scaffolding/next-frontend/*` | New tree | Next.js frontend starter (~20 files) |
| `scripts/new-project.sh` | New | Orchestrator script (executable) |
| `docs/NEW-PROJECT.md` | New | Q&A pattern + template selection guide |
| `dev/CLAUDE.md` | Modify | Add scaffolding carve-out to Scope rule |
| `tasks/dev-platform-r4a-scaffolding-spec.md` | (this file) | Spec |

## Implementation Order

1. **Phase 1 (Changes 1–3)** — write the three templates. Independent of each other; can be done in any order or batched. Each template's README + CLAUDE.md is the contract; the rest is content.
2. **Phase 2 (Change 4)** — write `new-project.sh`. Depends on at least one template existing for testing; can be developed alongside Change 3 if convenient.
3. **Phase 2 (Change 5)** — write `docs/NEW-PROJECT.md`. Independent — can be done first or last.
4. **Phase 2 (Change 6)** — update `dev/CLAUDE.md` Scope rule. Independent.
5. **Phase 3 (Change 7)** — smoke test. MUST come last — validates everything else.

Within each Phase, Changes can be batched in a single `/code` session. The whole spec is approximately one full session of work to plan + implement + smoke-test.

## Verification Checklist

- [ ] All 7 Changes implemented per the spec.
- [ ] `bash -n` passes on `scripts/new-project.sh` and all template `scripts/*.sh` files.
- [ ] All `*.json` files in templates parse as valid JSON.
- [ ] All `pyproject.toml`, `package.json`, `go.mod` files in templates parse correctly with their respective tools.
- [ ] Smoke test (Change 7) passes for all 3 templates.
- [ ] Refuse-to-clobber check passes (smoke test sub-step).
- [ ] Invalid-args check passes (smoke test sub-step).
- [ ] No file under `projects/` modified or left behind by the smoke test.
- [ ] `dev/CLAUDE.md` Scope rule has the carve-out paragraph; reading the rule alone is enough to understand the exception.
- [ ] `docs/NEW-PROJECT.md` is readable by humans AND by the assistant — the Q&A pattern is unambiguous.
- [ ] `git status` clean before commit; spec + templates + script + docs bundled in ONE atomic commit per the project bundling rule.
- [ ] No console.log / print() debug code in template content.
- [ ] No hardcoded secrets / passwords / tokens in any template file.

## Notes for Implementation

- **The `{{PORT}}` placeholder is a second substitution.** The script substitutes `{{PROJECT_NAME}}` automatically; `{{PORT}}` is left in place for the user (or assistant in conversation) to fill in post-scaffold. Why two-phase: ports come from a hand-maintained registry, and auto-allocation would be fragile. Documented in `docs/NEW-PROJECT.md` post-scaffold checklist.
- **Smoke-test cleanup is mandatory.** Smoke-test outputs land under `projects/r4a-smoke-*/`. After verification, every smoke project gets `rm -rf`'d. This avoids polluting the projects/ tree with throwaway smoke runs.
- **The carve-out is narrow.** Reading the Scope rule + carve-out side-by-side, the rule's spirit is preserved: dev-platform doesn't reach into existing projects, only creates NEW ones via the explicit scaffolding tool. If the carve-out feels too broad, tighten the wording in Change 6.
- **First scaffold from each template should be tested manually after R4a ships.** Smoke test verifies the structure and git init; full verification (does the Go service actually serve traffic? does the Python agent actually call the harness?) happens in the first real project that uses each template. That's expected — templates are starting points, not finished products.
- **Future R4b VSCode work will need to consider remote-SSH topology.** This dev environment runs over remote-SSH (`.vscode-server/` + `.config/Code/`). When R4b lands, "deploy VSCode config" needs to choose between client-side (unreachable from this Linux box) and server-side (deployable). R4a doesn't touch this; flagging only so R4b's spec session has the context.
- **The `kermit-harness` pin in the Python template is intentional.** Per the Architectural Triage rule in `dev/CLAUDE.md`, every kermit-harness consumer MUST formally declare the dependency in a manifest. The template ships with `>=2.39.1,<3.0.0` to set the right precedent — new Python agent projects start consumer-side compliant.
