# Dev Environment Standardization

## Coding Specification for Implementation

## Design Philosophy

Rich's development environment spans 16 projects in `/home/rich/dev/projects/` on a headless neurX server. The development workflow (`/plan → /code → /test → /review → commit → push`) is enforced by four Claude Code skills defined in `~/.claude/commands/`. The configuration that drives these skills is split across three CLAUDE.md levels: global (`~/.claude/CLAUDE.md`), workspace (`/home/rich/dev/CLAUDE.md`), and per-project (`projects/X/CLAUDE.md`).

The current state has three problems: (1) the global file contains workspace-specific content (data lifecycle rules, verification requirements, language matrix) that belongs at the `/dev` workspace level, (2) the workspace file is a hollow 32-line duplicate of the global, and (3) the `/code` skill contains Kermit-specific container rebuild logic. The WORKFLOW_MANUAL.md references wrong file paths.

This spec reorganizes the hierarchy so that `/home/rich/dev/CLAUDE.md` becomes the **single source of truth** for all development standards. The global file shrinks to Claude behavior preferences only. The skill files get cleaned of project-specific logic. A project CLAUDE.md template is established for consistency. The workflow best practices from Boris Cherny and the user's workflow orchestration principles are woven throughout.

**No code is written. No project logic changes. This is a documentation and configuration reorganization.**

## Language Decisions

| Component | Language | Reasoning |
| --------- | -------- | --------- |
| All files | Markdown | Configuration and documentation only — no application code |

## Overview

1. **Phase 1:** Rewrite `~/.claude/CLAUDE.md` (global — Claude behavior only)
2. **Phase 2:** Rewrite `/home/rich/dev/CLAUDE.md` (workspace — THE source of truth)
3. **Phase 3:** Fix `/code` skill — remove Kermit-specific logic
4. **Phase 4:** Fix `WORKFLOW_MANUAL.md` — correct file paths, add deployment step
5. **Phase 5:** Create project CLAUDE.md template at `/home/rich/dev/docs/PROJECT_CLAUDE_TEMPLATE.md`

---

## Phase 1: Rewrite Global CLAUDE.md

### Change 1: Replace `~/.claude/CLAUDE.md` with Claude behavior config only

**Problem:** The global file currently contains 193 lines mixing Claude behavior preferences with development standards (language matrix, data lifecycle rules, verification requirements). These development standards belong at the workspace level (`/home/rich/dev/CLAUDE.md`) because they're specific to Rich's dev environment, not universal Claude behavior.

**File:** `~/.claude/CLAUDE.md` (existing file, full rewrite)

**Implementation:**

Replace the entire file with a thin Claude behavior config (~40 lines). Keep ONLY:

1. **Response Style** — concise, no emojis, markdown formatting rules
2. **Boris Cherny Feedback Loop** — the self-correction mechanism (this IS Claude behavior)
3. **Self-Improvement Loop** — from workflow orchestration principles: update lessons after corrections, write rules that prevent repeats, review at session start
4. **Demand Elegance** — for non-trivial changes, pause and ask "is there a more elegant way?". Skip for obvious fixes.
5. **Skills Reference** — pointer to `~/.claude/commands/` and to `/home/rich/dev/CLAUDE.md` as the source of truth
6. **Markdown Rules** — blank line after headings, language on code blocks, table spacing, `.markdownlint.json` for new projects

Everything else (language matrix, verification, data lifecycle, code quality, git workflow, planning requirements, patterns) MOVES to Phase 2.

The file should contain this content:

```markdown
# Claude Behavior

These are Claude's operating rules — how to act regardless of project. Development standards live at `/home/rich/dev/CLAUDE.md`.

## Response Style

- Concise, direct. Lead with the answer, not the reasoning.
- No emojis unless explicitly asked.
- When referencing code, include file_path:line_number.

## Boris Cherny Feedback Loop

When corrected on a mistake, fix the SOURCE — not just the symptom.

- Specific bugs → project `tasks/lessons.md` (capped at ~30 entries)
- When 2-3 similar entries point to the same root cause → consolidate into a CLAUDE.md rule, delete the specifics
- After ANY correction: update the relevant instruction file IMMEDIATELY, before continuing work
- Never make the same mistake twice

## Self-Improvement Loop

- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for the relevant project

## Demand Elegance (Balanced)

- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: step back, implement the elegant solution
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

## Markdown Rules

- Blank line after headings (before content)
- Fenced code blocks must specify a language (bash, json, python, etc.)
- Tables must have proper spacing around pipes
- New projects: add `.markdownlint.json` with `{"default": false}`

## Skills & Standards

- Skills are defined in `~/.claude/commands/` (plan.md, code.md, test.md, review.md)
- Workflow manual: `~/.claude/skills/WORKFLOW_MANUAL.md`
- **Development standards (THE source of truth):** `/home/rich/dev/CLAUDE.md`
- Available skills: /plan, /code, /test, /review, /build-fix, /tdd, /permissions
```

**Acceptance Test:**

- File is under 50 lines
- Contains NO language matrix, NO data lifecycle rules, NO verification requirements, NO port assignments
- Contains Boris Cherny feedback loop, self-improvement loop, demand elegance, markdown rules
- Points to `/home/rich/dev/CLAUDE.md` as the source of truth

---

## Phase 2: Rewrite Workspace CLAUDE.md

### Change 2: Replace `/home/rich/dev/CLAUDE.md` with comprehensive development standards

**Problem:** Currently 32 lines, duplicates the global file, adds nothing. Should be THE source of truth for all development standards across all projects.

**File:** `/home/rich/dev/CLAUDE.md` (existing file, full rewrite)

**Implementation:**

Replace with comprehensive development standards (~280 lines). This file absorbs everything that was moved OUT of the global file, plus new content. Structure:

**Section 1: Development Workflow** (~25 lines)
- The full workflow: `/plan → /code → /test → /review → commit → push`
- Each step's purpose (1 line each)
- Quick fix shortcut: fix → /review → commit
- Plan mode default rule: enter plan mode for ANY non-trivial task (3+ steps or architectural decisions). If something goes sideways, STOP and re-plan.
- Verification before done: never mark complete without proving it works. Ask "Would a staff engineer approve this?"

**Section 2: Workflow Principles** (~15 lines)
- Autonomous bug fixing: when given a bug, just fix it. Don't ask for hand-holding.
- Subagent strategy: use subagents to keep main context clean. Offload research and parallel analysis. One task per subagent.
- Simplicity first: make every change as simple as possible. Impact minimal code.
- No laziness: find root causes. No temporary fixes. Senior developer standards.

**Section 3: Verification Requirements** (~15 lines)
- Run tests after code changes
- Build/typecheck before committing
- API changes: test with curl
- UI changes: verify in browser
- CRUD: verify delete cleans ALL storage layers
- New endpoints: trace end-to-end
- Delete operations: verify resource is GONE

**Section 4: Language Architecture Decision Matrix** (~30 lines)
- Move the full matrix table from global
- Decision rules (6 rules)
- Anti-patterns to flag

**Section 5: Code Quality** (~10 lines)
- Small files (200-400 lines, 800 max)
- No console.log in production
- Error handling with try/catch
- Input validation
- No over-engineering

**Section 6: Planning Requirements** (~8 lines)
- Search before writing new code
- Check for existing implementations
- Reuse first

**Section 7: Git Workflow** (~6 lines)
- Conventional commits
- Small, focused commits
- Tests before committing
- /review before every commit

**Section 8: Data Lifecycle & Wiring Rules** (~40 lines)
- Move all 6 rules from global verbatim
- These are workspace lessons from real failures

**Section 9: neurX Server Environment** (~12 lines)
- Headless Ubuntu server at 192.168.1.101
- Network config table: binding (0.0.0.0), service-to-service (127.0.0.1), browser (192.168.1.101)
- WRONG: localhost as default

**Section 10: Port Allocation Registry** (~20 lines)
- Central port registry table with ALL projects
- Rule: each project gets its own port series, no overlap
- Next available series noted

**Section 11: Production Deployment Pattern** (~15 lines)
- Dev at /home/rich/dev/projects/X, prod at /home/rich/prod/X
- Traefik + Let's Encrypt + Cloudflare DNS pattern
- traefik-global network, internal service networks
- ForwardAuth for portal-protected apps

