# Rich's Development Standards

All development standards for projects in `/home/rich/dev/projects/`. This is the single source of truth.

## Development Workflow

**CRITICAL — DO NOT ADVANCE STEPS WITHOUT EXPLICIT USER INVOCATION.**

Each step in the workflow requires the user to explicitly invoke it. Completing `/plan` does NOT
mean start `/code`. Completing `/code` does NOT mean start `/test`. Do not infer "natural next
step" and proceed. Stop after each step and wait for the user's command.

**After completing any step: report results only. Do NOT mention, suggest, or hint at the next step. Not even "ready for X when you are." Silence is correct.**

**For any feature touching multiple files or adding a new service:**

```text
/plan → /code → /test → /review → /gate fast → /docs → commit → push
```

- **`/plan`** — Spec before code. Catches missing layers BEFORE implementation.
- **`/code`** — Implements spec task by task. Follows the spec literally — doesn't improvise.
- **`/test`** — Validates with real data. "It compiles" is NOT "it works."
- **`/review`** — Pre-commit code review on staged changes.
- **`/gate fast`** — CRITICAL: runs constitutional checks + unit tests + smoke_fast. Must PASS before commit. A failing gate blocks the commit — fix it first.
- **`/docs`** — CRITICAL: update ALL project docs BEFORE commit. Updates planning.md, ROADMAP.md, README.md, tasks/lessons.md, and any feature-specific docs. Must run after `/gate fast` and before commit.
- **commit** — Conventional commits AFTER `/gate fast` PASS and AFTER `/docs` has updated all project docs. Feature code + doc updates go into ONE atomic commit — not separate "feat" and "docs" commits.
- **push** — Push to GitHub. Create PR if on a branch.

**NEVER commit before `/gate fast` passes. The gate is the last line of defense before the commit lands in history.**

**NEVER commit before `/docs` has run.** Splitting a feature across a "feat" commit and a follow-up "docs" commit pollutes history — a reader browsing `feat:` commits sees stale planning/roadmap state. Bundle docs with the feature they describe.

**Quick fixes (single-file, trivial):** Fix → `/review` → `/gate fast` → commit. No `/docs` needed if no project docs changed.

**Plan mode default:** Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions). If something goes sideways, STOP and re-plan — don't keep pushing. Write detailed specs upfront to reduce ambiguity.

**Verification before done:** Never mark a task complete without proving it works. Ask: "Would a staff engineer approve this?" Run tests, check logs, demonstrate correctness.

## Development Terminology

**These terms are the standard across ALL projects. Use them consistently in specs, docs, commits, and conversation.**

| Level | Term | Definition | Workflow trigger |
| ----- | ---- | ---------- | ---------------- |
| 1 | **Phase** | Major product milestone with exit criteria (Phase 1.0, Phase 1.1, Phase 2) | Roadmap planning |
| 2 | **Spec** | Demoable milestone within a Phase; the output of `/plan`. Artifact lives at `tasks/{descriptive-name}-spec.md` | `/plan` |
| 3 | **Task** | Atomic implementation unit within a Spec; `/code` implements one Task per invocation. Numbered sequentially (Task 1, Task 2...) | `/code` |
| 4 | **Commit** | Git record — feature code + doc updates bundled as one atomic commit | `git commit` |

**Rules:**

- Phase → Spec → Task → Commit. Always. Every project.
- A Phase has exit criteria. A Spec has a demo. A Task has a commit.
- `/plan` produces a Spec. `/code` implements a Task. No other granularities.
- Specs reference Tasks by number: "Task 3" — not "Change 3", "Step 3", "Item 3".
- Progress tables in specs track Tasks. Roadmaps track Phases.
- Spec files are named descriptively: `tasks/foundation-spec.md`, `tasks/auth-layer-spec.md` — not `stage-a-spec.md` or `sprint-1-spec.md`.
- Internal sections within a spec use "Section N:" headers — never "Phase N:" (which is reserved for product milestones).
- Task numbering is 1-indexed within their Spec (Task 1, Task 2...).

**Killed terms (never use as workflow-level labels):** Stage, Change, Sprint, Iteration, Revision, Milestone, Group, Epic.