**Section 12: Standard Project Structure** (~20 lines)
- Directory tree based on Kermit pattern
- Required files (CLAUDE.md, .markdownlint.json, .gitignore, README.md)
- Optional files (.env.example, docker-compose.yml, Dockerfiles)

**Section 13: Project CLAUDE.md Standard** (~15 lines)
- Reference to template at docs/PROJECT_CLAUDE_TEMPLATE.md
- Max 200 lines rule
- API docs, UI design, troubleshooting → docs/ directory
- Required sections listed

**Section 14: Patterns** (~8 lines)
- Move patterns from global (single cleanup path, cascade verification, horizontal tracing, create and delete together)
- Add: dev workflow pattern

The full content for this file:

```markdown
# Rich's Development Standards

All development standards for projects in `/home/rich/dev/projects/`. This is the single source of truth.

## Development Workflow

**For any feature touching multiple files or adding a new service:**

```text
/plan → /code → /test → /review → commit → push
```

- **`/plan`** — Spec before code. Catches missing layers BEFORE implementation.
- **`/code`** — Implements spec phase by phase. Follows the spec literally — doesn't improvise.
- **`/test`** — Validates with real data. "It compiles" is NOT "it works."
- **`/review`** — Pre-commit code review on staged changes.
- **commit** — Conventional commits only after /review gives APPROVE.
- **push** — Push to GitHub. Create PR if on a branch.

**Quick fixes (single-file, trivial):** Fix → `/review` → commit.

**Plan mode default:** Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions). If something goes sideways, STOP and re-plan — don't keep pushing. Write detailed specs upfront to reduce ambiguity.

**Verification before done:** Never mark a task complete without proving it works. Ask: "Would a staff engineer approve this?" Run tests, check logs, demonstrate correctness.

## Workflow Principles

**Autonomous bug fixing:** When given a bug report, just fix it. Don't ask for hand-holding. Point at logs, errors, failing tests — then resolve them. Zero context switching required from the user.

**Subagent strategy:** Use subagents to keep main context window clean. Offload research, exploration, and parallel analysis. One task per subagent for focused execution. For complex problems, throw more compute at it.

**Simplicity first:** Make every change as simple as possible. Impact minimal code. No over-engineering — don't add features, refactoring, or "improvements" beyond what was asked.

**No laziness:** Find root causes. No temporary fixes. Senior developer standards.

## Verification Requirements

**You MUST run these checks and fix any issues before marking work complete:**

- Run tests after code changes — all tests must pass
- Run build/typecheck before committing — no errors allowed
- For API changes, test endpoints with curl or the dev server
- For UI changes, start dev server and verify visually in browser
- For any CRUD feature: verify the delete path cleans up ALL storage layers (database, filesystem, cache, search index, in-memory state, message references)
- For any new endpoint: verify it's reachable end-to-end (UI → service call → proxy route → backend endpoint → storage)
- For any delete operation: verify the resource is actually gone (query DB, check filesystem, check indexes — not just "endpoint returned 200")

Do not skip verification. If a check fails, fix it before proceeding.

## Language Architecture Decision Matrix

**Every new component MUST be evaluated against this matrix. No exceptions.**

| Layer | Language | When to Use | Examples |
| ----- | -------- | ----------- | -------- |
| **Network-intensive** | **Go** | High concurrency, many connections, request routing, real-time | API gateways, WebSocket handlers, proxies, CLI tools, health monitors |
| **Compute-intensive** | **Rust** | CPU-bound processing, data transformation, performance-critical | Embedding pipelines, parsing engines, audio/video, compression |
| **AI-intensive** | **Python** | LLM integration, ML workflows, rapid prototyping | RAG pipelines, agent logic, document processing, prompt engineering |
| **UI/Frontend** | **TypeScript** | User interfaces, browser applications | React/Next.js apps, dashboards, browser extensions |

**Decision Rules:**

1. Network-intensive → **Go**
2. Compute-intensive → **Rust**
3. AI-intensive → **Python**
4. Mixed → Split: Go/Rust for I/O and transport, Python for intelligence
5. When in doubt → Python first, rewrite hot path when performance data justifies it

**Anti-patterns to flag:**

- Python handling 1000+ concurrent connections (should be Go)
- Python doing CPU-bound transformation in a tight loop (should be Rust)
- Go/Rust calling LLM APIs directly (should delegate to Python)
- Monolithic services mixing network routing with AI logic (should be split)

## Code Quality

- Many small files over few large files (200-400 lines typical, 800 max)
- No console.log in production code
- Proper error handling with try/catch
- Input validation for all user inputs
- No over-engineering — don't add features beyond what was asked

## Planning Requirements

**Before writing ANY new code:**

- Search the codebase for existing implementations (use Grep/Glob)
- Check if similar functionality already exists
- Identify reusable components, hooks, or utilities
- Follow patterns from existing implementations

Do not reinvent what already exists. Reuse first.

## Git Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`
- Small, focused commits
- Run tests before committing
- `/review` before every commit