**Disambiguation:** If a project has a business hierarchy that also uses "Phase" or "Task" (e.g., Keystone's Global → Project → Phase → Task → Sub-Task), always qualify with the project name: "Keystone Phase", "Keystone Task". Bare "Phase" and "Task" in development context always mean the workflow terms above.

## Workflow Principles

**Autonomous bug fixing:** When given a bug report, just fix it. Don't ask for hand-holding. Point at logs, errors, failing tests — then resolve them. Zero context switching required from the user.

**Subagent strategy:** Use subagents to keep main context window clean. Offload research, exploration, and parallel analysis. One task per subagent for focused execution. For complex problems, throw more compute at it.

**Simplicity first:** Make every change as simple as possible. Impact minimal code. No over-engineering — don't add features, refactoring, or "improvements" beyond what was asked.

**No laziness:** Find root causes. No temporary fixes. Senior developer standards.

**Use official SDKs — NEVER hand-roll protocol implementations.** Before building ANY protocol handler, server, or client: check if an official SDK exists. If it does, USE IT. The SDK is maintained by the people who wrote the spec — it is always more correct, more complete, and more maintainable than a custom implementation. Specifically: `a2a-sdk` for A2A protocol, `mcp`/`fastmcp` for MCP protocol, `claude-agent-sdk` for Anthropic agent runtime. Search PyPI/npm/Go modules before writing protocol code.

## Verification Requirements

**You MUST run these checks and fix any issues before marking work complete:**

- Run tests after code changes — all tests must pass
- Run build/typecheck before committing — no errors allowed
- For API changes, test endpoints with curl or the dev server
- For UI changes, start dev server and verify visually in browser
- For any CRUD feature: verify the delete path cleans up ALL storage layers (database, filesystem, cache, search index, in-memory state, message references)
- For any new endpoint: verify it's reachable end-to-end (UI → service call → proxy route → backend endpoint → storage)
- For any delete operation: verify the resource is actually gone (query DB, check filesystem, check indexes — not just "endpoint returned 200")
- For any batch processing: verify the TARGET store has the data, not just the status field. A database status of "complete" is a claim — query the actual destination (ChromaDB, filesystem, API) to confirm.
- For any multi-step pipeline: don't mark step N complete until step N+1's target confirms receipt. Status fields lie when processes crash between writes.

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

## Architectural Triage — Harness vs Consumer (Mandatory Before `/plan`)

For any project that builds on top of `kermit-harness` (Kermit PA, ATLAS,
Keystone agents, future Kermit-based products), every spec session starts
with the architectural triage gate **BEFORE** invoking `/plan`.

**Answer in one sentence each:**

1. **What is this work?** (one-line summary)
2. **Would another harness consumer need a different implementation if they
   wrote it themselves?**
3. **If no → does this belong in the harness or in the consumer?** (almost
   always: harness)
4. **If split (logic in harness, schema/policy in consumer): write two
   specs, not one.**

**Skipping this triage is a CLAUDE.md violation.** A consumer-only spec for
harness-shaped work needs an explicit "Why this can't wait for the harness"
justification.

### Signal patterns — almost always belong in the harness

| If the work is… | …it belongs upstream |
| --- | --- |
| A pure algorithm (chunking, dedup, retry, drain, regex intent detection) | yes |
| An adapter for an external service (LLM, embedding, vector store, reranker) | yes |
| A wrapper that only translates one shape to another (truncation heuristic, dict-to-string normalization) | yes — and the underlying gap is what the harness should fix |
| Lifecycle / orchestration (graceful drain, state machines, restart recovery) | yes |
| LLM-universal response fields (`stop_reason`, token counts, cost) | yes |

### Signal patterns — correctly stay in the consumer

| If the work is… | …it stays in the consumer |
| --- | --- |
| Schema, migrations, ORM models | consumer |
| Frontend components | consumer |
| Consumer-specific business logic, agent personas, domain workflows | consumer |
| Filter policies (tenant scope, project_id, privacy_tier) | consumer |
| MCP tool surfaces specific to the consumer's domain | consumer |

### When consumer-side work is harness-shaped but ships in the consumer anyway

When the harness doesn't yet expose the primitive and waiting blocks user
work, the consumer ships it anyway BUT appends an entry to a per-consumer
handoff queue file (e.g. `tasks/HARNESS_HANDOFF_QUEUE.md`) before the
commit lands. Each entry: feature, where it lives, why it's harness-shaped,
migration plan once the primitive ships.

The handoff queue makes the technical debt explicit and trackable instead
of buried in commit messages. A long Pending list signals that consumer
projects are carrying weight that should be upstream.

### Why this rule exists

Without architectural triage at intake, "build it where the bug surfaced"
becomes the default — and consumers accumulate slightly-different
reimplementations of the same primitives. The Kermit PA April 26 2026
session shipped roughly 40% harness-shaped code in PA before the pattern
was caught (recency intent detection, truncation heuristic, in-flight
task registry, dedup helpers, cascade delete, async/sync wrap pattern).
Every other consumer would have built each one slightly differently.
Triage at intake stops the drift.

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

## Keystone Server Environment

Headless Ubuntu server at `192.168.1.101`. NO monitor, NO keyboard. All development is remote.

**Power schedule:** Server shuts down nightly at 9pm and restarts at 4am for power saving. If services are unreachable, check whether the server is simply powered off. After each restart, containers with `restart: unless-stopped` come back automatically — but manually-stopped containers do not. If a site or service is down after 4am, start the relevant container with `docker compose up -d` from its prod directory.

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
| 8090 | Keystone Dashboard | 8090 |
| 8100s | Keystone Platform | 8100-8190 |
| 8200s | NVR Dashboard | 8200 (backend), 8210 (frontend), 8889 (WebRTC) |
| 8300 | TIS Standalone App | 8300 |
| 9000 | SQRL splash | 9000 |

**Next available series:** 8400s

## Production Deployment Pattern

All production services follow this pattern:

- **Dev:** `/home/rich/dev/projects/X/`
- **Prod:** `/home/rich/prod/X/` (Docker + Traefik)

Infrastructure:

- Traefik reverse proxy on ports 80/443 (`/home/rich/prod/traefik-global/`)
- Let's Encrypt SSL via HTTP challenge (certresolver: `letsencrypt`)
- Cloudflare DNS → Keystone public IP
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
- **Dev workflow** — `/plan → /code → /test → /review → /gate fast → /docs → commit → push` for features. Fix → `/review` → `/gate fast` → commit for quick fixes.