## Data Lifecycle & Wiring Rules

**These rules exist because the same failures keep repeating: features built vertically (happy path works) but never wired horizontally (cleanup paths missing, delete doesn't cascade, endpoints unreachable from UI).**

### Rule 1: CRUD Completeness — If You Build Create, You MUST Build Delete

Every data operation must have its inverse. When implementing any create/store/upload operation, implement the corresponding delete/cleanup/remove operation in the SAME work session. The delete MUST clean up ALL storage layers the create touched.

Before marking a CRUD feature complete, answer these three questions:

- If I create this record, what deletes it?
- If I delete this record, is it gone from EVERY storage system? (database, file system, cache, search index, in-memory state, message references)
- If a parent is deleted, what happens to children? (cascade delete, orphan intentionally, or block with error?)

### Rule 2: One Operation, One Code Path

**Never build two functions that do the same thing partially.**

If two endpoints delete the same type of data, they MUST share the same cleanup function. Not `delete_foo()` that cleans A+B and `remove_foo()` that cleans B+C. One canonical `_cleanup_foo()` that cleans A+B+C, called by both.

Before adding a new endpoint for an existing operation, search for existing endpoints that do the same thing. Extend the existing one — don't duplicate.

### Rule 3: Horizontal Wiring Verification

**Every new endpoint must be traceable from UI to storage and back.**

When adding any new feature, trace the complete chain and verify every link:

```text
UI component → Frontend service call → Proxy route → Backend endpoint → Storage layer → Response → UI update
```

If ANY link in this chain is missing, the feature is not done.

### Rule 4: Delete Verification Test

**After implementing any delete operation, verify the thing is GONE.**

1. Query the database — record should not exist
2. Check the filesystem — file should not exist
3. Check any search/vector indexes — documents/chunks should not exist
4. Check in-memory caches — entry should be cleared
5. Try to access the deleted resource via its original endpoint — should get 404

### Rule 5: No Phantom Features

**If a feature cannot be triggered from the UI end-to-end, it does not exist.**

### Rule 6: Status/Enum Consistency

**Every status field must have a defined set of valid values, and code must ONLY use those values.** Need a new value? Add it to the model definition FIRST.

## neurX Server Environment

Headless Ubuntu server at `192.168.1.101`. NO monitor, NO keyboard. All development is remote.

| Context | Use | Example |
| ------- | --- | ------- |
| Service binding | `0.0.0.0` | `uvicorn --host 0.0.0.0` or `chi.ListenAndServe(":8200", r)` |
| Service-to-service | `127.0.0.1` | `http://127.0.0.1:8001/api/endpoint` |
| Browser / client | `192.168.1.101` | `NEXT_PUBLIC_API_URL=http://192.168.1.101:8001` |

**WRONG:** `localhost` as default or fallback in any service. This is a headless server — `localhost` is unreachable from remote clients.

## Port Allocation Registry

Each project gets its own port series. No overlap. Check this table before assigning ports.

| Series | Project | Ports |
| ------ | ------- | ----- |
| 3000 | Kermit frontend | 3000 |
| 4000s | SQRL | 4001 (backend), 4002 (frontend) |
| 5000s | Portal | 5000 (frontend), 5100 (backend) |
| 8000s | Kermit backend | 8001-8021 (backend, agents, MCPs) |
| 8090 | neurX Dashboard | 8090 |
| 8100s | neurX Platform | 8100-8190 |
| 8200s | NVR Dashboard | 8200 (backend), 8210 (frontend), 8889 (WebRTC) |
| 9000 | SQRL splash | 9000 |

**Next available series:** 8300s

## Production Deployment Pattern

All production services follow this pattern:

- **Dev:** `/home/rich/dev/projects/X/`
- **Prod:** `/home/rich/prod/X/` (Docker + Traefik)

Infrastructure:

- Traefik reverse proxy on ports 80/443 (`/home/rich/prod/traefik-global/`)
- Let's Encrypt SSL via HTTP challenge (certresolver: `letsencrypt`)
- Cloudflare DNS → neurX public IP
- Each service joins `traefik-global` network for external routing
- Each service has its own internal network for databases (never exposed on traefik-global)
- Portal ForwardAuth middleware (`kermit-auth@file`) for protected apps

## Standard Project Structure

Based on Kermit pattern. All projects SHOULD have:

```text
project-name/
├── CLAUDE.md              ← Project-specific rules (see template)
├── .markdownlint.json     ← {"default": false}
├── .gitignore
├── .env.example           ← Environment variable template (if env vars used)
├── README.md              ← Purpose, quick start, architecture
├── backend/               ← Backend code (Go/Python/Rust)
├── frontend/              ← Frontend code (Next.js/TypeScript)
├── config/                ← Configuration files
├── docs/                  ← Architecture, API docs, guides
├── scripts/               ← Dev/deploy scripts
├── tasks/                 ← Spec files from /plan, lessons.md
├── tests/                 ← Test files
├── logs/                  ← Application logs (gitignored)
├── docker-compose.yml     ← Dev Docker compose
├── Dockerfile.backend     ← Production backend image
└── Dockerfile.frontend    ← Production frontend image
```

## Project CLAUDE.md Standard

Every project CLAUDE.md should follow the template at `docs/PROJECT_CLAUDE_TEMPLATE.md`.

Rules:

- **Max 200 lines.** API docs, UI design, troubleshooting → `docs/` directory.
- Required sections: description, architecture, tech stack, build & run, configuration, ports, file structure, rules, patterns.
- No duplicating rules from THIS file — project files ADD to these standards, not repeat them.

## Patterns

- **Single cleanup path** — One canonical cleanup function per data type, called by all endpoints that delete that type.
- **Cascade verification** — Parent delete handles all children (deleted, orphaned intentionally, or blocked with error).
- **Horizontal tracing** — Every endpoint traced through all layers before marking complete. Missing links = not done.
- **Create and delete together** — Delete path implemented in the same work session as create.
- **Dev workflow** — `/plan → /code → /test → /review → commit → push` for features. Fix → `/review` → commit for quick fixes.
```

**Acceptance Test:**

- File contains ALL development standards (language matrix, verification, data lifecycle, port registry, deployment pattern, project structure)
- File is ~280 lines
- No duplication with `~/.claude/CLAUDE.md` (global only has Claude behavior)
- Port registry is complete and accurate
- neurX server environment section present
- Production deployment pattern documented

---

## Phase 3: Fix /code Skill

### Change 3: Remove Kermit-specific container rebuild from `/code` skill

**Problem:** Step 4 in `~/.claude/commands/code.md` (lines 43-55) references Kermit-specific paths (`src/kermit/container/**`, `requirements.container.txt`, `agent_schema.json`, `Dockerfile.container`). This breaks the skill for non-Kermit projects.

**File:** `~/.claude/commands/code.md` (existing file, modify lines 43-55)

**Implementation:**

Replace the Kermit-specific Step 4 with a generic container rebuild check:

```markdown
## Step 4: Container Rebuild (if applicable)

After all changes are implemented, check if any modified files affect Docker containers:
- `Dockerfile*`
- `docker-compose*.yml`
- Container-specific dependency files (requirements.txt, go.mod, package.json inside container context)

If YES and containers are running:
1. Rebuild affected containers: `docker compose build <service> && docker compose up -d <service>`
2. Verify the rebuilt container starts and passes health checks
```

**Acceptance Test:**

- No references to `src/kermit/`, `requirements.container.txt`, `agent_schema.json`, or `Dockerfile.container`
- Step 4 is generic and works for any project with Docker
- Step numbering remains consistent (Step 4, Step 5)

---

## Phase 4: Fix WORKFLOW_MANUAL.md

### Change 4: Correct file paths and add deployment step in WORKFLOW_MANUAL.md

**Problem:** `~/.claude/skills/WORKFLOW_MANUAL.md` lines 222-227 reference wrong file paths (`~/.claude/skills/plan/SKILL.md` etc.) when the actual skills are at `~/.claude/commands/plan.md`. Also missing the deployment step in the workflow.

**File:** `~/.claude/skills/WORKFLOW_MANUAL.md` (existing file, modify lines 219-231 and lines 132-175)

**Implementation:**

**Fix 1:** Replace the File Locations section (lines 219-231) with:

```markdown
## File Locations

```
~/.claude/CLAUDE.md                    ← Claude behavior (response style, feedback loop)
~/.claude/commands/plan.md             ← /plan skill definition
~/.claude/commands/code.md             ← /code skill definition
~/.claude/commands/test.md             ← /test skill definition
~/.claude/commands/review.md           ← /review skill definition
~/.claude/skills/WORKFLOW_MANUAL.md    ← This file

/home/rich/dev/CLAUDE.md               ← Development standards (THE source of truth)
./CLAUDE.md                            ← Project-specific rules (per project)
./tasks/                               ← Spec files (per project)
```
```

**Fix 2:** Update the "Workflow: Full Feature Development" section (lines 132-175) to include the push step:

After Step 5 (Commit), add:

```markdown
### Step 6: Push

Push to GitHub. Create a PR if on a feature branch.
```

**Fix 3:** Update the Overview section (line 1-5 area) to reference `/home/rich/dev/CLAUDE.md` instead of `~/.claude/CLAUDE.md` as where the development rules live:

Change: "They read each project's `CLAUDE.md` at runtime to adapt" to also mention "and inherit from `/home/rich/dev/CLAUDE.md` for workspace-wide standards."

**Acceptance Test:**

- File paths match actual locations (`~/.claude/commands/plan.md` not `~/.claude/skills/plan/SKILL.md`)
- `/home/rich/dev/CLAUDE.md` referenced as the source of truth for development standards
- Push step present in the workflow
- No references to wrong file paths

---

## Phase 5: Create Project CLAUDE.md Template

### Change 5: Create project CLAUDE.md template

**Problem:** No standard template exists. Each project invented its own format — RICH_NVR is 159 lines (good), Portal is 768 lines (too long), 7 projects have no CLAUDE.md at all.

**File:** `/home/rich/dev/docs/PROJECT_CLAUDE_TEMPLATE.md` (new file)

**Implementation:**

Create a template that all project CLAUDE.md files should follow. Based on RICH_NVR (the current best example). Include markdown comments explaining what goes in each section:

```markdown
# {Project Name}

{1-2 sentence description. What it does and why it exists.}

**Production:** https://X.richteel.com | **Dev:** http://192.168.1.101:{port}

## Architecture

{ASCII diagram showing components, ports, and data flow. Keep it simple.}

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

{Project-specific rules. Things that have gone wrong before. Things unique to this project.
Do NOT repeat rules from /home/rich/dev/CLAUDE.md — those apply automatically.}

## Patterns

{Established patterns to follow in this project. Architectural decisions.
Do NOT repeat patterns from /home/rich/dev/CLAUDE.md.}
```

Include a header comment in the file:

```markdown
<!-- PROJECT CLAUDE.md TEMPLATE
     Copy this to your project root as CLAUDE.md and fill in the sections.
     Keep under 200 lines. Move API docs, UI design, troubleshooting to docs/.
     Do NOT duplicate rules from /home/rich/dev/CLAUDE.md — they apply automatically. -->
```

**Acceptance Test:**

- File exists at `/home/rich/dev/docs/PROJECT_CLAUDE_TEMPLATE.md`
- All required sections present (architecture, tech stack, build & run, configuration, ports, API endpoints, file structure, rules, patterns)
- Includes guidance comments about what NOT to put in project CLAUDE.md
- Under 100 lines (it's a template, not a filled-in example)

---

### Change 6: Create tasks directory and lessons.md at workspace level

**Problem:** No `tasks/` directory at workspace root. The Boris Cherny / self-improvement loop references `tasks/lessons.md` but it doesn't exist.

**File:** `/home/rich/dev/tasks/lessons.md` (new file)

**Implementation:**

Create a lessons file with header and structure:

```markdown
# Lessons Learned

Patterns from corrections. Reviewed at session start. Consolidated into CLAUDE.md rules when 2-3 similar entries emerge.

## Active Lessons

| Date | Lesson | Project | Status |
| ---- | ------ | ------- | ------ |
| 2026-03-18 | Each project needs its own port series — NVR on 8001 conflicted with Kermit | RICH_NVR | → Rule in dev CLAUDE.md |
```

**Acceptance Test:**

- File exists at `/home/rich/dev/tasks/lessons.md`
- Has table structure for tracking lessons
- First entry references the port conflict lesson (already learned)

---

## What NOT to Do

- **Do NOT modify any project-level CLAUDE.md files** in this spec. Those are separate tasks — this spec only establishes the standard. Projects will be updated individually.
- **Do NOT delete content from global CLAUDE.md without moving it.** Everything currently in the global file must land somewhere in the new hierarchy.
- **Do NOT add project-specific logic to skill files.** The `/code` fix removes Kermit-specific logic — do not replace it with other project-specific logic.
- **Do NOT change the skill definitions' core behavior.** Only fix the container rebuild step in `/code` and the file paths in WORKFLOW_MANUAL.md.
- **Do NOT create `.claude/rules/` files at the workspace level.** Keep all workspace rules in the single `CLAUDE.md` file for simplicity.

## File Change Summary

| File | Action | Description |
| ---- | ------ | ----------- |
| `~/.claude/CLAUDE.md` | Rewrite | Shrink to Claude behavior only (~40 lines) |
| `/home/rich/dev/CLAUDE.md` | Rewrite | Expand to full development standards (~280 lines) |
| `~/.claude/commands/code.md` | Modify | Replace Step 4 with generic container rebuild |
| `~/.claude/skills/WORKFLOW_MANUAL.md` | Modify | Fix file paths, add push step, update references |
| `/home/rich/dev/docs/PROJECT_CLAUDE_TEMPLATE.md` | New | Project CLAUDE.md template |
| `/home/rich/dev/tasks/lessons.md` | New | Workspace lessons file for self-improvement loop |

## Implementation Order

1. Phase 2 first — write workspace CLAUDE.md (so the content exists before we remove it from global)
2. Phase 1 — rewrite global CLAUDE.md (now safe to shrink since content lives in workspace)
3. Phase 3 — fix /code skill
4. Phase 4 — fix WORKFLOW_MANUAL.md
5. Phase 5 — create template and lessons file

## Verification Checklist

- [ ] `~/.claude/CLAUDE.md` is under 50 lines and contains ONLY Claude behavior
- [ ] `/home/rich/dev/CLAUDE.md` contains ALL development standards (language matrix, verification, data lifecycle, port registry, deployment pattern, project structure)
- [ ] No content was deleted without being moved — diff old global against new workspace to confirm
- [ ] `/code` skill has no Kermit-specific references (`src/kermit/`, `requirements.container.txt`, etc.)
- [ ] WORKFLOW_MANUAL.md file paths are correct (`~/.claude/commands/plan.md` not `~/.claude/skills/plan/SKILL.md`)
- [ ] WORKFLOW_MANUAL.md references `/home/rich/dev/CLAUDE.md` as the source of truth
- [ ] Push step present in WORKFLOW_MANUAL.md workflow
- [ ] Project template exists at `/home/rich/dev/docs/PROJECT_CLAUDE_TEMPLATE.md`
- [ ] `tasks/lessons.md` exists at workspace root
- [ ] No duplication between global and workspace CLAUDE.md files
- [ ] All 4 skills (`/plan`, `/code`, `/test`, `/review`) still load correctly (no syntax errors in frontmatter)
